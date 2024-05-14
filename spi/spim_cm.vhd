-- spim_cm.vhd
--
-- spi master for current monitor ADS1261IRHBT
-- all SPI transfers are 32 bits and are initiated by writing to base+0 register
-- the contents of base+0 register are not changed during the SPI transfer (register is read/write)
--
-- base+0: 32 bit data to write (register is R/W)
-- base+4: 32 bit data that was read from the SPI device 
-- base+8: bit 0 returns state of the ready pin (cm_drdyn)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spim_cm is
port(
    cm_sclk: out std_logic;
    cm_csn: out std_logic;
    cm_din: out std_logic;
    cm_dout: in std_logic;
    cm_drdyn: in std_logic;

    -- AXI-LITE interface

	S_AXI_ACLK	    : in std_logic; -- 100MHz
	S_AXI_ARESETN	: in std_logic;
	S_AXI_AWADDR	: in std_logic_vector(31 downto 0);
	S_AXI_AWPROT	: in std_logic_vector(2 downto 0);
	S_AXI_AWVALID	: in std_logic;
	S_AXI_AWREADY	: out std_logic;
	S_AXI_WDATA	    : in std_logic_vector(31 downto 0);
	S_AXI_WSTRB	    : in std_logic_vector(3 downto 0);
	S_AXI_WVALID	: in std_logic;
	S_AXI_WREADY	: out std_logic;
	S_AXI_BRESP	    : out std_logic_vector(1 downto 0);
	S_AXI_BVALID	: out std_logic;
	S_AXI_BREADY	: in std_logic;
	S_AXI_ARADDR	: in std_logic_vector(31 downto 0);
	S_AXI_ARPROT	: in std_logic_vector(2 downto 0);
	S_AXI_ARVALID	: in std_logic;
	S_AXI_ARREADY	: out std_logic;
	S_AXI_RDATA	    : out std_logic_vector(31 downto 0);
	S_AXI_RRESP	    : out std_logic_vector(1 downto 0);
	S_AXI_RVALID	: out std_logic;
	S_AXI_RREADY	: in std_logic
  );
end spim_cm;

architecture spim_cm_arch of spim_cm is

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

	signal rden, wren: std_logic;
	signal aw_en: std_logic;
    signal addra: std_logic_vector(10 downto 0);
    signal ram_dout: std_logic_vector(31 downto 0);

begin

end spim_cm_arch;
