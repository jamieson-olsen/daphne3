-- stc3.vhd
-- self triggered channel machine for ONE DAPHNE channel
--
-- updated for DAPHNE3 using new backend 10G Ethernet sender block
-- this block handles buffering of output data, so FIFO has been removed from this module
-- and has been replaced with a single UltraScale+ UltraRAM block
-- 
-- This module watches one channel data bus and computes the average signal level 
-- (baseline.vhd) based on the last N samples. When it detects a trigger condition
-- (defined in trig.vhd) it then begins assemblying the output frame IN MEMORY and when done,
-- begins clocking the data out directly, using a 64 bit wide bus.

-- Jamieson Olsen <jamieson@fnal.gov>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

library xpm;
use xpm.vcomponents.all;

entity stc3 is
generic( 
    link_id: std_logic_vector(5 downto 0) := "000000"; 
    ch_id: std_logic_vector(5 downto 0) := "000000";
    slot_id: std_logic_vector(3 downto 0) := "0010";
    crate_id: std_logic_vector(9 downto 0) := "0000000011";
    detector_id: std_logic_vector(5 downto 0) := "000010";
    version_id: std_logic_vector(5 downto 0) := "000011";
    runlength: integer := 256 -- baseline runlength must one one of 32,64,128,256
);
port(
    clock: in std_logic; -- master clock 62.5MHz
    reset: in std_logic;
    threshold: std_logic_vector(13 downto 0); -- trig threshold relative to calculated baseline
    enable: in std_logic; 
    timestamp: in std_logic_vector(63 downto 0);
	din: in std_logic_vector(13 downto 0); -- aligned AFE data
    dout: out std_logic_vector(63 downto 0);
    valid: out std_logic;
    last: out std_logic
);
end stc3;

architecture stc3_arch of stc3 is

    signal din_dly32_i, din_dly64_i, din_dly96_i, din_dly: std_logic_vector(13 downto 0);
    signal R0, R1, R2, R3, R4, R5: std_logic_vector(13 downto 0);
    signal block_count: integer range 0 to 31 := 0;

    type state_type is (rst, wait4trig, w0, w1, w2, w3, w4, w5, w6,
                        d0, d1, d2, d3, d4, d5, d6, d7, d8, d9, d10, d11, d12, d13, d14, d15, 
                        d16, d17, d18, d19, d20, d21, d22, d23, d24, d25, d26, d27, d28, d29, d30, d31,
                        h0, h1, h2, h3, h4, h5, h6, h7, h8,
                        hold0, hold1, dump0, dump1);
    signal state: state_type;

    signal ts_reg: std_logic_vector(63 downto 0) := (others=>'0');
    signal bline, trigsample: std_logic_vector(13 downto 0) := (others=>'0');
    signal triggered: std_logic := '0';

    signal dina: std_logic_vector(63 downto 0) := (others=>'0');
    signal ena: std_logic := '0';
    signal wea: std_logic_vector(0 downto 0) := "0";
    signal addra: std_logic_vector(7 downto 0) := X"00";

    signal enb: std_logic := '0';
    signal addrb: std_logic_vector(7 downto 0) := X"00";

    component baseline
    generic( runlength: integer := 256 );
    port(
        clock: in std_logic;
        reset: in std_logic;
        din: in std_logic_vector(13 downto 0);
        bline: out std_logic_vector(13 downto 0));
    end component;

    component trig
    port(
        clock: in std_logic;
        din: in std_logic_vector(13 downto 0);
        baseline: in std_logic_vector(13 downto 0);
        threshold: in std_logic_vector(13 downto 0);
        triggered: out std_logic;
        trigsample: out std_logic_vector(13 downto 0));
    end component;

begin

    -- delay input data by 128 clocks to compensate for 64 clock trigger latency 
    -- and also for capturing 64 pre-trigger samples

    gendelay: for i in 13 downto 0 generate

        srlc32e_0_inst : srlc32e
        port map(
            clk => clock,
            ce => '1',
            a => "11111",
            d => din(i), -- live AFE data
            q => open,
            q31 => din_dly32_i(i) -- live data delayed 32 clocks
        );
    
        srlc32e_1_inst : srlc32e
        port map(
            clk => clock,
            ce => '1',
            a => "11111",
            d => din_dly32_i(i),
            q => open,
            q31 => din_dly64_i(i) -- live data delayed 64 clocks
        );

        srlc32e_2_inst : srlc32e
        port map(
            clk => clock,
            ce => '1',
            a => "11111",
            d => din_dly64_i(i),
            q => open,
            q31 => din_dly96_i(i) -- live data delayed 96 clocks
        );

        srlc32e_3_inst : srlc32e
        port map(
            clk => clock,
            ce => '1',
            a => "11111",
            d => din_dly96_i(i),
            q => open,
            q31 => din_dly(i) -- live data delayed 128 clocks
        );

    end generate gendelay;

    -- compute the average signal baseline level over the last N samples

    baseline_inst: baseline
    generic map ( runlength => runlength ) -- must be 32, 64, 128, or 256
    port map(
        clock => clock,
        reset => reset,
        din => din, -- this looks at LIVE AFE data, not the delayed data
        bline => bline
    );

    -- for dense data packing, we need to access up to last 6 samples at once...

    pack_proc: process(clock)
    begin
        if rising_edge(clock) then
            R0 <= din_dly;
            R1 <= R0;
            R2 <= R1;
            R3 <= R2;
            R4 <= R3;
            R5 <= R4;
        end if;
    end process pack_proc;       

    -- trigger algorithm in a separate module. this latency is assumed to be 64 cycles

    trig_inst: trig
    port map(
         clock => clock,
         din => din, -- watching live AFE data
         baseline => bline,
         threshold => threshold,
         triggered => triggered,
         trigsample => trigsample -- the ADC sample that caused the trigger 
    );        

    -- big FSM waits for trigger condition then dense pack assembly of the output frame 
    -- in memory, then jumps back and fills in the header.

    -- one BLOCK = 32 14-bit samples DENSE PACKED into 7 64-bit words
    -- one SUPERBLOCK = 32 blocks = 1024 samples = 224 64 bit words

    builder_fsm_proc: process(clock)
    begin
        if rising_edge(clock) then
            if (reset='1') then
                state <= rst;
            else
                case(state) is
                    when rst =>
                        state <= wait4trig;
                    when wait4trig => 
                        if (triggered='1' and enable='1') then -- start packing
                            block_count <= 0;
                            ts_reg <= std_logic_vector( unsigned(timestamp) - 125 ); -- this offset is fixed and determined by simulation
                            state <= w0; 
                        else
                            state <= wait4trig;
                        end if;

                    when w0 => state <= w1; -- wait states
                    when w1 => state <= w2;
                    when w2 => state <= w3;
                    when w3 => state <= w4;
                    when w4 => state <= w5;
                    when w5 => state <= w6;
                    when w6 => 
                        addra <= X"09"; -- address of first data word in output buffer
                        state <= d0;

                    when d0 => state <= d1;
                    when d1 => state <= d2;
                    when d2 => state <= d3;
                    when d3 => state <= d4;
                    when d4 => state <= d5; addra <= std_logic_vector(unsigned(addra)+1);
                    when d5 => state <= d6;
                    when d6 => state <= d7;
                    when d7 => state <= d8;
                    when d8 => state <= d9; addra <= std_logic_vector(unsigned(addra)+1);
                    when d9 => state <= d10;
                    when d10 => state <= d11;
                    when d11 => state <= d12;
                    when d12 => state <= d13;
                    when d13 => state <= d14; addra <= std_logic_vector(unsigned(addra)+1);
                    when d14 => state <= d15;
                    when d15 => state <= d16;
                    when d16 => state <= d17;
                    when d17 => state <= d18; addra <= std_logic_vector(unsigned(addra)+1);
                    when d18 => state <= d19;
                    when d19 => state <= d20;
                    when d20 => state <= d21;
                    when d21 => state <= d22;
                    when d22 => state <= d23; addra <= std_logic_vector(unsigned(addra)+1);
                    when d23 => state <= d24;
                    when d24 => state <= d25;
                    when d25 => state <= d26;
                    when d26 => state <= d27; addra <= std_logic_vector(unsigned(addra)+1);
                    when d27 => state <= d28;
                    when d28 => state <= d29;
                    when d29 => state <= d30;
                    when d30 => state <= d31;

                    when d31 =>
                        if (block_count=31) then -- done with packing data samples, update header info
                            state <= h0;
                            addra <= X"00"; -- address of header word 0
                        else
                            block_count <= block_count + 1;
                            state <= d0;
                            addra <= std_logic_vector(unsigned(addra)+1);
                        end if;

                    -- jump back in and fill in the header information in the buffer

                    when h0 => 
                        state <= h1; 
                        addra <= std_logic_vector(unsigned(addra)+1);
                    when h1 => 
                        state <= h2;
                        addra <= std_logic_vector(unsigned(addra)+1);
                    when h2 => 
                        state <= h3;
                        addra <= std_logic_vector(unsigned(addra)+1);
                    when h3 =>
                        state <= h4;
                        addra <= std_logic_vector(unsigned(addra)+1);
                    when h4 =>
                        state <= h5;
                        addra <= std_logic_vector(unsigned(addra)+1);
                    when h5 =>
                        state <= h6;
                        addra <= std_logic_vector(unsigned(addra)+1);
                    when h6 =>
                        state <= h7;
                        addra <= std_logic_vector(unsigned(addra)+1);
                    when h7 =>
                        state <= h8;
                        addra <= std_logic_vector(unsigned(addra)+1);
                    when h8 =>
                        state <= hold0;

                    when hold0 => -- wait a moment for the last writes into the buffer to finish
                        state <= hold1;
                    when hold1 =>
                        state <= dump0;
                        addrb <= X"00";
                        enb <= '1';

                    when dump0 => -- read out the buffer, dump memory locations 0-223 to output
                        if (addrb=X"DF") then
                            state <= dump1;
                            last <= '1';
                        else
                            state <= dump0;
                            addrb <= std_logic_vector(unsigned(addrb)+1);
                        end if;

                    when dump1 => -- done dumping output buffer
                        enb <= '0';
                        last <= '0';
                        state <= wait4trig;                    

                    when others => 
                        state <= rst;
                end case;
            end if;
        end if;
    end process builder_fsm_proc;

    -- mux to determine what is written into the output buffer 

    dina <= X"00000000" & link_id & slot_id & crate_id & detector_id & version_id when (state=h0) else
            ts_reg(63 downto 0) when (state=h1) else
            "0000000000" & ch_id & "00" & bline & "00" & threshold & "00" & trigsample when (state=h2) else
            -- add header 3 through header 8 assignments here...
            ( R0(7 downto 0) & R1 & R2 & R3 & R4)                     when (state=d0) else -- sample4l ... sample0
            ( R0(1 downto 0) & R1 & R2 & R3 & R4 & R5(13 downto 8) )  when (state=d5) else -- sample9l ... sample4h
            ( R0(9 downto 0) & R1 & R2 & R3 & R4(13 downto 2) )       when (state=d9) else -- sample13l ... sample9h
            ( R0(3 downto 0) & R1 & R2 & R3 & R4 & R5(13 downto 10) ) when (state=d14) else -- sample18l ... sample13h
            ( R0(11 downto 0) & R1 & R2 & R3 & R4(13 downto 4) )      when (state=d18) else -- sample22l ... sample18h
            ( R0(5 downto 0) & R1 & R2 & R3 & R4 & R5(13 downto 12) ) when (state=d23) else -- sample27l ... sample22h
            ( R0 & R1 & R2 & R3 & R4(13 downto 6) )                   when (state=d27) else -- sample31 ... sample27h
            X"0000000000000000";

    wea <= "1" when (state=h0) else  -- wea is only 1 bit, but needs to be std_logic_vector
           "1" when (state=h1) else
           "1" when (state=h2) else
           "1" when (state=h3) else
           "1" when (state=h4) else
           "1" when (state=h5) else
           "1" when (state=h6) else
           "1" when (state=h7) else
           "1" when (state=h8) else
           "1" when (state=d0) else
           "1" when (state=d5) else
           "1" when (state=d9) else
           "1" when (state=d14) else
           "1" when (state=d18) else
           "1" when (state=d23) else
           "1" when (state=d27) else
           "0";

    ena <= '0' when (state=rst) else
           '0' when (state=wait4trig) else 
           '1';

-- ultraram buffer is simple dual port, port A for writing, port B for reading
-- data width is 64 bits. common clock. disable sleep for now.
-- ultraram is 288kbits but we don't need all of this here. for now keep it simple and 
-- buffer up just one event, so we need 224 locations each is 64 bits. call it 256 x 64 = 16384 bits
-- address fields are 8 bits

-- xpm_memory_sdpram: Simple Dual Port RAM
-- Xilinx Parameterized Macro, version 2024.1

xpm_memory_sdpram_inst : xpm_memory_sdpram
generic map (
   ADDR_WIDTH_A => 8, -- 256 addresses each is 64 data bits wide
   ADDR_WIDTH_B => 8,
   AUTO_SLEEP_TIME => 0,          
   BYTE_WRITE_WIDTH_A => 64, -- read and write whole 64-bit words only
   CASCADE_HEIGHT => 0,
   CLOCKING_MODE => "common_clock",
   ECC_BIT_RANGE => "7:0",
   ECC_MODE => "no_ecc",            
   ECC_TYPE => "none",              
   IGNORE_INIT_SYNTH => 0,          
   MEMORY_INIT_FILE => "none",      
   MEMORY_INIT_PARAM => "0",        
   MEMORY_OPTIMIZATION => "true",   
   MEMORY_PRIMITIVE => "ultra",     
   MEMORY_SIZE => 16384,             
   MESSAGE_CONTROL => 0,            
   RAM_DECOMP => "auto",            
   READ_DATA_WIDTH_B => 64,         
   READ_LATENCY_B => 2,             
   READ_RESET_VALUE_B => "0",       
   RST_MODE_A => "SYNC",            
   RST_MODE_B => "SYNC",            
   SIM_ASSERT_CHK => 0, -- 0=disable simulation messages, 1=enable simulation messages
   USE_EMBEDDED_CONSTRAINT => 0,    
   USE_MEM_INIT => 1,               
   USE_MEM_INIT_MMI => 0,           
   WAKEUP_TIME => "disable_sleep",  
   WRITE_DATA_WIDTH_A => 64,        
   WRITE_MODE_B => "no_change",     
   WRITE_PROTECT => 1               
)
port map (
   dbiterrb => open,
   doutb => dout,
   sbiterrb => open,
   addra => addra,
   addrb => addrb,
   clka => clock,
   clkb => '0', -- unused in common clock mode
   dina => dina,
   ena => ena,
   enb => enb,
   injectdbiterra => '0',
   injectsbiterra => '0',
   regceb => '1',
   rstb => '0',
   sleep => '0',
   wea => wea -- one bit std_logic_vector
);

end stc3_arch;
