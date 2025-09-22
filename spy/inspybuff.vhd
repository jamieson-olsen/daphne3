-- DAPHNE input spy buffer
--
-- Select one of 45 inputs to capture. First this module is ARMED by the user, then it waits
-- for a TRIGGER pulse, which comes from external pin or a register write in the front end module.
-- Then it captures 64 pre-trigger samples and then it captures post-trigger samples until the
-- FIFO is full. The FIFO_DEPTH is adjustable at compile time, values (2048, 4096, 8192, 16384) will
-- impact the number of BlockRAMs this module uses.
--
-- there are 3 registers defined in the axi-lite interface:

-- Control Register (write address base+0)
--  Specify which AFE channel to capture and arm the spy buffer
--    bits 6..4 = AFE chip number (0 to 4)
--    bits 3..0 = AFE channel number (0 to 8)
--
-- Status Register (read address base+0)
--    bits 31..28 = spy buffer state machine status (search for "state_nibble" in this file for details) 
--    bits 6..4 = AFE chip number (0 to 4)
--    bits 3..0 = AFE channel number (0 to 8)
--
-- Data Register (read address base+4)
--    bits 13..0 = the captured AFE data; read this register repeatedly to get it all
--
-- HOW TO USE IT: First, write the AFE chip number and channel number to the control register. 
-- That will FLUSH the FIFO and ARM it.  Now read the status register. The upper nibble will indicate
-- the state of the capture logic. Once it is armed this module will wait for the trigger signal,
-- then it will store 64 pre-trigger samples and keep storing data until the FIFO is full. 
-- Then it will return to idle and wait to be armed again. Now you can read the captured data by 
-- reading the data register repeatedly. Reading this register will return a 32 bit word that has
-- a single 14 bit sample in bits 13..0. You don't have to read out the entire FIFO since 
-- it gets flushed each time it is armed.
--
-- The FIFO depth is controlled by the FIFO_DEPTH generic
-- and will impact the number of BlockRAMs used here:
--
-- 2048  = 1 36kbit BlockRAM
-- 4096  = 2 36kbit BlockRAMs
-- 8192  = 4 36kbit BlockRAMs
-- 16384 = 8 36kbit BlockRAMs

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library xpm;
use xpm.vcomponents.all;

library unisim;
use unisim.vcomponents.all;

use work.daphne3_package.all;

entity inspybuff is
    generic (FIFO_DEPTH: integer := 4096);  -- 2048, 4096, 8192, 16384
	port (
	    clock: in std_logic; -- 62.5MHz
	    din: in array_5x9x16_type; 
        trigger: in std_logic;
        AXI_IN: in AXILITE_INREC;  
        AXI_OUT: out AXILITE_OUTREC
  	);
end inspybuff;

architecture inspybuff_arch of inspybuff is

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
    signal arm_reg, trig_reg: std_logic := '0';
    signal afe_reg: std_logic_vector(2 downto 0) := "000";
    signal afe_ch_reg: std_logic_vector(3 downto 0) := "0000";
    signal din_mux, din_delayed32, din_delayed64: std_logic_vector(15 downto 0);

    signal FIFO_empty, FIFO_full, FIFO_wr_en, FIFO_rd_en, FIFO_rst: std_logic;
    signal FIFO_din, FIFO_dout: std_logic_vector(15 downto 0);

    signal status_word: std_logic_vector(31 downto 0);
    signal counter: integer range 0 to 63 := 0;
    type state_type is (rst, wait4arm, fifo_clear, fifo_wait, wait4trig, store);
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
        afe_reg <= "000";
        afe_ch_reg <= "0000";
    else
      if (reg_wren = '1' and AXI_IN.WSTRB = "1111") then
        if (axi_awaddr(3 downto 0)="0000") then -- write addr 0
            arm_axi_reg(0) <= '1';
            afe_reg    <= AXI_IN.WDATA(6 downto 4); -- store the target AFE number (0-4)
            afe_ch_reg <= AXI_IN.WDATA(3 downto 0); -- store the target AFE channel number (0-8)
        end if;
      else
        arm_axi_reg(0) <= '0';
        arm_axi_reg(1) <= arm_axi_reg(0);  -- make arm a double wide momentary pulse
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

reg_data_out <= status_word         when (axi_araddr(3 downto 0)="0000") else -- read reg 0
                X"0000" & FIFO_dout when (axi_araddr(3 downto 0)="0100") else -- read reg 4
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

-- big dumb mux to determine which input channel is selected for capture

din_mux <= din(0)(0) when (afe_reg="000" and afe_ch_reg="0000") else 
           din(0)(1) when (afe_reg="000" and afe_ch_reg="0001") else 
           din(0)(2) when (afe_reg="000" and afe_ch_reg="0010") else 
           din(0)(3) when (afe_reg="000" and afe_ch_reg="0011") else 
           din(0)(4) when (afe_reg="000" and afe_ch_reg="0100") else 
           din(0)(5) when (afe_reg="000" and afe_ch_reg="0101") else 
           din(0)(6) when (afe_reg="000" and afe_ch_reg="0110") else 
           din(0)(7) when (afe_reg="000" and afe_ch_reg="0111") else 
           din(0)(8) when (afe_reg="000" and afe_ch_reg="1000") else

           din(1)(0) when (afe_reg="001" and afe_ch_reg="0000") else 
           din(1)(1) when (afe_reg="001" and afe_ch_reg="0001") else 
           din(1)(2) when (afe_reg="001" and afe_ch_reg="0010") else 
           din(1)(3) when (afe_reg="001" and afe_ch_reg="0011") else 
           din(1)(4) when (afe_reg="001" and afe_ch_reg="0100") else 
           din(1)(5) when (afe_reg="001" and afe_ch_reg="0101") else 
           din(1)(6) when (afe_reg="001" and afe_ch_reg="0110") else 
           din(1)(7) when (afe_reg="001" and afe_ch_reg="0111") else 
           din(1)(8) when (afe_reg="001" and afe_ch_reg="1000") else

           din(2)(0) when (afe_reg="010" and afe_ch_reg="0000") else 
           din(2)(1) when (afe_reg="010" and afe_ch_reg="0001") else 
           din(2)(2) when (afe_reg="010" and afe_ch_reg="0010") else 
           din(2)(3) when (afe_reg="010" and afe_ch_reg="0011") else 
           din(2)(4) when (afe_reg="010" and afe_ch_reg="0100") else 
           din(2)(5) when (afe_reg="010" and afe_ch_reg="0101") else 
           din(2)(6) when (afe_reg="010" and afe_ch_reg="0110") else 
           din(2)(7) when (afe_reg="010" and afe_ch_reg="0111") else 
           din(2)(8) when (afe_reg="010" and afe_ch_reg="1000") else

           din(3)(0) when (afe_reg="011" and afe_ch_reg="0000") else 
           din(3)(1) when (afe_reg="011" and afe_ch_reg="0001") else 
           din(3)(2) when (afe_reg="011" and afe_ch_reg="0010") else 
           din(3)(3) when (afe_reg="011" and afe_ch_reg="0011") else 
           din(3)(4) when (afe_reg="011" and afe_ch_reg="0100") else 
           din(3)(5) when (afe_reg="011" and afe_ch_reg="0101") else 
           din(3)(6) when (afe_reg="011" and afe_ch_reg="0110") else 
           din(3)(7) when (afe_reg="011" and afe_ch_reg="0111") else 
           din(3)(8) when (afe_reg="011" and afe_ch_reg="1000") else
 
           din(4)(0) when (afe_reg="100" and afe_ch_reg="0000") else 
           din(4)(1) when (afe_reg="100" and afe_ch_reg="0001") else 
           din(4)(2) when (afe_reg="100" and afe_ch_reg="0010") else 
           din(4)(3) when (afe_reg="100" and afe_ch_reg="0011") else 
           din(4)(4) when (afe_reg="100" and afe_ch_reg="0100") else 
           din(4)(5) when (afe_reg="100" and afe_ch_reg="0101") else 
           din(4)(6) when (afe_reg="100" and afe_ch_reg="0110") else 
           din(4)(7) when (afe_reg="100" and afe_ch_reg="0111") else 
           din(4)(8) when (afe_reg="100" and afe_ch_reg="1000") else

           (others=>'0');

-- delay that data by 64 clocks

gendelay: for i in 15 downto 0 generate

    srlc32e_0_inst : srlc32e
    port map(
        clk => clock,
        ce => '1',
        a => "11111",
        d => din_mux(i),
        q => open,
        q31 => din_delayed32(i)  
    );

    srlc32e_1_inst : srlc32e
    port map(
        clk => clock,
        ce => '1',
        a => "11111",
        d => din_delayed32(i),
        q => din_delayed64(i),
        q31 => open  
    );

end generate gendelay;

-- FSM controls the FIFO write side signals
-- it is armed by the AXI side, but triggered by the trigger signal

 fsm_proc: process(clock)
    begin
        if rising_edge(clock) then

            reset_reg <= not AXI_IN.ARESETN; -- clean this up
            arm_reg <= arm_axi_reg(1) or arm_axi_reg(0);
            trig_reg <= trigger;

            if (reset_reg='1') then

                state <= rst;

            else

                case state is

                    when rst =>
                        state <= wait4arm;

                    when wait4arm => -- wait for arm pulse from AXI side
                        if (arm_reg='1') then
                            state <= fifo_clear;
                            counter <= 0;
                        else
                            state <= wait4arm;
                        end if;

                    when fifo_clear =>  -- reset the FIFO
                        if (counter=10) then -- sel_reg has just changed
                            state <= fifo_wait;
                            counter <= 0;
                        else
                            state <= fifo_clear;
                            counter <= counter + 1;
                        end if;

                    when fifo_wait =>  -- allow some time for FIFO to come out of reset
                        if (counter=51) then  -- allow time for 64 pre-trigger delay 
                            state <= wait4trig;
                            counter <= 0;
                        else
                            state <= fifo_wait;
                            counter <= counter + 1;
                        end if;                      
 
                    when wait4trig => -- wait until trigger pulse seen
                        if (trig_reg='1') then
                            state <= store;
                        else
                            state <= wait4trig;
                        end if;

                    when store => -- store data until FIFO is full
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

FIFO_wr_en <= '1' when (state=store) else '0';

FIFO_rd_en <= '1' when (reg_rden='1' and AXI_IN.ARADDR(3 downto 0)="0100") else '0'; -- read address 4

FIFO_rst <= '1' when (state=fifo_clear) else '0';

FIFO_din <= din_delayed64;

-- these four bits reflect the current state

state_nibble <= "0001" when (state=rst) else -- in reset
                "0010" when (state=wait4arm) else -- idle; waiting to be armed by the user
                "0011" when (state=fifo_clear) else -- flushing the FIFO
                "0100" when (state=fifo_wait) else -- pause after FIFO flush
                "0101" when (state=wait4trig) else -- waiting to be triggered 
                "0110" when (state=store) else -- capturing data but the FIFO is not yet FULL
                "0000";

status_word <= state_nibble & X"00000" & '0' & afe_reg(2 downto 0) & afe_ch_reg(3 downto 0);

-- FIFO read and write ports are 16 bits wide
-- FIFO depth is controlled by generic FIFO_DEPTH
-- This FIFO is made from 36kbit BlockRAMs (not UltraRAMs)

xpm_fifo_async_inst : xpm_fifo_async
generic map (
     CASCADE_HEIGHT => 0, 
     CDC_SYNC_STAGES => 2, 
     DOUT_RESET_VALUE => "0", 
     ECC_MODE => "no_ecc", 
     EN_SIM_ASSERT_ERR => "warning", 
     FIFO_MEMORY_TYPE => "block", 
     FIFO_READ_LATENCY => 1, 
     WRITE_DATA_WIDTH => 16, 
     FIFO_WRITE_DEPTH => FIFO_DEPTH,
     FULL_RESET_VALUE => 0, 
     PROG_EMPTY_THRESH => 10, 
     PROG_FULL_THRESH => 10, 
     --RD_DATA_COUNT_WIDTH => 10,
     --WR_DATA_COUNT_WIDTH => 10,  
     READ_DATA_WIDTH => 16,
     READ_MODE => "fwft",
     RELATED_CLOCKS => 0,
     SIM_ASSERT_CHK => 0,
     USE_ADV_FEATURES => "0707", 
     WAKEUP_TIME => 0
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
     din => FIFO_din,
     injectdbiterr => '0',
     injectsbiterr => '0',
     rd_clk => AXI_IN.ACLK,
     rd_en => FIFO_rd_en,
     rst => FIFO_rst,
     sleep => '0',
     wr_clk => clock,
     wr_en => FIFO_wr_en
);

end inspybuff_arch;

