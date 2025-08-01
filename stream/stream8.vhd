-- stream8.vhd
-- DAPHNE_MEZZ streaming core module, input is 8 AFE data streams, each 14 bits wide, 
-- constantly arriving at 62.5MHz. Output is a 64 bit stream to HERMES core @ 125MHz.
--
-- header = 30 64 bit words 
-- data = 8 ch x 512 samples x 14 bits/sample = 896 64 bit words (dense packing)
--
-- input rate = 8 * 14 * 62.5MHz = 7.000 Gbps
-- output rate = 64 * 125MHz = 8.000 Gbps
-- 
-- factoring in the output headers, calc the window sizes:
-- input time = 512 clocks @ 62.5MHz = 8.192us
-- output time = (30 header words + 896 data words) @ 125MHz = 7.408us

-- since the output runs much faster than the input the "valid" output
-- will frequently (and randomly!) be pulled low.
--
-- Jamieson Olsen <jamieson@fnal.gov>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library xpm;
use xpm.vcomponents.all;

use work.daphne3_package.all;

entity stream8 is
port(

    link_id: std_logic_vector(5 downto 0);
    slot_id: std_logic_vector(3 downto 0);
    crate_id: std_logic_vector(9 downto 0);
    detector_id: std_logic_vector(5 downto 0);
    version_id: std_logic_vector(5 downto 0);

    clock: in std_logic; -- 62.5MHz master clock
    areset: in std_logic; -- async reset active high
    ts: in std_logic_vector(63 downto 0);
    din: array_8x14_type;

    clk125: in std_logic; -- 125MHz phase aligned to clock
    dout:  out std_logic_vector(63 downto 0);
    valid: out std_logic;
    last: out std_logic
  );
end stream8;

architecture stream8_arch of stream8 is

    signal reset: std_logic := '1';
    signal a_reg, b_reg: array_8x14_type;
    signal scnt_reg: std_logic_vector(1 downto 0) := "00";
    signal fcnt_reg: std_logic_vector(2 downto 0) := "000";
    signal ts_reg: std_logic_vector(63 downto 0) := (others => '0');
    signal pack, pack_reg: std_logic_vector(63 downto 0) := (others => '0');
    signal tock_reg, start_reg, hold_reg: std_logic := '0';
    signal bcount: integer range 0 to 127 := 127;

    signal FIFO_din, FIFO_dout: std_logic_vector(64 downto 0);
    signal FIFO_wr_en, FIFO_rd_en, FIFO_empty: std_logic;

    type fsm_type is (rst, purge, hold, header, data);
    signal state: fsm_type;
    signal wordcount: integer range 0 to 1023 := 0;
    signal valid_i, valid_reg: std_logic := '0';
    signal last_i, last_reg: std_logic := '0';
    signal dout_i, dout_reg: std_logic_vector(63 downto 0) := (others=>'0');

    -- one streaming output record is:
    -- 512 samples x 8 channels = 4096 14-bit words = 57344 bits (not including header)
    -- 57344 bits / (64 bits/word) = 896 64-bit data transmission words

    -- increment wordcount on every data word tranmission so that we know
    -- to assert the LAST output on the last data word number 895

    constant LASTWORDCOUNT: integer range 0 to 1023 := 895;  -- total 896 data words

    -- the holdoff state delays the FIFO read logic, thus allowing the FIFO
    -- to fill up a bit more. when this constant is tuned properly, the FIFO will
    -- go empty a few times, but only near the end of the data block. 
    -- This parameter is hand tuned in simulation...

    constant HOLDOFFCOUNT:  integer range 0 to 1023 := 92;

begin

    -- cleanup the aysnc reset pulse

    reset_proc: process(clk125, areset)
    begin
        if (areset='1') then
            reset <= '1'; -- async immediate assertion
        elsif rising_edge(clk125) then
            if (areset='0') then
                reset <= '0'; -- sync release
            else
                reset <= '1';
            end if;
        end if; 
    end process;

    -- gearbox / packer pipeline runs continuously...

    inreg_proc: process(clock) 
    begin
        if rising_edge(clock) then
            if (reset='1') then
                scnt_reg <= (others=>'0');
                ts_reg <= (others=>'0');
            else
                a_reg <= din;
                b_reg <= a_reg;
                scnt_reg <= std_logic_vector( unsigned(scnt_reg) + 1 ); -- sample counter 0 to 3 repeat
                ts_reg <= ts;
            end if;
        end if;
    end process inreg_proc;

    pack_proc: process(clk125) 
    begin
        if rising_edge(clk125) then
            if (reset='1') then
                tock_reg <= '0';
                fcnt_reg <= "000";
                pack_reg <= (others=>'0');
                start_reg <= '0';
                hold_reg <= '1';
                bcount <= 127;
            else
                if (scnt_reg="00" and tock_reg='0') then
                    tock_reg <= '1';
                else
                    tock_reg <= '0';
                end if;
    
                if (tock_reg='1') then
                    fcnt_reg <= "000";
                else
                    fcnt_reg <= std_logic_vector( unsigned(fcnt_reg) + 1 );
                end if;
    
                pack_reg <= pack;
                start_reg <= '1' when (fcnt_reg="111") else '0';
    
                if (fcnt_reg="111") then
                    hold_reg <= '0';
                    if (bcount=127) then 
                        bcount <= 0;
                    else
                        bcount <= bcount + 1;
                    end if;
                end if;

            end if;
        end if;
    end process pack_proc;

    -- this dense packing logic is really nasty...

    -- fcnt_reg = 0 or 1 : a_reg=S1  b_reg=S0
    -- fcnt_reg = 2 or 3 : a_reg=S2  b_reg=S1
    -- fcnt_reg = 4 or 5 : a_reg=S3  b_reg=S2
    -- fcnt_reg = 6 or 7 : a_reg=S0  b_reg=S3

    -- DATAWORD0 = C4S0(7..0) & C3S0 & C2S0 & C1S0 & C0S0
    -- DATAWORD1 = C1S1(1..0) & C0S1 & C7S0 & C6S0 & C5S0 & C4S0(13..8)
    -- DATAWORD2 = C5S1(9..0) & C4S1 & C3S1 & C2S1 & C1S1(13..2)
    -- DATAWORD3 = C2S2(33.0) & C1S2 & C0S2 & C7S1 & C6S1 & C5S1(13..10)
    -- DATAWORD4 = C6S2(11..0) & C5S2 & C4S2 & C3S2 & C2S2(13..4)
    -- DATAWORD5 = C3S3(5..0) & C2S3 & C1S3 & C0S3 & C7S2 & C6S2(13..12)
    -- DATAWORD6 = C7S3 & C6S3 & C5S3 & C4S3 & C3S3(13..6)

    pack <= ( b_reg(4)( 7 downto 0) & b_reg(3) & b_reg(2) & b_reg(1) & b_reg(0)                          ) when (fcnt_reg="000") else -- S0
            ( a_reg(1)( 1 downto 0) & a_reg(0) & b_reg(7) & b_reg(6) & b_reg(5) & b_reg(4)(13 downto 8)  ) when (fcnt_reg="001") else -- S1,S0
            ( b_reg(5)( 9 downto 0) & b_reg(4) & b_reg(3) & b_reg(2) & b_reg(1)(13 downto 2)             ) when (fcnt_reg="010") else -- S1
            ( a_reg(2)( 3 downto 0) & a_reg(1) & a_reg(0) & b_reg(7) & b_reg(6) & b_reg(5)(13 downto 10) ) when (fcnt_reg="011") else -- S2,S1
            ( b_reg(6)(11 downto 0) & b_reg(5) & b_reg(4) & b_reg(3) & b_reg(2)(13 downto 4)             ) when (fcnt_reg="100") else -- S2
            ( a_reg(3)( 5 downto 0) & a_reg(2) & a_reg(1) & a_reg(0) & b_reg(7) & b_reg(6)(13 downto 12) ) when (fcnt_reg="101") else -- S3,S2
            ( b_reg(7)              & b_reg(6) & b_reg(5) & b_reg(4) & b_reg(3)(13 downto 6)             ) when (fcnt_reg="110") else -- S3
            ts_reg;

    -- timestamp and dense packed sample data are combined into a single 
    -- 125MHz 65-bit data stream like this:
    --
    -- start_reg: 1.......1.......1.......1.......1.......1.......1
    -- pack_reg:  T0123456T0123456T0123456T0123456T0123456T0123456T
    -- bcount:    N       N+1     N+2     N+3     N+4     N+5
    -- 
    -- where T is the timestamp for DATAWORD0 which immediately follows
    -- important: this stream runs continously, it never stops...

    -- Manage the write side of the ultraram FIFO like this:
    -- the start bit is stored in the FIFO as FIFO_din(64) that's the timestamp marker
    -- if bcount=0: store timestamp word + data words
    -- all other bcounts: store data words only
    -- hold_reg is only used coming out of reset so that early data words are not stored

    FIFO_din <= start_reg & pack_reg(63 downto 0);

    FIFO_wr_en <= '1' when (start_reg='1' and bcount=0) else -- write first timestamp
                  '1' when (start_reg='0' and hold_reg='0') else -- write packed data
                  '0'; -- don't write other timestamp words

    fifo_inst : xpm_fifo_sync
    generic map (
       CASCADE_HEIGHT => 0,
       DOUT_RESET_VALUE => "0",
       ECC_MODE => "no_ecc",
       EN_SIM_ASSERT_ERR => "warning",
       FIFO_MEMORY_TYPE => "ultra", 
       FIFO_READ_LATENCY => 0,
       FIFO_WRITE_DEPTH => 2048,
       FULL_RESET_VALUE => 0,
       PROG_EMPTY_THRESH => 10,
       PROG_FULL_THRESH => 10,
       RD_DATA_COUNT_WIDTH => 12,
       READ_DATA_WIDTH => 65,
       READ_MODE => "fwft",
       SIM_ASSERT_CHK => 0,
       USE_ADV_FEATURES => "0707",
       WAKEUP_TIME => 0, 
       WRITE_DATA_WIDTH => 65,
       WR_DATA_COUNT_WIDTH => 12
    )
    port map (
       almost_empty => open,
       almost_full => open,
       data_valid => open,
       dbiterr => open,
       dout => FIFO_dout,
       empty => FIFO_empty,
       full => open,
       overflow => open,
       prog_empty => open, 
       prog_full => open,
       rd_data_count => open,
       rd_rst_busy => open,
       sbiterr => open,
       underflow => open,
       wr_ack => open,
       wr_data_count => open,
       wr_rst_busy => open,
       din => FIFO_din,
       injectdbiterr => '0',
       injectsbiterr => '0',
       rd_en => FIFO_rd_en,
       rst => reset,
       sleep => '0',
       wr_clk => clk125,
       wr_en => FIFO_wr_en
    );

    -- now manage the read side of the FIFO like this:

    -- if we are in DATA mode
    --   if FIFO is empty: drop read_en, drop valid, output zero, don't increment word count
    --   else:  
    --      if MSB is set then HEADER mode else
    --      assert read_en, set valid, output data
    --      if wordcount = lastword then assert LAST else wordcount++
    -- else we are in HEADER mode:
    --     drop read_en, output header words, on last header word assert read_en, switch to DATA mode

    -- we are reading from the FIFO faster than we are filling it, so it can and will go empty,
    -- this is normal, and we drop the VALID output to tell the serializer we got nothing for those clock cycles.

    fsm_proc: process(clk125)
    begin
        if rising_edge(clk125) then
            if (reset='1') then
                state <= rst;
            else
                case state is

                when rst =>
                    state <= purge;

                when purge => -- keep reading until header is seen
                    if (FIFO_empty='0' and FIFO_dout(64)='1') then
                        state <= hold;
                        wordcount <= 0;
                    else
                        state <= purge;
                    end if;
         
                when hold => -- holdoff a bit here to make a gap between output records
                    if (wordcount=HOLDOFFCOUNT) then
                        state <= header;
                        wordcount <= 0;
                    else
                        state <= hold;
                        wordcount <= wordcount + 1;
                    end if;

                when header => 
                    if (wordcount=29) then
                        state <= data;
                        wordcount <= 0;
                    else
                        state <= header;
                        wordcount <= wordcount + 1;
                    end if;                    

                when data => 
                    if (FIFO_empty='0') then -- FIFO has data
                        if (FIFO_dout(64)='1') then -- this data is beginning of next record
                            state <= hold;
                            wordcount <= 0;
                        else -- normal data, pass it on, increment wordcount
                            state <= data;
                            wordcount <= wordcount + 1;
                        end if;
                    else -- FIFO is empty, stay here, do not increment word count
                        state <= data;
                        wordcount <= wordcount;
                    end if;

                when others =>
                    state <= rst;
                end case;
            end if;
        end if;
    end process fsm_proc;

    FIFO_rd_en <= '1' when (state=rst and FIFO_empty='0' and FIFO_dout(64)='0') else 
                  '1' when (state=data and FIFO_empty='0' and FIFO_dout(64)='0') else 
                  '1' when (state=header and wordcount=2) else 
                  '0';

    valid_i <= '1' when (state=header) else
               '1' when (state=data and FIFO_empty='0' and FIFO_dout(64)='0') else
               '0';

    dout_i <= (X"00000000" & link_id & slot_id & crate_id & detector_id & version_id) when (state=header and wordcount=0) else
              FIFO_dout(63 downto 0) when (state=header and wordcount=1) else -- this is the timestamp
              FIFO_dout(63 downto 0) when (state=data and FIFO_empty='0' and FIFO_dout(64)='0') else -- normal data pass thru
              (others=>'0');

    last_i <= '1' when (state=data and wordcount=LASTWORDCOUNT) else '0';

    regout_proc: process(clk125)
    begin
        if rising_edge(clk125) then
            valid_reg <= valid_i;
            dout_reg  <= dout_i;
            last_reg  <= last_i;
        end if;
    end process regout_proc;

    valid <= valid_reg;
    dout  <= dout_reg;
    last  <= last_reg;

end stream8_arch;
