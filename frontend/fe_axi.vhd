-- fe_axi.vhd
-- daphne v3 front end control registers
-- adapted from the Vivado example/skeleton AXI-LITE interface sources
-- Jamieson Olsen <jamieson@fnal.gov>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.daphne3_package.all;

entity fe_axi is  
	port (

		S_AXI_ACLK	: in std_logic;
		S_AXI_ARESETN	: in std_logic;
		S_AXI_AWADDR	: in std_logic_vector(31 downto 0);
		S_AXI_AWPROT	: in std_logic_vector(2 downto 0);
		S_AXI_AWVALID	: in std_logic;
		S_AXI_AWREADY	: out std_logic;
		S_AXI_WDATA	: in std_logic_vector(31 downto 0);
		S_AXI_WSTRB	: in std_logic_vector(3 downto 0);
		S_AXI_WVALID	: in std_logic;
		S_AXI_WREADY	: out std_logic;
		S_AXI_BRESP	: out std_logic_vector(1 downto 0);
		S_AXI_BVALID	: out std_logic;
		S_AXI_BREADY	: in std_logic;
		S_AXI_ARADDR	: in std_logic_vector(31 downto 0);
		S_AXI_ARPROT	: in std_logic_vector(2 downto 0);
		S_AXI_ARVALID	: in std_logic;
		S_AXI_ARREADY	: out std_logic;
		S_AXI_RDATA	: out std_logic_vector(31 downto 0);
		S_AXI_RRESP	: out std_logic_vector(1 downto 0);
		S_AXI_RVALID	: out std_logic;
		S_AXI_RREADY	: in std_logic;

        -- signals used by the front end 

        idelayctrl_ready: in std_logic;
        idelay_tap: out array_5x9_type;
        idelay_load: out std_logic_vector(4 downto 0);
        iserdes_bitslip: out array_5x4_type;
        iserdes_reset: out std_logic;
        idelayctrl_reset: out std_logic;
        idelay_en_vtc: out std_logic

	);
end fe_axi;

architecture fe_axi_arch of fe_axi is

	signal axi_awaddr	: std_logic_vector(31 downto 0);
	signal axi_awready	: std_logic;
	signal axi_wready	: std_logic;
	signal axi_bresp	: std_logic_vector(1 downto 0);
	signal axi_bvalid	: std_logic;
	signal axi_araddr	: std_logic_vector(31 downto 0);
	signal axi_arready	: std_logic;
	signal axi_rdata	: std_logic_vector(31 downto 0);
	signal axi_rresp	: std_logic_vector(1 downto 0);
	signal axi_rvalid	: std_logic;

	signal reg_rden: std_logic;
	signal reg_wren: std_logic;
	signal reg_data_out:std_logic_vector(31 downto 0);
	signal aw_en: std_logic;

	signal idelay_tap_reg: array_5x9_type;
    signal idelay_load0_reg, idelay_load1_reg: std_logic_vector(4 downto 0) := "00000";
    signal iserdes_bitslip_reg: array_5x4_type;
    signal fe_control_reg: std_logic_vector(31 downto 0) := (others=>'0');

begin

	S_AXI_AWREADY <= axi_awready;
	S_AXI_WREADY <= axi_wready;
	S_AXI_BRESP	<= axi_bresp;
	S_AXI_BVALID <= axi_bvalid;
	S_AXI_ARREADY <= axi_arready;
	S_AXI_RDATA	<= axi_rdata;
	S_AXI_RRESP	<= axi_rresp;
	S_AXI_RVALID <= axi_rvalid;

	-- Implement axi_awready generation
	-- axi_awready is asserted for one S_AXI_ACLK clock cycle when both
	-- S_AXI_AWVALID and S_AXI_WVALID are asserted. axi_awready is
	-- de-asserted when reset is low.

	process (S_AXI_ACLK)
	begin
	  if rising_edge(S_AXI_ACLK) then 
	    if S_AXI_ARESETN = '0' then
	      axi_awready <= '0';
	      aw_en <= '1';
	    else
	      if (axi_awready = '0' and S_AXI_AWVALID = '1' and S_AXI_WVALID = '1' and aw_en = '1') then
	        -- slave is ready to accept write address when
	        -- there is a valid write address and write data
	        -- on the write address and data bus. This design 
	        -- expects no outstanding transactions. 
	           axi_awready <= '1';
	           aw_en <= '0';
	        elsif (S_AXI_BREADY = '1' and axi_bvalid = '1') then
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

	process (S_AXI_ACLK)
	begin
	  if rising_edge(S_AXI_ACLK) then 
	    if S_AXI_ARESETN = '0' then
	      axi_awaddr <= (others => '0');
	    else
	      if (axi_awready = '0' and S_AXI_AWVALID = '1' and S_AXI_WVALID = '1' and aw_en = '1') then
	        -- Write Address latching
	        axi_awaddr <= S_AXI_AWADDR;
	      end if;
	    end if;
	  end if;                   
	end process; 

	-- Implement axi_wready generation
	-- axi_wready is asserted for one S_AXI_ACLK clock cycle when both
	-- S_AXI_AWVALID and S_AXI_WVALID are asserted. axi_wready is 
	-- de-asserted when reset is low. 

	process (S_AXI_ACLK)
	begin
	  if rising_edge(S_AXI_ACLK) then 
	    if S_AXI_ARESETN = '0' then
	      axi_wready <= '0';
	    else
	      if (axi_wready = '0' and S_AXI_WVALID = '1' and S_AXI_AWVALID = '1' and aw_en = '1') then
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

	reg_wren <= axi_wready and S_AXI_WVALID and axi_awready and S_AXI_AWVALID ;

	process (S_AXI_ACLK)
	begin
	  if rising_edge(S_AXI_ACLK) then 
	    if S_AXI_ARESETN = '0' then
          idelay_tap_reg(0) <= (others=>'0');
          idelay_tap_reg(1) <= (others=>'0');
          idelay_tap_reg(2) <= (others=>'0');
          idelay_tap_reg(3) <= (others=>'0');
          idelay_tap_reg(4) <= (others=>'0');
          idelay_load0_reg <= "00000";
          idelay_load1_reg <= "00000";
          iserdes_bitslip_reg(0) <= (others=>'0');
          iserdes_bitslip_reg(1) <= (others=>'0');
          iserdes_bitslip_reg(2) <= (others=>'0');
          iserdes_bitslip_reg(3) <= (others=>'0');
          iserdes_bitslip_reg(4) <= (others=>'0');
          fe_control_reg <= (others=>'0');
	    else
	      if (reg_wren = '1') then

            -- treat all of these register writes as if they are full 32 bits
            -- e.g. the four write strobe bits should be high

	        case (axi_awaddr) is

	          when FE_CTRL_ADDR => 
                if ( S_AXI_WSTRB = "1111" ) then
                    fe_control_reg <= S_AXI_WDATA;
                end if;
	          when FE_AFE0_TAP_ADDR => 
                if ( S_AXI_WSTRB = "1111" ) then
                    idelay_tap_reg(0) <= S_AXI_WDATA(8 downto 0);
                    idelay_load0_reg(0) <= '1';
                end if;
	          when FE_AFE1_TAP_ADDR =>
                if ( S_AXI_WSTRB = "1111" ) then 
                    idelay_tap_reg(1) <= S_AXI_WDATA(8 downto 0);
                    idelay_load0_reg(1) <= '1';
                end if;
	          when FE_AFE2_TAP_ADDR =>
                if ( S_AXI_WSTRB = "1111" ) then
                    idelay_tap_reg(2) <= S_AXI_WDATA(8 downto 0);
                    idelay_load0_reg(2) <= '1';
                end if;
	          when FE_AFE3_TAP_ADDR =>
                if ( S_AXI_WSTRB = "1111" ) then
                    idelay_tap_reg(3) <= S_AXI_WDATA(8 downto 0);
                    idelay_load0_reg(3) <= '1';
                end if;
	          when FE_AFE4_TAP_ADDR => 
                if ( S_AXI_WSTRB = "1111" ) then
                    idelay_tap_reg(4) <= S_AXI_WDATA(8 downto 0);
                    idelay_load0_reg(4) <= '1';
                end if;

              when FE_AFE0_BITSLIP_ADDR =>
                if ( S_AXI_WSTRB = "1111" ) then
                    iserdes_bitslip_reg(0) <= S_AXI_WDATA(3 downto 0);
                end if;
              when FE_AFE1_BITSLIP_ADDR =>
                if ( S_AXI_WSTRB = "1111" ) then
                    iserdes_bitslip_reg(1) <= S_AXI_WDATA(3 downto 0);
                end if;
              when FE_AFE2_BITSLIP_ADDR =>
                if ( S_AXI_WSTRB = "1111" ) then
                    iserdes_bitslip_reg(2) <= S_AXI_WDATA(3 downto 0);
                end if;
              when FE_AFE3_BITSLIP_ADDR =>
                if ( S_AXI_WSTRB = "1111" ) then
                    iserdes_bitslip_reg(3) <= S_AXI_WDATA(3 downto 0);
                end if;
              when FE_AFE4_BITSLIP_ADDR =>  
                if ( S_AXI_WSTRB = "1111" ) then
                    iserdes_bitslip_reg(4) <= S_AXI_WDATA(3 downto 0);
                end if;

	          when others =>
                fe_control_reg <= fe_control_reg;
                idelay_tap_reg(0) <= idelay_tap_reg(0);
                idelay_tap_reg(1) <= idelay_tap_reg(1);
                idelay_tap_reg(2) <= idelay_tap_reg(2);
                idelay_tap_reg(3) <= idelay_tap_reg(3);
                idelay_tap_reg(4) <= idelay_tap_reg(4);
                iserdes_bitslip_reg(0) <= iserdes_bitslip_reg(0);
                iserdes_bitslip_reg(1) <= iserdes_bitslip_reg(1);
                iserdes_bitslip_reg(2) <= iserdes_bitslip_reg(2);
                iserdes_bitslip_reg(3) <= iserdes_bitslip_reg(3);
                iserdes_bitslip_reg(4) <= iserdes_bitslip_reg(4);

	        end case;
          else
            idelay_load1_reg <= idelay_load0_reg;
            idelay_load0_reg <= "00000";
	      end if;
	    end if;
	  end if;                   
	end process; 

	-- Implement write response logic generation
	-- The write response and response valid signals are asserted by the slave 
	-- when axi_wready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted.  
	-- This marks the acceptance of address and indicates the status of 
	-- write transaction.

	process (S_AXI_ACLK)
	begin
	  if rising_edge(S_AXI_ACLK) then 
	    if S_AXI_ARESETN = '0' then
	      axi_bvalid  <= '0';
	      axi_bresp   <= "00"; --need to work more on the responses
	    else
	      if (axi_awready = '1' and S_AXI_AWVALID = '1' and axi_wready = '1' and S_AXI_WVALID = '1' and axi_bvalid = '0'  ) then
	        axi_bvalid <= '1';
	        axi_bresp  <= "00"; 
	      elsif (S_AXI_BREADY = '1' and axi_bvalid = '1') then   --check if bready is asserted while bvalid is high)
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

	process (S_AXI_ACLK)
	begin
	  if rising_edge(S_AXI_ACLK) then 
	    if S_AXI_ARESETN = '0' then
	      axi_arready <= '0';
	      axi_araddr  <= (others => '1');
	    else
	      if (axi_arready = '0' and S_AXI_ARVALID = '1') then
	        -- indicates that the slave has acceped the valid read address
	        axi_arready <= '1';
	        -- Read Address latching 
	        axi_araddr  <= S_AXI_ARADDR;           
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
 
	process (S_AXI_ACLK)
	begin
	  if rising_edge(S_AXI_ACLK) then
	    if S_AXI_ARESETN = '0' then
	      axi_rvalid <= '0';
	      axi_rresp  <= "00";
	    else
	      if (axi_arready = '1' and S_AXI_ARVALID = '1' and axi_rvalid = '0') then
	        -- Valid read data is available at the read data bus
	        axi_rvalid <= '1';
	        axi_rresp  <= "00"; -- 'OKAY' response
	      elsif (axi_rvalid = '1' and S_AXI_RREADY = '1') then
	        -- Read data is accepted by the master
	        axi_rvalid <= '0';
	      end if;            
	    end if;
	  end if;
	end process;

	-- Implement memory mapped register select and read logic generation
	-- Slave register read enable is asserted when valid address is available
	-- and the slave is ready to accept the read address.

	reg_rden <= axi_arready and S_AXI_ARVALID and (not axi_rvalid) ;

    reg_data_out <= fe_control_reg when (axi_araddr=FE_CTRL_ADDR) else
                    X"0000000" & "000" & idelayctrl_ready when (axi_araddr=FE_STAT_ADDR) else
                    X"00000" & "000" & idelay_tap_reg(0) when (axi_araddr=FE_AFE0_TAP_ADDR) else
                    X"00000" & "000" & idelay_tap_reg(1) when (axi_araddr=FE_AFE1_TAP_ADDR) else
                    X"00000" & "000" & idelay_tap_reg(2) when (axi_araddr=FE_AFE2_TAP_ADDR) else
                    X"00000" & "000" & idelay_tap_reg(3) when (axi_araddr=FE_AFE3_TAP_ADDR) else
                    X"00000" & "000" & idelay_tap_reg(4) when (axi_araddr=FE_AFE4_TAP_ADDR) else
                    X"0000000" & iserdes_bitslip_reg(0) when (axi_araddr=FE_AFE0_BITSLIP_ADDR) else
                    X"0000000" & iserdes_bitslip_reg(1) when (axi_araddr=FE_AFE1_BITSLIP_ADDR) else
                    X"0000000" & iserdes_bitslip_reg(2) when (axi_araddr=FE_AFE2_BITSLIP_ADDR) else
                    X"0000000" & iserdes_bitslip_reg(3) when (axi_araddr=FE_AFE3_BITSLIP_ADDR) else
                    X"0000000" & iserdes_bitslip_reg(4) when (axi_araddr=FE_AFE4_BITSLIP_ADDR) else
                    X"00000000";

	-- Output register or memory read data
	process( S_AXI_ACLK ) is
	begin
	  if (rising_edge (S_AXI_ACLK)) then
	    if ( S_AXI_ARESETN = '0' ) then
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

    idelay_en_vtc <= fe_control_reg(2);
    iserdes_reset <= fe_control_reg(1);
    idelayctrl_reset <= fe_control_reg(0);

    idelay_tap(0) <= idelay_tap_reg(0);
    idelay_tap(1) <= idelay_tap_reg(1);
    idelay_tap(2) <= idelay_tap_reg(2);
    idelay_tap(3) <= idelay_tap_reg(3);
    idelay_tap(4) <= idelay_tap_reg(4);

    -- this load pulse is momentary, only two AXI clocks wide...

    idelay_load <= idelay_load1_reg or idelay_load0_reg; 

    iserdes_bitslip(0) <= iserdes_bitslip_reg(0);
    iserdes_bitslip(1) <= iserdes_bitslip_reg(1);
    iserdes_bitslip(2) <= iserdes_bitslip_reg(2);
    iserdes_bitslip(3) <= iserdes_bitslip_reg(3);
    iserdes_bitslip(4) <= iserdes_bitslip_reg(4);

end fe_axi_arch;
