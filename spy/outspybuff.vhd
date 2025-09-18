-- DAPHNE output spy buffer 2.0
--
-- Major Changes:
--    1. memory style interface replaced with FIFO style interface, just two addresses now!
--    2. uses LAST and VALID to detect data, only store VALID data, 1024 words captured
--    3. no longer stores pre-trigger samples (doesn't make sense with output data)
--    4. select one of 8 output streams for capture
--
-- address 0 = ARM the module by writing the output stream number (0-7) to this address
--             reading this address will return the status of the state machine in the upper nibble
--             (search for state_nibble futher down in this file...) and the stream number in the lower 3 bits.
--
-- address 4 = FIFO data register (R/O) read the captured data (low 32 bits, then high 32 bits, then low, then high...) 
--             1k 64-bit words are stored, so read this address 2048 times to get it all
--
-- HOW TO USE IT: First, write the output stream number you want to capture (0-7) to address 0. That will FLUSH the FIFO and ARM it.
-- Now you can poll the status by reading address 0. The status will be in the upper nibble of this 32 bit word.
-- (to see what these four bits mean, search for state_nibble futher down in this file...)
-- You can read the captured data by reading address 1 repeatedly. After this module has cycled through the
-- all the states, then the first word you'll read is the lower 32 bits of the first 64-bit word, followed by the upper 32 bits,
-- followed by the lower 32 bits of the next 64-bit word, etc. etc.
-- (you can read less, that's ok, since the FIFO is flushed automatically next time it is armed).
--
-- Capture depth is variable and will affect the number of BlockRAMs used
-- FIFO_DEPTH = 1024 -->  2 36kbit BlockRAMs
-- FIFO_DEPTH = 2048 -->  4 36kbit BlockRAMs
-- FIFO_DEPTH = 4096 -->  8 36kbit BlockRAMs
-- FIFO_DEPTH = 8192 --> 16 36kbit BlockRAMs

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library xpm;
use xpm.vcomponents.all;

use work.daphne3_package.all;

entity outspybuff is
    generic( FIFO_DEPTH: integer := 1024 );  -- 1024, 2048, 4096, 8192
	port (
	    clock: in std_logic; -- 62.5MHz clock
	    din: in array_8x64_type; -- tap off signals going to HERMES sender IP
	    valid: in std_logic_vector(7 downto 0);
	    last: in std_logic_vector(7 downto 0);
        AXI_IN: in AXILITE_INREC;  
        AXI_OUT: out AXILITE_OUTREC
  	);
end outspybuff;

architecture outspybuff_arch of outspybuff is

    signal axi_awaddr: std_logic_vector(31 downto 0);
    signal axi_awready: std_logic;
    signal axi_wready: std_logic;
    signal axi_bresp: std_logic_vector(1 downto 0);
    signal axi_bvalid: std_logic;
    signal axi_araddr: std_logic_vector(31 downto 0);
    signal axi_arready: std_logic;
    signal axi_rdata: std_logic_vector(31 downto 0);
    signal axi_rresp: std_logic_vector(1 downto 0);
    signal axi_rvalid: std_logic;
    signal axi_arready_reg: std_logic;
    signal axi_arvalid: std_logic;    
    signal reg_rden: std_logic;
    signal reg_wren: std_logic;
    signal reg_data_out:std_logic_vector(31 downto 0);
    signal aw_en: std_logic;

    signal arm_axi_reg: std_logic_vector(1 downto 0) := "00";
    signal reset_reg: std_logic := '1';
    signal arm_reg: std_logic := '0';

    signal sel_reg: std_logic_vector(2 downto 0) := "000";
    signal din_mux: std_logic_vector(63 downto 0);
    signal last_mux, valid_mux: std_logic;

    signal FIFO_empty, FIFO_full, FIFO_wr_en, FIFO_rd_en, FIFO_rst: std_logic;
    signal FIFO_dout: std_logic_vector(31 downto 0);

    signal status_word: std_logic_vector(31 downto 0);
    signal word_count: integer range 0 to 1024 := 0;
    type state_type is (rst, wait4arm, fifo_clear, fifo_wait, wait4last, store);
    signal state: state_type := rst;
    signal state_nibble: std_logic_vector(3 downto 0) := "0000";

begin

AXI_OUT.AWREADY <= axi_awready;
AXI_OUT.WREADY <= axi_wready;
AXI_OUT.BRESP <= axi_bresp;
AXI_OUT.BVALID <= axi_bvalid;
AXI_OUT.ARREADY <= axi_arready;
AXI_OUT.RDATA <= axi_rdata;
AXI_OUT.RRESP <= axi_rresp;
AXI_OUT.RVALID <= axi_rvalid;

-- Implement axi_awready generation
-- axi_awready is asserted for one S_AXI_ACLK clock cycle when both
-- S_AXI_AWVALID and S_AXI_WVALID are asserted. axi_awready is
-- de-asserted when reset is low.

process (AXI_IN.ACLK)
begin
  if rising_edge(AXI_IN.ACLK) then 
    if (AXI_IN.ARESETN = '0') then
      axi_awready <= '0';
      aw_en <= '1';
    else
      if (axi_awready = '0' and AXI_IN.AWVALID = '1' and AXI_IN.WVALID = '1' and aw_en = '1') then
        -- slave is ready to accept write address when
        -- there is a valid write address and write data
        -- on the write address and data bus. This design 
        -- expects no outstanding transactions. 
           axi_awready <= '1';
           aw_en <= '0';
        elsif (AXI_IN.BREADY = '1' and axi_bvalid = '1') then
           aw_en <= '1';
           axi_awready <= '0';
      else
        axi_awready <= '0';
      end if;
    end if;
  end if;
end process;

-- Implement axi_awaddr latching
-- This process is used to latch the address when both 
-- S_AXI_AWVALID and S_AXI_WVALID are valid. 

process (AXI_IN.ACLK)
begin
  if rising_edge(AXI_IN.ACLK) then 
    if (AXI_IN.ARESETN = '0') then
      axi_awaddr <= (others => '0');
    else
      if (axi_awready = '0' and AXI_IN.AWVALID = '1' and AXI_IN.WVALID = '1' and aw_en = '1') then
        -- Write Address latching
        axi_awaddr <= AXI_IN.AWADDR;
      end if;
    end if;
  end if;                   
end process; 

-- Implement axi_wready generation
-- axi_wready is asserted for one S_AXI_ACLK clock cycle when both
-- S_AXI_AWVALID and S_AXI_WVALID are asserted. axi_wready is 
-- de-asserted when reset is low. 

process (AXI_IN.ACLK)
begin
  if rising_edge(AXI_IN.ACLK) then 
    if (AXI_IN.ARESETN = '0') then
      axi_wready <= '0';
    else
      if (axi_wready = '0' and AXI_IN.WVALID = '1' and AXI_IN.AWVALID = '1' and aw_en = '1') then
          -- slave is ready to accept write data when 
          -- there is a valid write address and write data
          -- on the write address and data bus. This design 
          -- expects no outstanding transactions.           
          axi_wready <= '1';
      else
        axi_wready <= '0';
      end if;
    end if;
  end if;
end process; 

-- Implement memory mapped register select and write logic generation
-- The write data is accepted and written to memory mapped registers when
-- axi_awready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted. Write strobes are used to
-- select byte enables of slave registers while writing.
-- These registers are cleared when reset (active low) is applied.
-- Slave register write enable is asserted when valid address and data are available
-- and the slave is ready to accept the write address and write data.

reg_wren <= axi_wready and AXI_IN.WVALID and axi_awready and AXI_IN.AWVALID ;

process (AXI_IN.ACLK)
begin
  if rising_edge(AXI_IN.ACLK) then 
    if (AXI_IN.ARESETN = '0') then 
        arm_axi_reg <= "00";
        sel_reg <= "000";
    else
      if (reg_wren = '1' and AXI_IN.WSTRB = "1111") then
        if (axi_awaddr(3 downto 0)="0000") then  -- just wrote to address 0
            arm_axi_reg(0) <= '1';
            sel_reg <= AXI_IN.WDATA(2 downto 0); 
        end if;
      else
        arm_axi_reg(0) <= '0';
        arm_axi_reg(1) <= arm_axi_reg(0);  -- make a double wide momentary pulse
      end if;
    end if;
  end if;                   
end process; 

-- Implement write response logic generation
-- The write response and response valid signals are asserted by the slave 
-- when axi_wready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted.  
-- This marks the acceptance of address and indicates the status of 
-- write transaction.

process (AXI_IN.ACLK)
begin
  if rising_edge(AXI_IN.ACLK) then 
    if AXI_IN.ARESETN = '0' then
      axi_bvalid  <= '0';
      axi_bresp   <= "00"; --need to work more on the responses
    else
      if (axi_awready = '1' and AXI_IN.AWVALID = '1' and axi_wready = '1' and AXI_IN.WVALID = '1' and axi_bvalid = '0'  ) then
        axi_bvalid <= '1';
        axi_bresp  <= "00"; 
      elsif (AXI_IN.BREADY = '1' and axi_bvalid = '1') then   --check if bready is asserted while bvalid is high)
        axi_bvalid <= '0';                                   -- (there is a possibility that bready is always asserted high)
      end if;
    end if;
  end if;                   
end process; 

-- Implement axi_arready generation
-- axi_arready is asserted for one S_AXI_ACLK clock cycle when
-- S_AXI_ARVALID is asserted. axi_awready is 
-- de-asserted when reset (active low) is asserted. 
-- The read address is also latched when S_AXI_ARVALID is 
-- asserted. axi_araddr is reset to zero on reset assertion.

process (AXI_IN.ACLK)
begin
  if rising_edge(AXI_IN.ACLK) then 
    if (AXI_IN.ARESETN) = '0' then
      axi_arready <= '0';
      axi_araddr  <= (others => '1');
    else
      if (axi_arready = '0' and AXI_IN.ARVALID = '1') then
        -- indicates that the slave has acceped the valid read address
        axi_arready <= '1';
        -- Read Address latching 
        axi_araddr  <= AXI_IN.ARADDR;           
      else
        axi_arready <= '0';
      end if;
    end if;
  end if;                   
end process; 

-- Implement axi_arvalid generation
-- axi_rvalid is asserted for one S_AXI_ACLK clock cycle when both 
-- S_AXI_ARVALID and axi_arready are asserted. The slave registers 
-- data are available on the axi_rdata bus at this instance. The 
-- assertion of axi_rvalid marks the validity of read data on the 
-- bus and axi_rresp indicates the status of read transaction.axi_rvalid 
-- is deasserted on reset (active low). axi_rresp and axi_rdata are 
-- cleared to zero on reset (active low). 

process (AXI_IN.ACLK)
begin
  if rising_edge(AXI_IN.ACLK) then
    if (AXI_IN.ARESETN = '0') then
      axi_rvalid <= '0';
      axi_rresp  <= "00";
    else
      if (axi_arready = '1' and AXI_IN.ARVALID = '1' and axi_rvalid = '0') then
        -- Valid read data is available at the read data bus
        axi_rvalid <= '1';
        axi_rresp  <= "00"; -- 'OKAY' response
      elsif (axi_rvalid = '1' and AXI_IN.RREADY = '1') then
        -- Read data is accepted by the master
        axi_rvalid <= '0';
      end if;            
    end if;
  end if;
end process;

-- Implement memory mapped register select and read logic generation
-- Slave register read enable is asserted when valid address is available
-- and the slave is ready to accept the read address.
-- reg_data_out is 32 bits

reg_rden <= axi_arready and AXI_IN.ARVALID and (not axi_rvalid) ;

reg_data_out <= status_word when (axi_araddr(3 downto 0)="0000") else -- addr 0
                fifo_dout   when (axi_araddr(3 downto 0)="0100") else -- addr 4
                (others =>'0');

-- Output register or memory read data
process( AXI_IN.ACLK ) is
begin
  if (rising_edge (AXI_IN.ACLK)) then
    if ( AXI_IN.ARESETN = '0' ) then
      axi_rdata  <= (others => '0');
    else
      if (reg_rden = '1') then
        -- When there is a valid read address (S_AXI_ARVALID) with 
        -- acceptance of read address by the slave (axi_arready), 
        -- output the read dada 
        -- Read address mux
          axi_rdata <= reg_data_out; -- register read data
      end if;   
    end if;
  end if;
end process;

-- end of axilite glue logic

-- input mux switching

din_mux <= din(0) when (sel_reg="000") else
           din(1) when (sel_reg="001") else
           din(2) when (sel_reg="010") else
           din(3) when (sel_reg="011") else
           din(4) when (sel_reg="100") else
           din(5) when (sel_reg="101") else
           din(6) when (sel_reg="110") else
           din(7);

last_mux <= last(0) when (sel_reg="000") else
            last(1) when (sel_reg="001") else
            last(2) when (sel_reg="010") else
            last(3) when (sel_reg="011") else
            last(4) when (sel_reg="100") else
            last(5) when (sel_reg="101") else
            last(6) when (sel_reg="110") else
            last(7);

valid_mux <= valid(0) when (sel_reg="000") else
             valid(1) when (sel_reg="001") else
             valid(2) when (sel_reg="010") else
             valid(3) when (sel_reg="011") else
             valid(4) when (sel_reg="100") else
             valid(5) when (sel_reg="101") else
             valid(6) when (sel_reg="110") else
             valid(7);

-- FSM controls the FIFO write side signals
-- it is armed by the AXI side

 fsm_proc: process(clock)
    begin
        if rising_edge(clock) then

            reset_reg <= not AXI_IN.ARESETN; -- clean this up
            arm_reg <= arm_axi_reg(1) or arm_axi_reg(0);

            if (reset_reg='1') then

                state <= rst;

            else

                case state is

                    when rst =>
                        state <= wait4arm;

                    when wait4arm => -- wait for arm pulse from AXI side
                        if (arm_reg='1') then
                            state <= fifo_clear;
                            word_count <= 0;
                        else
                            state <= wait4arm;
                        end if;

                    when fifo_clear =>  -- reset the FIFO
                        if (word_count=10) then
                            state <= fifo_wait;
                            word_count <= 0;
                        else
                            state <= fifo_clear;
                            word_count <= word_count + 1;
                        end if;

                    when fifo_wait =>  -- allow some time for FIFO to come out of reset
                        if (word_count=10) then
                            state <= wait4last;
                            word_count <= 0;
                        else
                            state <= fifo_wait;
                            word_count <= word_count + 1;
                        end if;                      
 
                    when wait4last => -- wait until the end of previous record seen
                        if (last_mux='1') then
                            state <= store;
                        else
                            state <= wait4last;
                        end if;

                    when store => -- store valid words until FIFO is full
                        if (FIFO_full='1') then
                            state <= wait4arm;
                        else
                            state <= store;
                        end if;

                    when others => 
                        state <= rst;    
    
                end case;
            end if;
        end if;
    end process fsm_proc;

FIFO_wr_en <= '1' when (state=store and valid_mux='1') else '0';

FIFO_rd_en <= '1' when (reg_rden='1' and AXI_IN.ARADDR(3 downto 0)="0100") else '0';  -- read address 4

FIFO_rst <= '1' when (state=fifo_clear) else '0';

-- these four status bits describe the current state of this spy buffer

state_nibble <= "0001" when (state=rst) else -- in reset
                "0010" when (state=wait4arm) else   -- idle; waiting to be armed by the user 
                "0011" when (state=fifo_clear) else  -- flushing the FIFO
                "0100" when (state=fifo_wait) else -- pause after flushing the FIFO
                "0101" when (state=wait4last) else -- waiting to see the END of a record
                "0110" when (state=store) else -- saw the END, now storing valid data but the FIFO is not yet full
                "0000";

status_word <= state_nibble & X"000000" & '0' & sel_reg;

-- FIFO write side is 64 x 1k deep, read side is 32 x 2k
-- This FIFO is made from 36kbit BlockRAMs (not UltraRAM)

xpm_fifo_async_inst : xpm_fifo_async
generic map (
     CASCADE_HEIGHT => 0, 
     CDC_SYNC_STAGES => 2, 
     DOUT_RESET_VALUE => "0", 
     ECC_MODE => "no_ecc", 
     EN_SIM_ASSERT_ERR => "warning", 
     FIFO_MEMORY_TYPE => "block", 
     FIFO_READ_LATENCY => 1, 
     FIFO_WRITE_DEPTH => FIFO_DEPTH, -- generic
     FULL_RESET_VALUE => 0, 
     PROG_EMPTY_THRESH => 10, 
     PROG_FULL_THRESH => 10, 
     -- RD_DATA_COUNT_WIDTH => 10, 
     -- WR_DATA_COUNT_WIDTH => 10, 
     READ_DATA_WIDTH => 32, -- read port x32
     READ_MODE => "fwft",
     RELATED_CLOCKS => 0,
     SIM_ASSERT_CHK => 0,
     USE_ADV_FEATURES => "0707", 
     WAKEUP_TIME => 0, 
     WRITE_DATA_WIDTH => 64 -- write port x64
    )
port map (
     almost_empty => open,
     almost_full => open,
     data_valid => open,
     dbiterr => open,
     dout => FIFO_dout,
     empty => FIFO_empty,
     full => FIFO_full,
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
     din => din_mux,
     injectdbiterr => '0',
     injectsbiterr => '0',
     rd_clk => AXI_IN.ACLK,
     rd_en => FIFO_rd_en,
     rst => FIFO_rst,
     sleep => '0',
     wr_clk => clock,
     wr_en => FIFO_wr_en
);

end outspybuff_arch;

