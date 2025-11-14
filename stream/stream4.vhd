-- stream4.vhd
-- DAPHNE_MEZZ streaming core module, input is 4 AFE data streams, each 14 bits wide, 
-- clocked in @ 62.5MHz. Output is a 64 bit stream to HERMES core @ 62.5MHz.
-- NOTE: we assume that HERMES will mux TWO of these streams into ONE 10G link!
--
-- Samples are grouped into BLOCKS. Each block = 32 samples (4ch x 8 samples/ch)
-- dense packed into a block of 7 64-bit data words.
--
-- an output record is:
-- number of 64-bit header words = 5 (timestamp + 4 reserved)
-- number of 64-bit data words = BLOCKS_PER_RECORD * 7 
--
-- The output record contains a significant number of header words.
-- If BLOCKS_PER_RECORD is set too low, the header words begin to dominate
-- the output bandwidth and data will start to back up in the FIFO.
-- Minimum BLOCKS_PER_RECORD is about 30.
--
-- To disable this sender, set all four channel_id bytes to 0xFF.
-- 
-- calculate running baseline average for each channel
-- if a sample is X counts above the baseline value, mark that in the
-- corresponding header field in the NEXT record
--
-- Jamieson Olsen <jamieson@fnal.gov>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library xpm;
use xpm.vcomponents.all;

use work.daphne3_package.all;

entity stream4 is
generic(
    BLOCKS_PER_RECORD: integer := 35;
    BASELINE_RUNLENGTH: integer := 32 -- values allowed: 32, 64, 128 or 256
); 
port(
    clock: in std_logic;
    reset: in std_logic;
    version: in std_logic_vector(3 downto 0);
    channel_id: in array_4x8_type;
    threshold: in array_4x14_type;
    ts: in std_logic_vector(63 downto 0);
    din: array_4x14_type;
    dout:  out std_logic_vector(63 downto 0);
    valid: out std_logic;
    last: out std_logic
  );
end stream4;

architecture stream4_arch of stream4 is

    signal reset_clean: std_logic := '1';
    signal din_reg: std_logic_vector(111 downto 0);
    signal ts_reg: std_logic_vector(63 downto 0) := (others => '0');
    signal pack_reg: std_logic_vector(64 downto 0) := (others => '0');
    signal pack_sel: integer range 0 to 7 := 4;
    signal block_count: integer range 0 to BLOCKS_PER_RECORD-1 := 0;
    signal hold_reg: std_logic := '1';

    signal FIFO_din, FIFO_dout: std_logic_vector(64 downto 0);
    signal FIFO_wr_en, FIFO_rd_en, FIFO_empty: std_logic;

    type fsm_type is (rst, purge, hold, header, data);
    signal state: fsm_type;
    signal wordcount: integer range 0 to BLOCKS_PER_RECORD*7 := 0;
    signal valid_i, valid_reg: std_logic := '0';
    signal last_i, last_reg: std_logic := '0';
    signal dout_i, dout_reg: std_logic_vector(63 downto 0) := (others=>'0');

    signal sender_enable: std_logic := '1';

    signal sof: std_logic;
    signal channel_header: array_4x48_type;

    -- the holdoff state delays the FIFO read logic, thus allowing the FIFO
    -- to fill up a bit more. when this constant is tuned properly, the FIFO will
    -- go empty a just few times, but only near the end of the record. Note that 
    -- if the FIFO goes empty <THAT IS OK> since this sender will momentarily drop
    -- the VALID output. This parameter is largely cosmetic... 
    -- This parameter is hand tuned in simulation, some good values are:
    -- 
    -- BLOCKS_PER_RECORD = 32  --> HOLDOFFCOUNT = 0
    -- BLOCKS_PER_RECORD = 64  --> HOLDOFFCOUNT = 32
    -- BLOCKS_PER_RECORD = 80  --> HOLDOFFCOUNT = 48
    -- BLOCKS_PER_RECORD = 96  --> HOLDOFFCOUNT = 54
    -- BLOCKS_PER_RECORD = 128 --> HOLDOFFCOUNT = 96

    constant HOLDOFFCOUNT: integer range 0 to 1023 := 24;  

    component stream_header -- generate header metadata for a channel
    generic( RUNLENGTH: integer := 32 ); 
    port(
        clock: in  std_logic;
        reset: in  std_logic;
        threshold: in std_logic_vector(13 downto 0);
        sof:   in  std_logic;
        din:   in  std_logic_vector(13 downto 0);
        hdrdata: out std_logic_vector(47 downto 0)
    );
    end component;

begin

    -- cleanup the aysnc reset pulse

    reset_proc: process(clock, reset)
    begin
        if (reset='1') then
            reset_clean <= '1'; -- async immediate assertion
        elsif rising_edge(clock) then
            if (reset='0') then
                reset_clean <= '0'; -- sync release
            else
                reset_clean <= '1';
            end if;
        end if; 
    end process;

    -- to disable this sender, set all four channel_id bytes to 0xFF
    -- (this is done in the input mux module)

    sender_enable <= '0' when (channel_id(0)=X"FF" and channel_id(1)=X"FF" and channel_id(2)=X"FF" and channel_id(3)=X"FF") else '1';

    -- monitor live data and compute header metadata...
    -- this header data will merged into the output stream as 
    -- the timestamp and event data is being read from the
    -- output FIFO and formed into records

    sof <= '1' when (state=header and wordcount=4) else '0';

    genhead: for i in 3 downto 0 generate
        header_inst: stream_header
        generic map( RUNLENGTH => BASELINE_RUNLENGTH )
        port map(
            clock => clock,
            reset => reset,
            threshold => threshold(i),
            sof => sof,
            din => din(i),
            hdrdata => channel_header(i) 
        );
    end generate;

    -- gearbox / packer pipeline runs continuously...

    packer_proc: process(clock) 
    begin
        if rising_edge(clock) then
            if (reset_clean='1') then
                din_reg <= (others=>'0');
                ts_reg <= (others=>'0');
                pack_reg <= (others=>'0');
                pack_sel <= 4;
                block_count <= BLOCKS_PER_RECORD-1;
                hold_reg <= '1';
            else
                ts_reg <= ts;
                din_reg <= din(3) & din(2) & din(1) & din(0) & din_reg(111 downto 56);

                if (pack_sel=7) then
                    pack_sel <=0;
                else
                    pack_sel <= pack_sel + 1;
                end if;

                case pack_sel is
                    when 0 =>
                        pack_reg <= '1' & ts_reg;
                        hold_reg <= '0';
                        if (block_count = BLOCKS_PER_RECORD-1) then
                            block_count <= 0;
                        else
                            block_count <= block_count + 1;
                        end if;                      
                    when 1 => 
                        pack_reg <= '0' & din_reg(63 downto 0);
                    when 2 =>
                        pack_reg <= '0' & din_reg(71 downto 8);
                    when 3 =>
                        pack_reg <= '0' & din_reg(79 downto 16);
                    when 4 =>
                        pack_reg <= '0' & din_reg(87 downto 24);
                    when 5 =>
                        pack_reg <= '0' & din_reg(95 downto 32);
                    when 6 =>
                        pack_reg <= '0' & din_reg(103 downto 40);
                    when 7 =>
                        pack_reg <= '0' & din_reg(111 downto 48);
                    when others =>
                        null;
                end case;

            end if;
        end if;
    end process packer_proc;

    -- timestamp and dense packed sample data are combined into a single 
    -- 65-bit data stream which runs continuously like this:
    -- pack_reg(64):   1.......1.......1.......1.......1.......1.......1
    -- pack_reg(63..0) T0123456T0123456T0123456T0123456T0123456T0123456T
    -- where 0-6 are dense packed data words 
    -- and T is the timestamp for data word 0  

    -- Manage the write side of the ultraram FIFO like this:
    -- the start bit is stored in the FIFO as FIFO_din(64) that's the timestamp marker
    -- if bcount=0: store timestamp word + data words
    -- all other bcounts: store data words only
    -- hold_reg is only used coming out of reset so that early data words are not stored

    FIFO_din <= pack_reg;

    FIFO_wr_en <= '1' when (pack_reg(64)='1' and block_count=0) else -- write first timestamp
                  '1' when (pack_reg(64)='0' and hold_reg='0') else -- write packed data
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
       rst => reset_clean,
       sleep => '0',
       wr_clk => clock,
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

    fsm_proc: process(clock)
    begin
        if rising_edge(clock) then
            if (reset_clean='1') then
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
                    if (wordcount=4) then
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

    dout_i <= FIFO_dout(63 downto 0)                       when (state=header and wordcount=0) else -- this is the timestamp header word
              (channel_id(0) & version & "0000" & channel_header(0)) when (state=header and wordcount=1) else -- ch0 header word 
              (channel_id(1) & version & "0000" & channel_header(1)) when (state=header and wordcount=2) else -- ch1 header word
              (channel_id(2) & version & "0000" & channel_header(2)) when (state=header and wordcount=3) else -- ch2 header word
              (channel_id(3) & version & "0000" & channel_header(3)) when (state=header and wordcount=4) else -- ch3 header word
              FIFO_dout(63 downto 0)                       when (state=data and FIFO_empty='0' and FIFO_dout(64)='0') else -- normal data pass thru
              (others=>'0');

    last_i <= '1' when (state=data and wordcount=((BLOCKS_PER_RECORD*7)-1) ) else '0';  -- 7 data words per block

    regout_proc: process(clock)
    begin
        if rising_edge(clock) then
            if (sender_enable='1') then -- normal running
                valid_reg <= valid_i;
                dout_reg  <= dout_i;
                last_reg  <= last_i;
            else -- disable output
                valid_reg <= '0';
                dout_reg  <= (others=>'0');
                last_reg  <= '0';
            end if;
        end if;
    end process regout_proc;

    valid <= valid_reg;
    dout  <= dout_reg;
    last  <= last_reg;    

end stream4_arch;
