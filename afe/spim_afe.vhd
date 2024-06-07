-- spim_afe.vhd
--
-- spi master for AFE chips and associated offset and trim DACs
-- this module contains three independent SPI masters attached to a single AXI-LITE interface
-- 
-- afe0 = 1 AFE + 2 trim DACs + 2 offset DACs
-- afe12 = 2 AFEs + 4 trim DACs + 4 offset DACs
-- afe34 = 2 AFEs + 4 trim DACs + 4 offset DACs
-- 
-- AFE = AFE5808AZCF and DAC = AD5327BRUZ-REEL7
--
-- AFEs can be optionally be read back, but the DAC chips are write only. 
-- DAC chips are daisy chained in pairs and must be written together.
--
-- base+0:  afe0 data to write
-- base+4:  afe0 read data 
-- base+8:  afe0 trim DAC data to write
-- base+12: afe0 offset DAC data to write
-- base+16: afe1 data to write
-- base+20: afe1 read data 
-- base+24: afe1 trim DAC data to write
-- base+28: afe1 offset DAC data to write
-- base+32: afe2 data to write
-- base+36: afe2 read data 
-- base+40: afe2 trim DAC data to write
-- base+44: afe2 offset DAC data to write
-- base+48: afe3 data to write
-- base+52: afe3 read data 
-- base+56: afe3 trim DAC data to write
-- base+60: afe3 offset DAC data to write
-- base+64: afe4 data to write
-- base+68: afe4 read data 
-- base+72: afe4 trim DAC data to write
-- base+76: afe4 offset DAC data to write

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spim_afe is
port(

    afe_rst: out std_logic; -- high = hard reset all AFEs
    afe_pdn: out std_logic; -- low = power down all AFEs

    afe0_miso: in std_logic;
    afe0_sclk: out std_logic;
    afe0_sdata: out std_logic;
    afe0_sen: out std_logic;
    afe0_csn_trim: out std_logic;
    afe0_csn_off: out std_logic;
    afe0_ldacn_trim: out std_logic;
    afe0_ldacn_off: out std_logic;

    afe12_miso: in std_logic;
    afe12_sclk: out std_logic;
    afe12_sdata: out std_logic;
    afe12_sen: out std_logic_vector(1 downto 0);
    afe12_csn_trim: out std_logic_vector(1 downto 0);
    afe12_csn_off: out std_logic_vector(1 downto 0);
    afe12_ldacn_trim: out std_logic_vector(1 downto 0);
    afe12_ldacn_off: out std_logic_vector(1 downto 0);

    afe34_miso: in std_logic;
    afe34_sclk: out std_logic;
    afe34_sdata: out std_logic;
    afe34_sen: out std_logic_vector(1 downto 0);
    afe34_csn_trim: out std_logic_vector(1 downto 0);
    afe34_csn_off: out std_logic_vector(1 downto 0);
    afe34_ldacn_trim: out std_logic_vector(1 downto 0);
    afe34_ldacn_off: out std_logic_vector(1 downto 0);

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
end spim_afe;

architecture spim_afe_arch of spim_afe is

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
    signal axi_arvalid: std_logic;       

	signal rden, wren: std_logic;
	signal aw_en: std_logic;
    signal addra: std_logic_vector(10 downto 0);
    signal ram_dout: std_logic_vector(31 downto 0);

begin

-- placeholder

end spim_afe_arch;
