-- stc3.vhd
-- self triggered channel machine for ONE DAPHNE channel
--
-- updated again: the backend FIFO returns! The merge logic has been removed from
-- Adam's 10G sender and is now under control in the DAPHNE core logic.
-- 
-- This module watches one channel data bus and computes the average signal level 
-- (baseline.vhd) based on the last N samples. When it detects a trigger condition
-- (defined in trig.vhd) it then begins assemblying the output frame in the output FIFO.
-- The output FIFO is UltraRAM based and is a single clock domain.

-- the trigger module provided here is very basic and is intended as a placeholder
-- to simulate a more advanced trigger which has a total latency of 128 clock cycles.

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
    runlength: integer := 256; -- baseline runlength must be one of: 32, 64, 128, 256
    threshold: std_logic_vector(13 downto 0):= "00001111101000" -- trig threshold relative to calculated baseline
);
port(
    clock: in std_logic; -- master clock 62.5MHz
    reset: in std_logic;
    enable: in std_logic;
    forcetrig: in std_logic; -- force a trigger
    timestamp: in std_logic_vector(63 downto 0);
	din: in std_logic_vector(13 downto 0); -- aligned AFE data

    FIFO_rd_en: in std_logic; -- output FIFO read enable
    FIFO_dout: out std_logic_vector(71 downto 0); -- output FIFO data
    FIFO_empty: out std_logic -- output FIFO flag
);
end stc3;

architecture stc3_arch of stc3 is

type array_11x14_type is array(10 downto 0) of std_logic_vector(13 downto 0);
signal din_delay: array_11x14_type;

signal R0, R1, R2, R3, R4, R5: std_logic_vector(13 downto 0);
signal block_count: integer range 0 to 31 := 0;

type state_type is (rst, wait4trig, w0, w1, w2, w3, h0, h1, h2, h3, h4, h5, h6, h7, h8, 
                    d0, d1, d2, d3, d4, d5, d6, d7, d8, d9, d10, d11, d12, d13, d14, d15, 
                    d16, d17, d18, d19, d20, d21, d22, d23, d24, d25, d26, d27, d28, d29, d30, d31);
signal state: state_type;

signal trig_ts: std_logic_vector(63 downto 0) := (others=>'0');
signal bline, trig_sample: std_logic_vector(13 downto 0) := (others=>'0');
signal triggered, forcetrig_reg: std_logic := '0';
signal FIFO_din: std_logic_vector(71 downto 0) := (others=>'0');
signal FIFO_wr_en, FIFO_sleep: std_logic := '0';

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
    ts: in std_logic_vector(63 downto 0);
    baseline: in std_logic_vector(13 downto 0);
    threshold: in std_logic_vector(13 downto 0);
    trig: out std_logic;
    trig_sample: out std_logic_vector(13 downto 0);
    trig_ts: out std_logic_vector(63 downto 0)
);
end component;

begin

-- assume trigger latency is 256 clocks
-- + 64 pre-trigger samples = total delay is 320 clocks!
-- use 32 bit shift register primitives (srlc32e) for this

din_delay(0) <= din;

gen_delay_bit: for b in 13 downto 0 generate
    gen_delay_srlc: for s in 9 downto 0 generate

        srlc32e_0_inst : srlc32e
        port map(
            clk => clock,
            ce => '1',
            a => "11111",
            d => din_delay(s)(b),
            q => open,
            q31 => din_delay(s+1)(b)
        );

    end generate gen_delay_srlc;
end generate gen_delay_bit;

-- din_delay(0)(13..0) = din(13..0) live no delay
-- din_delay(1)(13..0) = din(13..0) delayed by 32 clocks
-- din_delay(2)(13..0) = din(13..0) delayed by 64 clocks
-- ...
-- din_delay(10)(13..0) = din(13..0) delayed by 320 clocks

-- now compute the average signal baseline level over the last N samples

baseline_inst: baseline
generic map ( runlength => runlength ) -- must be 32, 64, 128, or 256
port map(
    clock => clock,
    reset => reset,
    din => din_delay(0), -- this looks at LIVE AFE data, not the delayed data
    bline => bline
);

-- trig may be an async signal, clean it up here

trig_proc: process(clock)
begin
    if rising_edge(clock) then
        forcetrig_reg <= forcetrig;
    end if;
end process trig_proc;     

-- for dense data packing 14 bit samples into 64 bit words,
-- we need to access up to last 6 samples at once...

pack_proc: process(clock)
begin
    if rising_edge(clock) then
        R0 <= din_delay(10);
        R1 <= R0;
        R2 <= R1;
        R3 <= R2;
        R4 <= R3;
        R5 <= R4;
    end if;
end process pack_proc;       

-- trigger module latency is FIXED at 128 clocks:

trig_inst: trig
port map(
     clock => clock,
     din => din_delay(0), -- watching live AFE data
     ts => timestamp,
     baseline => bline,
     threshold => threshold,
     trig => triggered,
     trig_sample => trig_sample, 
     trig_ts => trig_ts 
);        

-- big FSM waits for trigger condition then dense pack assembly of the output frame 
-- as it is being written to the output FIFO *IN ORDER* (there is no "jumping back" to update
-- the header!)

-- one BLOCK = 32 14-bit samples DENSE PACKED into 7 64-bit words
-- one SUPERBLOCK = 32 blocks = 1024 samples = 224 64 bit words

-- sample0 is the first sample packed into the output record
-- sample0...sample63 = pretrigger
-- sample64 = trigger sample
-- sample65...sample1023 = post trigger
-- the timestamp value recorded in the output record corresponds to sample0 NOT the trigger sample!

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
                    if ((triggered='1' or forcetrig_reg='1') and enable='1') then -- start packing
                        block_count <= 0;
                        state <= w0; 
                    else
                        state <= wait4trig;
                    end if;

                when w0 => state <= w1; -- a few wait states while the FIFO wakes up from sleep mode...
                when w1 => state <= w2;
                when w2 => state <= w3;
                when w3 => state <= h0;                   

                -- begin assembly of output record 
                -- the output buffer is a FIFO so this MUST be done IN ORDER!

                when h0 => state <= h1; -- header words
                when h1 => state <= h2;
                when h2 => state <= h3;
                when h3 => state <= h4;
                when h4 => state <= h5;
                when h5 => state <= h6;
                when h6 => state <= h7;
                when h7 => state <= h8;
                when h8 => state <= d0;

                when d0 => state <= d1; -- begin dense pack data block
                when d1 => state <= d2;
                when d2 => state <= d3;
                when d3 => state <= d4;
                when d4 => state <= d5; 
                when d5 => state <= d6;
                when d6 => state <= d7;
                when d7 => state <= d8;
                when d8 => state <= d9; 
                when d9 => state <= d10;
                when d10 => state <= d11;
                when d11 => state <= d12;
                when d12 => state <= d13;
                when d13 => state <= d14; 
                when d14 => state <= d15;
                when d15 => state <= d16;
                when d16 => state <= d17;
                when d17 => state <= d18; 
                when d18 => state <= d19;
                when d19 => state <= d20;
                when d20 => state <= d21;
                when d21 => state <= d22;
                when d22 => state <= d23;
                when d23 => state <= d24;
                when d24 => state <= d25;
                when d25 => state <= d26;
                when d26 => state <= d27;
                when d27 => state <= d28;
                when d28 => state <= d29;
                when d29 => state <= d30;
                when d30 => state <= d31;

                when d31 =>
                    if (block_count=31) then -- done with packing data samples, return to idle
                        state <= wait4trig;
                    else
                        block_count <= block_count + 1;
                        state <= d0;
                    end if;

                when others => 
                    state <= rst;
            end case;
        end if;
    end if;
end process builder_fsm_proc;

-- mux to determine what is written into the output FIFO, note this is 72 bits to match ultraram bus
-- this output FIFO is deep enough to hold MANY output records
-- set the upper byte to 0xFF to mark the first word of each record (makes downstream selection logic easier)

FIFO_din <= X"FF00000000" & link_id & slot_id & crate_id & detector_id & version_id when (state=h0) else
            X"00" & trig_ts when (state=h1) else
            X"00" & "0000000000" & ch_id & "00" & bline & "00" & threshold & "00" & trig_sample when (state=h2) else
            -- reserved for header 3 (all zeros)
            -- reserved for header 4 (all zeros)
            -- reserved for header 5 (all zeros)
            -- reserved for header 6 (all zeros)
            -- reserved for header 7 (all zeros)
            -- reserved for header 8 (all zeros)
            X"00" & R0(7 downto 0) & R1 & R2 & R3 & R4                    when (state=d0) else -- sample4l ... sample0
            X"00" & R0(1 downto 0) & R1 & R2 & R3 & R4 & R5(13 downto 8)  when (state=d5) else -- sample9l ... sample4h
            X"00" & R0(9 downto 0) & R1 & R2 & R3 & R4(13 downto 2)       when (state=d9) else -- sample13l ... sample9h
            X"00" & R0(3 downto 0) & R1 & R2 & R3 & R4 & R5(13 downto 10) when (state=d14) else -- sample18l ... sample13h
            X"00" & R0(11 downto 0) & R1 & R2 & R3 & R4(13 downto 4)      when (state=d18) else -- sample22l ... sample18h
            X"00" & R0(5 downto 0) & R1 & R2 & R3 & R4 & R5(13 downto 12) when (state=d23) else -- sample27l ... sample22h
            X"00" & R0 & R1 & R2 & R3 & R4(13 downto 6)                   when (state=d27) else -- sample31 ... sample27h
            X"000000000000000000";

-- output FIFO write enable

FIFO_wr_en <= '1' when (state=h0) else  
              '1' when (state=h1) else
              '1' when (state=h2) else
              '1' when (state=h3) else
              '1' when (state=h4) else
              '1' when (state=h5) else
              '1' when (state=h6) else
              '1' when (state=h7) else
              '1' when (state=h8) else
              '1' when (state=d0) else
              '1' when (state=d5) else
              '1' when (state=d9) else
              '1' when (state=d14) else
              '1' when (state=d18) else
              '1' when (state=d23) else
              '1' when (state=d27) else
              '0';

FIFO_sleep <= '1' when (state=rst) else
              '1' when (state=wait4trig) else
              '0';

-- UltraRAM sync FIFO macro
-- 4k words deep x 72 bits wide (this is enough to hold 17 hits!)
-- first word fall through (FWFT)

--xpm_fifo_sync_inst : xpm_fifo_sync
--generic map (
--   CASCADE_HEIGHT => 0,
--   DOUT_RESET_VALUE => "0",
--   ECC_MODE => "no_ecc",
--   EN_SIM_ASSERT_ERR => "warning",
--   FIFO_MEMORY_TYPE => "ultra",
--   FIFO_READ_LATENCY => 0,  FWFT
--   FIFO_WRITE_DEPTH => 4096,
--   FULL_RESET_VALUE => 0,
--   PROG_EMPTY_THRESH => 10,
--   PROG_FULL_THRESH => 10,
--   RD_DATA_COUNT_WIDTH => 1,
--   READ_DATA_WIDTH => 72,
--   READ_MODE => "fwft",
--   SIM_ASSERT_CHK => 0,
--   USE_ADV_FEATURES => "0707",
--   WAKEUP_TIME => 2,  use sleep pin
--   WRITE_DATA_WIDTH => 72,
--   WR_DATA_COUNT_WIDTH => 1
--)
--port map (
--   almost_empty => open,
--   almost_full => open,
--   data_valid => open,
--   dbiterr => open,
--   dout => FIFO_dout,
--   empty => FIFO_empty,
--   full => open,
--   overflow => open,
--   prog_empty => open,
--   prog_full => open,
--   rd_data_count => open,
--   rd_rst_busy => open,
--   sbiterr => open,
--   underflow => open,
--   wr_ack => open,
--   wr_data_count => open, 
--   wr_rst_busy => open,
--   din => FIFO_din,
--   injectdbiterr => '0',
--   injectsbiterr => '0',
--   rd_en => FIFO_rd_en,
--   rst => reset,
--   sleep => FIFO_sleep,
--   wr_clk => clock,
--   wr_en => FIFO_wr_en
--);

end stc3_arch;
