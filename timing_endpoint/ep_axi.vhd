-- AXI-Lite Interface for the Timing Endpoint
-- all registers are 32 bits

-- base+0 = clock control register R/W
--  bits 31..3: don't care
--  bit 2: clock source (0=local, 1=use endpoint)
--  bit 1: MMCM1 reset (does not auto-clear, user must set then clear this bit)
--  bit 0: MMCM0 reset (does not auto-clear, user must set then clear this bit)

-- base+4 = clock status register R/O
--  bits 31..2: zero
--  bit 1: MMCM1 locked
--  bit 0: MMCM0 locked

-- base+8 = endpoint control register R/W
--  bits 31..17: don't care
--  bit 16: endpoint reset
--  bits 15..0: endpoint address

-- base+12 = endpoint status register R/O
--  bits 31..5: zero
--  bit 4: endpoint timestamp ok
--  bits 3..0: endpoint state machine status

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.daphne3_package.all;

entity ep_axi is
	port (
    AXI_IN: in AXILITE_INREC;
    AXI_OUT: out AXILITE_OUTREC;

    ep_ts_rdy: in std_logic; -- endpoint timestamp is good
    ep_stat: in std_logic_vector(3 downto 0); -- endpoint state status bits
    mmcm0_locked: in std_logic; -- high if PLL/MMCM is locked
    mmcm1_locked: in std_logic; -- high if PLL/MMCM is locked

    ep_reset: out std_logic; -- soft reset endpoint logic
    ep_addr: out std_logic_vector(15 downto 0); -- endpoint address
    mmcm0_reset: out std_logic;
    mmcm1_reset: out std_logic;
    use_ep: out std_logic );
end ep_axi;

architecture ep_axi_arch of ep_axi is

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

	signal slv_reg_rden	: std_logic;
	signal slv_reg_wren	: std_logic;
	signal reg_data_out	:std_logic_vector(31 downto 0);
	signal aw_en	: std_logic;

    signal clock_ctrl_reg, ep_ctrl_reg: std_logic_vector(31 downto 0);
    signal clock_status, ep_status: std_logic_vector(31 downto 0);

    constant CLK_CTRL_OFFSET: std_logic_vector(3 downto 0) := "0000";
    constant CLK_STAT_OFFSET: std_logic_vector(3 downto 0) := "0100";
    constant EP_CTRL_OFFSET:  std_logic_vector(3 downto 0) := "1000";
    constant EP_STAT_OFFSET:  std_logic_vector(3 downto 0) := "1100";

begin

	AXI_OUT.AWREADY <= axi_awready;
	AXI_OUT.WREADY  <= axi_wready;
	AXI_OUT.BRESP	  <= axi_bresp;
	AXI_OUT.BVALID  <= axi_bvalid;
	AXI_OUT.ARREADY <= axi_arready;
	AXI_OUT.RDATA   <= axi_rdata;
	AXI_OUT.RRESP   <= axi_rresp;
	AXI_OUT.RVALID  <= axi_rvalid;

	-- Implement axi_awready generation
	-- axi_awready is asserted for one AXI_IN.ACLK clock cycle when both
	-- AXI_IN.AWVALID and AXI_IN.WVALID are asserted. axi_awready is
	-- de-asserted when reset is low.
	
	process (AXI_IN.ACLK)
	begin
	  if rising_edge(AXI_IN.ACLK) then 
	    if AXI_IN.ARESETN = '0' then
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
	-- AXI_IN.AWVALID and AXI_IN.WVALID are valid. 

	process (AXI_IN.ACLK)
	begin
	  if rising_edge(AXI_IN.ACLK) then 
	    if AXI_IN.ARESETN = '0' then
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
	-- axi_wready is asserted for one AXI_IN.ACLK clock cycle when both
	-- AXI_IN.AWVALID and AXI_IN.WVALID are asserted. axi_wready is 
	-- de-asserted when reset is low. 

	process (AXI_IN.ACLK)
	begin
	  if rising_edge(AXI_IN.ACLK) then 
	    if AXI_IN.ARESETN = '0' then
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
	-- axi_awready, AXI_IN.WVALID, axi_wready and AXI_IN.WVALID are asserted. Write strobes are used to
	-- select byte enables of slave registers while writing.
	-- These registers are cleared when reset (active low) is applied.
	-- Slave register write enable is asserted when valid address and data are available
	-- and the slave is ready to accept the write address and write data.

	slv_reg_wren <= axi_wready and AXI_IN.WVALID and axi_awready and AXI_IN.AWVALID ;

	process (AXI_IN.ACLK)
	begin
	  if rising_edge(AXI_IN.ACLK) then 
	    if (AXI_IN.ARESETN = '0') then
            clock_ctrl_reg <= X"00000000";
            ep_ctrl_reg    <= X"00000000";
	    else
	      if (slv_reg_wren='1' and AXI_IN.WSTRB="1111") then
	        case ( axi_awaddr(3 downto 0) ) is
                when CLK_CTRL_OFFSET => -- write base+0, clock control register, 32 bits
                    clock_ctrl_reg <= AXI_IN.WDATA;
                when EP_CTRL_OFFSET => -- write base+8, endpoint control register, 32 bits
                    ep_ctrl_reg <= AXI_IN.WDATA;
	            when others =>
                    clock_ctrl_reg <= clock_ctrl_reg;
                    ep_ctrl_reg <= ep_ctrl_reg;
	        end case;
	      end if;
	    end if;
	  end if;                   
	end process; 

	-- Implement write response logic generation
	-- The write response and response valid signals are asserted by the slave 
	-- when axi_wready, AXI_IN.WVALID, axi_wready and AXI_IN.WVALID are asserted.  
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
	        axi_bvalid <= '0';                                 -- (there is a possibility that bready is always asserted high)
	      end if;
	    end if;
	  end if;                   
	end process; 

	-- Implement axi_arready generation
	-- axi_arready is asserted for one AXI_IN.ACLK clock cycle when
	-- S_AXI_ARVALID is asserted. axi_awready is 
	-- de-asserted when reset (active low) is asserted. 
	-- The read address is also latched when S_AXI_ARVALID is 
	-- asserted. axi_araddr is reset to zero on reset assertion.

	process (AXI_IN.ACLK)
	begin
	  if rising_edge(AXI_IN.ACLK) then 
	    if AXI_IN.ARESETN = '0' then
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
	-- axi_rvalid is asserted for one AXI_IN.ACLK clock cycle when both 
	-- S_AXI_ARVALID and axi_arready are asserted. The slave registers 
	-- data are available on the axi_rdata bus at this instance. The 
	-- assertion of axi_rvalid marks the validity of read data on the 
	-- bus and axi_rresp indicates the status of read transaction.axi_rvalid 
	-- is deasserted on reset (active low). axi_rresp and axi_rdata are 
	-- cleared to zero on reset (active low).  

	process (AXI_IN.ACLK)
	begin
	  if rising_edge(AXI_IN.ACLK) then
	    if AXI_IN.ARESETN = '0' then
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

	slv_reg_rden <= axi_arready and AXI_IN.ARVALID and (not axi_rvalid) ;

	-- Output register or memory read data

	process( AXI_IN.ACLK ) is
	begin
	  if (rising_edge (AXI_IN.ACLK)) then
	    if ( AXI_IN.ARESETN = '0' ) then
	      axi_rdata  <= (others => '0');
	    else
	      if (slv_reg_rden = '1') then
	        -- When there is a valid read address (S_AXI_ARVALID) with 
	        -- acceptance of read address by the slave (axi_arready), 
	        -- output the read dada 
	        -- Read address mux
	          axi_rdata <= reg_data_out;     -- register read data
	      end if;   
	    end if;
	  end if;
	end process;

    -- AXI read select mux

    reg_data_out <= clock_ctrl_reg when ( axi_araddr(3 downto 0)=CLK_CTRL_OFFSET ) else
                    clock_status   when ( axi_araddr(3 downto 0)=CLK_STAT_OFFSET ) else
                    ep_ctrl_reg    when ( axi_araddr(3 downto 0)=EP_CTRL_OFFSET ) else
                    ep_status      when ( axi_araddr(3 downto 0)=EP_STAT_OFFSET ) else
                    X"00000000";
    
    -- form the 32 bit status words 

    clock_status <= X"0000000" & "00" & mmcm1_locked & mmcm0_locked;
    ep_status    <= X"000000" & "000" & ep_ts_rdy & ep_stat(3 downto 0);

    -- drive outputs based on bits in the control registers

    ep_reset <= ep_ctrl_reg(16);
    ep_addr  <= ep_ctrl_reg(15 downto 0);

    use_ep      <= clock_ctrl_reg(2);
    mmcm1_reset <= clock_ctrl_reg(1);
    mmcm0_reset <= clock_ctrl_reg(0);

end ep_axi_arch;
