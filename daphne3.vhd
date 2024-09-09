-- DAPHNE3.vhd
--
-- Kria PL TOP LEVEL. This REPLACES the top level graphical block.
--
-- Build this with the TCL script from the command line (aka Vivado NON PROJECT MODE)
-- see the github README file for details

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.daphne3_package.all;

entity DAPHNE3 is
generic(version: std_logic_vector(27 downto 0) := X"1234567"); -- git commit number is passed in from tcl build script
port(

    -- misc PL external connections

    sysclk_p, sysclk_n: in  std_logic; -- 100MHz system clock from the clock generator chip (LVDS)
    fan_tach: in std_logic_vector(1 downto 0); -- fan tach speed sensors
    fan_ctrl: out std_logic; -- pwm fan speed control
    stat_led: out std_logic_vector(5 downto 0); -- general status LEDs
    hvbias_en: out std_logic; -- enable HV bias source
    mux_en: out std_logic_vector(1 downto 0); -- analog mux enables
    mux_a: out std_logic_vector(1 downto 0); -- analog mux addr selects
    gpi: in std_logic; -- testpoint input

    -- optical timing endpoint interface signals

    sfp_tmg_los: in std_logic; -- loss of signal is active high
    rx0_tmg_p, rx0_tmg_n: in std_logic; -- received serial data "LVDS"
    sfp_tmg_tx_dis: out std_logic; -- high to disable timing SFP TX
    tx0_tmg_p, tx0_tmg_n: out std_logic; -- serial data to TX to the timing master

    -- AFE LVDS high speed data interface 

    afe0_p, afe0_n: in std_logic_vector(8 downto 0);
    afe1_p, afe1_n: in std_logic_vector(8 downto 0);
    afe2_p, afe2_n: in std_logic_vector(8 downto 0);
    afe3_p, afe3_n: in std_logic_vector(8 downto 0);
    afe4_p, afe4_n: in std_logic_vector(8 downto 0);

    -- 62.5MHz master clock sent to AFEs (LVDS)

    afe_clk_p, afe_clk_n: out std_logic; 

    -- I2C master (for many different devices)

    pl_sda: inout std_logic;
    pl_scl: out std_logic;

    -- SPI master (for current monitor) 

    cm_sclk: out std_logic;
    cm_csn: out std_logic;
    cm_dout: in std_logic;
    cm_din: out std_logic;
    cm_drdyn: in std_logic;

    -- SPI master (for 3 DACs)

    dac_sclk:   out std_logic;
    dac_din:    out std_logic;
    dac_sync_n: out std_logic;
    dac_ldac_n: out std_logic;

    -- SPI master (for AFEs and associated DACs)

    afe_rst: out std_logic; -- high = hard reset all AFEs
    afe_pdn: out std_logic; -- low = power down all AFEs

    afe0_miso: in std_logic;
    afe0_sclk: out std_logic;
    afe0_mosi: out std_logic;

    afe12_miso: in std_logic;
    afe12_sclk: out std_logic;
    afe12_mosi: out std_logic;

    afe34_miso: in std_logic;
    afe34_sclk: out std_logic;
    afe34_mosi: out std_logic;

    afe_sen: out std_logic_vector(4 downto 0);
    trim_sync_n: out std_logic_vector(4 downto 0);
    trim_ldac_n: out std_logic_vector(4 downto 0);
    offset_sync_n: out std_logic_vector(4 downto 0);
    offset_ldac_n: out std_logic_vector(4 downto 0);

    -- 10G Ethernet sender interface to external MGT refclk LVDS 156.25MHz

    eth_clk_p: in std_logic;
    eth_clk_n: in std_logic; 

    -- 10G Ethernet sender interface to external SFP+ transceiver

    eth0_rx_p: in std_logic;
    eth0_rx_n: in std_logic;
    eth0_tx_p: out std_logic;
    eth0_tx_n: out std_logic;
    eth0_tx_dis: out std_logic

  );
end DAPHNE3;

architecture DAPHNE3_arch of DAPHNE3 is

-- There are 9 AXI-LITE interfaces in this design:
--
-- 1. timing endpoint
-- 2. front end 
-- 3. spy buffers
-- 4. i2c master (multiple devices)
-- 5. spi master (current monitor)
-- 6. spi master (afe + dac)
-- 7. spi master (3 dacs)
-- 8. misc stuff (fans, vbias, mux control, leds, etc. etc.)
-- 9. core logic
--
-- MOAR NOTES: 
-- 1. all modules are written assuming S_AXI_ACLK is 100MHz
-- 2. most modules use S_AXI_ARESETN has an active low HARD RESET
-- 3. most modules have various SOFT RESET control bits that can be written via AXI registers
-- 4. most modules have a testbench for standalone simulation

-- front end data alignment logic

component front_end 
port(
    afe_p, afe_n: in array_5x9_type;
    afe_clk_p, afe_clk_n: out std_logic;
    clk500: in std_logic;
    clk125: in std_logic;
    clock: in std_logic;
    dout: out array_5x9x16_type;
    trig: out std_logic;
    S_AXI_ACLK: in std_logic;
    S_AXI_ARESETN: in std_logic;
    S_AXI_AWADDR: in std_logic_vector(31 downto 0);
    S_AXI_AWPROT: in std_logic_vector(2 downto 0);
    S_AXI_AWVALID: in std_logic;
    S_AXI_AWREADY: out std_logic;
    S_AXI_WDATA: in std_logic_vector(31 downto 0);
    S_AXI_WSTRB: in std_logic_vector(3 downto 0);
    S_AXI_WVALID: in std_logic;
    S_AXI_WREADY: out std_logic;
    S_AXI_BRESP: out std_logic_vector(1 downto 0);
    S_AXI_BVALID: out std_logic;
    S_AXI_BREADY: in std_logic;
    S_AXI_ARADDR: in std_logic_vector(31 downto 0);
    S_AXI_ARPROT: in std_logic_vector(2 downto 0);
    S_AXI_ARVALID: in std_logic;
    S_AXI_ARREADY: out std_logic;
    S_AXI_RDATA: out std_logic_vector(31 downto 0);
    S_AXI_RRESP: out std_logic_vector(1 downto 0);
    S_AXI_RVALID: out std_logic;
    S_AXI_RREADY: in std_logic
  );
end component;

-- Input Spy Buffers

component spybuffers
port(
    clock           : in std_logic;
    trig            : in std_logic;
    din             : in array_5x9x16_type;
    timestamp       : in std_logic_vector(63 downto 0);
	S_AXI_ACLK	    : in std_logic;
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
end component;

-- Timing Endpoint

component endpoint 
port(
    sysclk_p        : in std_logic;
    sysclk_n        : in std_logic;
    sfp_tmg_los     : in std_logic;
    rx0_tmg_p       : in std_logic;
    rx0_tmg_n       : in std_logic;
    sfp_tmg_tx_dis  : out std_logic;
    tx0_tmg_p       : out std_logic;
    tx0_tmg_n       : out std_logic;
    clock           : out std_logic;
    clk500          : out std_logic;
    clk125          : out std_logic;
    timestamp       : out std_logic_vector(63 downto 0);
	S_AXI_ACLK      : in std_logic;
	S_AXI_ARESETN   : in std_logic;
	S_AXI_AWADDR    : in std_logic_vector(31 downto 0);
	S_AXI_AWPROT    : in std_logic_vector(2 downto 0);
	S_AXI_AWVALID   : in std_logic;
	S_AXI_AWREADY   : out std_logic;
	S_AXI_WDATA     : in std_logic_vector(31 downto 0);
	S_AXI_WSTRB     : in std_logic_vector(3 downto 0);
	S_AXI_WVALID    : in std_logic;
	S_AXI_WREADY    : out std_logic;
	S_AXI_BRESP     : out std_logic_vector(1 downto 0);
	S_AXI_BVALID    : out std_logic;
	S_AXI_BREADY    : in std_logic;
	S_AXI_ARADDR    : in std_logic_vector(31 downto 0);
	S_AXI_ARPROT    : in std_logic_vector(2 downto 0);
	S_AXI_ARVALID   : in std_logic;
	S_AXI_ARREADY   : out std_logic;
	S_AXI_RDATA     : out std_logic_vector(31 downto 0);
	S_AXI_RRESP     : out std_logic_vector(1 downto 0);
	S_AXI_RVALID    : out std_logic;
	S_AXI_RREADY    : in std_logic
);
end component;

-- I2C master

component i2cm is
port(
    pl_sda          : inout std_logic;
    pl_scl          : out std_logic;
	S_AXI_ACLK	    : in std_logic;
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
end component;

-- SPI master for 3 DAC chips 

component spim_dac
port(
    dac_sclk        : out std_logic;
    dac_din         : out std_logic;
    dac_sync_n      : out std_logic;
    dac_ldac_n      : out std_logic;
	S_AXI_ACLK	    : in std_logic;
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
end component;

-- current monitor

component spim_cm 
port(
    cm_sclk         : out std_logic;
    cm_csn          : out std_logic;
    cm_din          : out std_logic;
    cm_dout         : in std_logic;
    cm_drdyn        : in std_logic;
	S_AXI_ACLK	    : in std_logic;
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
end component;

-- SPI master for AFE chips + Offset DACs + Trim DACs
-- plus two global AFE control signals

component spim_afe 
port(
    afe_rst: out std_logic;
    afe_pdn: out std_logic;
    afe0_miso: in std_logic;
    afe0_sclk: out std_logic;
    afe0_mosi: out std_logic;
    afe12_miso: in std_logic;
    afe12_sclk: out std_logic;
    afe12_mosi: out std_logic;
    afe34_miso: in std_logic;
    afe34_sclk: out std_logic;
    afe34_mosi: out std_logic;
    afe_sen: out std_logic_vector(4 downto 0);
    trim_sync_n: out std_logic_vector(4 downto 0);
    trim_ldac_n: out std_logic_vector(4 downto 0);
    offset_sync_n: out std_logic_vector(4 downto 0);
    offset_ldac_n: out std_logic_vector(4 downto 0);
	S_AXI_ACLK	    : in std_logic;
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
end component;

-- catch all module for misc signals

component stuff
port(
    fan_tach        : in  std_logic_vector(1 downto 0);
    fan_ctrl        : out std_logic;
    hvbias_en       : out std_logic;
    mux_en          : out std_logic_vector(1 downto 0);
    mux_a           : out std_logic_vector(1 downto 0);
    stat_led        : out std_logic_vector(5 downto 0);
    version         : in std_logic_vector(27 downto 0);
	S_AXI_ACLK	    : in std_logic;
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
end component;

-- 40 self-triggered senders + 10G Ethernet sender

component core
generic( 
    link_id: std_logic_vector(5 downto 0) := "000000";
    slot_id: std_logic_vector(3 downto 0) := "0010";
    crate_id: std_logic_vector(9 downto 0) := "0000000011";
    detector_id: std_logic_vector(5 downto 0) := "000010";
    version_id: std_logic_vector(5 downto 0) := "000011";
    threshold: std_logic_vector(13 downto 0) := "10000000000000";
    runlength: integer := 256;
    enable: std_logic_vector(39 downto 0) := X"FFFFFFFFFF";
    ext_mac_addr_0: std_logic_vector(47 downto 0) := X"DEADBEEFCAFE";
    ext_ip_addr_0: std_logic_vector(31 downto 0) := X"C0A80064";
    ext_port_addr_0: std_logic_vector(15 downto 0) := X"1234"
);
port(
    clock: in std_logic;
    reset: in std_logic;
    timestamp: in std_logic_vector(63 downto 0);
    din: in array_5x8x14_type;
    S_AXI_ACLK: in std_logic;
    S_AXI_ARESETN: in std_logic;
    S_AXI_AWADDR: in std_logic_vector(31 downto 0);
    S_AXI_AWPROT: in std_logic_vector(2 downto 0);
    S_AXI_AWVALID: in std_logic;
    S_AXI_AWREADY: out std_logic;
    S_AXI_WDATA: in std_logic_vector(31 downto 0);
    S_AXI_WSTRB: in std_logic_vector(3 downto 0);
    S_AXI_WVALID: in std_logic;
    S_AXI_WREADY: out std_logic;
    S_AXI_BRESP: out std_logic_vector(1 downto 0);
    S_AXI_BVALID: out std_logic;
    S_AXI_BREADY: in std_logic;
    S_AXI_ARADDR: in std_logic_vector(31 downto 0);
    S_AXI_ARPROT: in std_logic_vector(2 downto 0);
    S_AXI_ARVALID: in std_logic;
    S_AXI_ARREADY: out std_logic;
    S_AXI_RDATA: out std_logic_vector(31 downto 0);
    S_AXI_RRESP: out std_logic_vector(1 downto 0);
    S_AXI_RVALID: out std_logic;
    S_AXI_RREADY: in std_logic;
    eth_clk_p: in std_logic;
    eth_clk_n: in std_logic; 
    eth0_rx_p: in std_logic;
    eth0_rx_n: in std_logic;
    eth0_tx_p: out std_logic;
    eth0_tx_n: out std_logic;
    eth0_tx_dis: out std_logic
);
end component;

signal afe_p_array, afe_n_array: array_5x9_type;
signal din_full_array: array_5x9x16_type;
signal din_array: array_5x8x14_type;
signal trig: std_logic;
signal timestamp: std_logic_vector(63 downto 0);
signal clock, clk125, clk500: std_logic;

signal S_AXI_ACLK:    std_logic;
signal S_AXI_ARESETN: std_logic;

signal FE_AXI_AWADDR:  std_logic_vector(31 downto 0);
signal FE_AXI_AWPROT:  std_logic_vector(2 downto 0);
signal FE_AXI_AWVALID: std_logic;
signal FE_AXI_AWREADY: std_logic;
signal FE_AXI_WDATA:   std_logic_vector(31 downto 0);
signal FE_AXI_WSTRB:   std_logic_vector(3 downto 0);
signal FE_AXI_WVALID:  std_logic;
signal FE_AXI_WREADY:  std_logic;
signal FE_AXI_BRESP:   std_logic_vector(1 downto 0);
signal FE_AXI_BVALID:  std_logic;
signal FE_AXI_BREADY:  std_logic;
signal FE_AXI_ARADDR:  std_logic_vector(31 downto 0);
signal FE_AXI_ARPROT:  std_logic_vector(2 downto 0);
signal FE_AXI_ARVALID: std_logic;
signal FE_AXI_ARREADY: std_logic;
signal FE_AXI_RDATA:   std_logic_vector(31 downto 0);
signal FE_AXI_RRESP:   std_logic_vector(1 downto 0);
signal FE_AXI_RVALID:  std_logic;
signal FE_AXI_RREADY:  std_logic;

signal SB_AXI_AWADDR:  std_logic_vector(31 downto 0);
signal SB_AXI_AWPROT:  std_logic_vector(2 downto 0);
signal SB_AXI_AWVALID: std_logic;
signal SB_AXI_AWREADY: std_logic;
signal SB_AXI_WDATA:   std_logic_vector(31 downto 0);
signal SB_AXI_WSTRB:   std_logic_vector(3 downto 0);
signal SB_AXI_WVALID:  std_logic;
signal SB_AXI_WREADY:  std_logic;
signal SB_AXI_BRESP:   std_logic_vector(1 downto 0);
signal SB_AXI_BVALID:  std_logic;
signal SB_AXI_BREADY:  std_logic;
signal SB_AXI_ARADDR:  std_logic_vector(31 downto 0);
signal SB_AXI_ARPROT:  std_logic_vector(2 downto 0);
signal SB_AXI_ARVALID: std_logic;
signal SB_AXI_ARREADY: std_logic;
signal SB_AXI_RDATA:   std_logic_vector(31 downto 0);
signal SB_AXI_RRESP:   std_logic_vector(1 downto 0);
signal SB_AXI_RVALID:  std_logic;
signal SB_AXI_RREADY:  std_logic;

signal EP_AXI_AWADDR:  std_logic_vector(31 downto 0);
signal EP_AXI_AWPROT:  std_logic_vector(2 downto 0);
signal EP_AXI_AWVALID: std_logic;
signal EP_AXI_AWREADY: std_logic;
signal EP_AXI_WDATA:   std_logic_vector(31 downto 0);
signal EP_AXI_WSTRB:   std_logic_vector(3 downto 0);
signal EP_AXI_WVALID:  std_logic;
signal EP_AXI_WREADY:  std_logic;
signal EP_AXI_BRESP:   std_logic_vector(1 downto 0);
signal EP_AXI_BVALID:  std_logic;
signal EP_AXI_BREADY:  std_logic;
signal EP_AXI_ARADDR:  std_logic_vector(31 downto 0);
signal EP_AXI_ARPROT:  std_logic_vector(2 downto 0);
signal EP_AXI_ARVALID: std_logic;
signal EP_AXI_ARREADY: std_logic;
signal EP_AXI_RDATA:   std_logic_vector(31 downto 0);
signal EP_AXI_RRESP:   std_logic_vector(1 downto 0);
signal EP_AXI_RVALID:  std_logic;
signal EP_AXI_RREADY:  std_logic;

signal AFE_AXI_AWADDR:  std_logic_vector(31 downto 0);
signal AFE_AXI_AWPROT:  std_logic_vector(2 downto 0);
signal AFE_AXI_AWVALID: std_logic;
signal AFE_AXI_AWREADY: std_logic;
signal AFE_AXI_WDATA:   std_logic_vector(31 downto 0);
signal AFE_AXI_WSTRB:   std_logic_vector(3 downto 0);
signal AFE_AXI_WVALID:  std_logic;
signal AFE_AXI_WREADY:  std_logic;
signal AFE_AXI_BRESP:   std_logic_vector(1 downto 0);
signal AFE_AXI_BVALID:  std_logic;
signal AFE_AXI_BREADY:  std_logic;
signal AFE_AXI_ARADDR:  std_logic_vector(31 downto 0);
signal AFE_AXI_ARPROT:  std_logic_vector(2 downto 0);
signal AFE_AXI_ARVALID: std_logic;
signal AFE_AXI_ARREADY: std_logic;
signal AFE_AXI_RDATA:   std_logic_vector(31 downto 0);
signal AFE_AXI_RRESP:   std_logic_vector(1 downto 0);
signal AFE_AXI_RVALID:  std_logic;
signal AFE_AXI_RREADY:  std_logic;

signal I2C_AXI_AWADDR:  std_logic_vector(31 downto 0);
signal I2C_AXI_AWPROT:  std_logic_vector(2 downto 0);
signal I2C_AXI_AWVALID: std_logic;
signal I2C_AXI_AWREADY: std_logic;
signal I2C_AXI_WDATA:   std_logic_vector(31 downto 0);
signal I2C_AXI_WSTRB:   std_logic_vector(3 downto 0);
signal I2C_AXI_WVALID:  std_logic;
signal I2C_AXI_WREADY:  std_logic;
signal I2C_AXI_BRESP:   std_logic_vector(1 downto 0);
signal I2C_AXI_BVALID:  std_logic;
signal I2C_AXI_BREADY:  std_logic;
signal I2C_AXI_ARADDR:  std_logic_vector(31 downto 0);
signal I2C_AXI_ARPROT:  std_logic_vector(2 downto 0);
signal I2C_AXI_ARVALID: std_logic;
signal I2C_AXI_ARREADY: std_logic;
signal I2C_AXI_RDATA:   std_logic_vector(31 downto 0);
signal I2C_AXI_RRESP:   std_logic_vector(1 downto 0);
signal I2C_AXI_RVALID:  std_logic;
signal I2C_AXI_RREADY:  std_logic;

signal DAC_AXI_AWADDR:  std_logic_vector(31 downto 0);
signal DAC_AXI_AWPROT:  std_logic_vector(2 downto 0);
signal DAC_AXI_AWVALID: std_logic;
signal DAC_AXI_AWREADY: std_logic;
signal DAC_AXI_WDATA:   std_logic_vector(31 downto 0);
signal DAC_AXI_WSTRB:   std_logic_vector(3 downto 0);
signal DAC_AXI_WVALID:  std_logic;
signal DAC_AXI_WREADY:  std_logic;
signal DAC_AXI_BRESP:   std_logic_vector(1 downto 0);
signal DAC_AXI_BVALID:  std_logic;
signal DAC_AXI_BREADY:  std_logic;
signal DAC_AXI_ARADDR:  std_logic_vector(31 downto 0);
signal DAC_AXI_ARPROT:  std_logic_vector(2 downto 0);
signal DAC_AXI_ARVALID: std_logic;
signal DAC_AXI_ARREADY: std_logic;
signal DAC_AXI_RDATA:   std_logic_vector(31 downto 0);
signal DAC_AXI_RRESP:   std_logic_vector(1 downto 0);
signal DAC_AXI_RVALID:  std_logic;
signal DAC_AXI_RREADY:  std_logic;

signal CM_AXI_AWADDR:  std_logic_vector(31 downto 0);
signal CM_AXI_AWPROT:  std_logic_vector(2 downto 0);
signal CM_AXI_AWVALID: std_logic;
signal CM_AXI_AWREADY: std_logic;
signal CM_AXI_WDATA:   std_logic_vector(31 downto 0);
signal CM_AXI_WSTRB:   std_logic_vector(3 downto 0);
signal CM_AXI_WVALID:  std_logic;
signal CM_AXI_WREADY:  std_logic;
signal CM_AXI_BRESP:   std_logic_vector(1 downto 0);
signal CM_AXI_BVALID:  std_logic;
signal CM_AXI_BREADY:  std_logic;
signal CM_AXI_ARADDR:  std_logic_vector(31 downto 0);
signal CM_AXI_ARPROT:  std_logic_vector(2 downto 0);
signal CM_AXI_ARVALID: std_logic;
signal CM_AXI_ARREADY: std_logic;
signal CM_AXI_RDATA:   std_logic_vector(31 downto 0);
signal CM_AXI_RRESP:   std_logic_vector(1 downto 0);
signal CM_AXI_RVALID:  std_logic;
signal CM_AXI_RREADY:  std_logic;

signal STUFF_AXI_AWADDR:  std_logic_vector(31 downto 0);
signal STUFF_AXI_AWPROT:  std_logic_vector(2 downto 0);
signal STUFF_AXI_AWVALID: std_logic;
signal STUFF_AXI_AWREADY: std_logic;
signal STUFF_AXI_WDATA:   std_logic_vector(31 downto 0);
signal STUFF_AXI_WSTRB:   std_logic_vector(3 downto 0);
signal STUFF_AXI_WVALID:  std_logic;
signal STUFF_AXI_WREADY:  std_logic;
signal STUFF_AXI_BRESP:   std_logic_vector(1 downto 0);
signal STUFF_AXI_BVALID:  std_logic;
signal STUFF_AXI_BREADY:  std_logic;
signal STUFF_AXI_ARADDR:  std_logic_vector(31 downto 0);
signal STUFF_AXI_ARPROT:  std_logic_vector(2 downto 0);
signal STUFF_AXI_ARVALID: std_logic;
signal STUFF_AXI_ARREADY: std_logic;
signal STUFF_AXI_RDATA:   std_logic_vector(31 downto 0);
signal STUFF_AXI_RRESP:   std_logic_vector(1 downto 0);
signal STUFF_AXI_RVALID:  std_logic;
signal STUFF_AXI_RREADY:  std_logic;

signal CORE_AXI_AWADDR:  std_logic_vector(31 downto 0);
signal CORE_AXI_AWPROT:  std_logic_vector(2 downto 0);
signal CORE_AXI_AWVALID: std_logic;
signal CORE_AXI_AWREADY: std_logic;
signal CORE_AXI_WDATA:   std_logic_vector(31 downto 0);
signal CORE_AXI_WSTRB:   std_logic_vector(3 downto 0);
signal CORE_AXI_WVALID:  std_logic;
signal CORE_AXI_WREADY:  std_logic;
signal CORE_AXI_BRESP:   std_logic_vector(1 downto 0);
signal CORE_AXI_BVALID:  std_logic;
signal CORE_AXI_BREADY:  std_logic;
signal CORE_AXI_ARADDR:  std_logic_vector(31 downto 0);
signal CORE_AXI_ARPROT:  std_logic_vector(2 downto 0);
signal CORE_AXI_ARVALID: std_logic;
signal CORE_AXI_ARREADY: std_logic;
signal CORE_AXI_RDATA:   std_logic_vector(31 downto 0);
signal CORE_AXI_RRESP:   std_logic_vector(1 downto 0);
signal CORE_AXI_RVALID:  std_logic;
signal CORE_AXI_RREADY:  std_logic;

begin

-- pack SLV AFE LVDS signals into 5x9 2D arrays

afe_p_array(0)(8 downto 0) <= afe0_p(8 downto 0); 
afe_p_array(1)(8 downto 0) <= afe1_p(8 downto 0); 
afe_p_array(2)(8 downto 0) <= afe2_p(8 downto 0); 
afe_p_array(3)(8 downto 0) <= afe3_p(8 downto 0); 
afe_p_array(4)(8 downto 0) <= afe4_p(8 downto 0); 

afe_n_array(0)(8 downto 0) <= afe0_n(8 downto 0);
afe_n_array(1)(8 downto 0) <= afe1_n(8 downto 0);
afe_n_array(2)(8 downto 0) <= afe2_n(8 downto 0);
afe_n_array(3)(8 downto 0) <= afe3_n(8 downto 0);
afe_n_array(4)(8 downto 0) <= afe4_n(8 downto 0);

-- front end deskew and alignment

front_end_inst: front_end 
port map(
    afe_p           => afe_p_array,
    afe_n           => afe_n_array,
    afe_clk_p       => afe_clk_p,
    afe_clk_n       => afe_clk_n,
    clock           => clock,
    clk125          => clk125,
    clk500          => clk500,
    dout            => din_full_array,
    trig            => trig,
	S_AXI_ACLK	    => S_AXI_ACLK,
	S_AXI_ARESETN	=> S_AXI_ARESETN,
	S_AXI_AWADDR	=> FE_AXI_AWADDR,
	S_AXI_AWPROT	=> FE_AXI_AWPROT,
	S_AXI_AWVALID	=> FE_AXI_AWVALID,
	S_AXI_AWREADY	=> FE_AXI_AWREADY,
	S_AXI_WDATA	    => FE_AXI_WDATA,
	S_AXI_WSTRB	    => FE_AXI_WSTRB,
	S_AXI_WVALID	=> FE_AXI_WVALID,
	S_AXI_WREADY	=> FE_AXI_WREADY,
	S_AXI_BRESP	    => FE_AXI_BRESP,
	S_AXI_BVALID	=> FE_AXI_BVALID,
	S_AXI_BREADY	=> FE_AXI_BREADY,
	S_AXI_ARADDR	=> FE_AXI_ARADDR,
	S_AXI_ARPROT	=> FE_AXI_ARPROT,
	S_AXI_ARVALID	=> FE_AXI_ARVALID,
	S_AXI_ARREADY	=> FE_AXI_ARREADY,
	S_AXI_RDATA	    => FE_AXI_RDATA,
	S_AXI_RRESP	    => FE_AXI_RRESP,
	S_AXI_RVALID	=> FE_AXI_RVALID,
	S_AXI_RREADY	=> FE_AXI_RREADY
  );

-- Input spy buffers

spybuffers_inst: spybuffers
port map(
    clock           => clock,
    trig            => trig,
    din             => din_full_array,
    timestamp       => timestamp,
	S_AXI_ACLK	    => S_AXI_ACLK,
	S_AXI_ARESETN	=> S_AXI_ARESETN,
	S_AXI_AWADDR	=> SB_AXI_AWADDR,
	S_AXI_AWPROT	=> SB_AXI_AWPROT,
	S_AXI_AWVALID	=> SB_AXI_AWVALID,
	S_AXI_AWREADY	=> SB_AXI_AWREADY,
	S_AXI_WDATA	    => SB_AXI_WDATA,
	S_AXI_WSTRB	    => SB_AXI_WSTRB,
	S_AXI_WVALID	=> SB_AXI_WVALID,
	S_AXI_WREADY	=> SB_AXI_WREADY,
	S_AXI_BRESP	    => SB_AXI_BRESP,
	S_AXI_BVALID	=> SB_AXI_BVALID,
	S_AXI_BREADY	=> SB_AXI_BREADY,
	S_AXI_ARADDR	=> SB_AXI_ARADDR,
	S_AXI_ARPROT	=> SB_AXI_ARPROT,
	S_AXI_ARVALID	=> SB_AXI_ARVALID,
	S_AXI_ARREADY	=> SB_AXI_ARREADY,
	S_AXI_RDATA	    => SB_AXI_RDATA,
	S_AXI_RRESP	    => SB_AXI_RRESP,
	S_AXI_RVALID	=> SB_AXI_RVALID,
	S_AXI_RREADY	=> SB_AXI_RREADY
  );

-- Timing Endpoint

endpoint_inst: endpoint
port map(
    sysclk_p        => sysclk_p,
    sysclk_n        => sysclk_n,
    sfp_tmg_los     => sfp_tmg_los,
    rx0_tmg_p       => rx0_tmg_p,
    rx0_tmg_n       => rx0_tmg_n,
    sfp_tmg_tx_dis  => sfp_tmg_tx_dis,
    tx0_tmg_p       => tx0_tmg_p,
    tx0_tmg_n       => tx0_tmg_n,
    clock           => clock,
    clk500          => clk500,
    clk125          => clk125,
    timestamp       => timestamp,
    S_AXI_ACLK	    => S_AXI_ACLK,
	S_AXI_ARESETN	=> S_AXI_ARESETN,
	S_AXI_AWADDR	=> EP_AXI_AWADDR,
	S_AXI_AWPROT	=> EP_AXI_AWPROT,
	S_AXI_AWVALID	=> EP_AXI_AWVALID,
	S_AXI_AWREADY	=> EP_AXI_AWREADY,
	S_AXI_WDATA	    => EP_AXI_WDATA,
	S_AXI_WSTRB	    => EP_AXI_WSTRB,
	S_AXI_WVALID	=> EP_AXI_WVALID,
	S_AXI_WREADY	=> EP_AXI_WREADY,
	S_AXI_BRESP	    => EP_AXI_BRESP,
	S_AXI_BVALID	=> EP_AXI_BVALID,
	S_AXI_BREADY	=> EP_AXI_BREADY,
	S_AXI_ARADDR	=> EP_AXI_ARADDR,
	S_AXI_ARPROT	=> EP_AXI_ARPROT,
	S_AXI_ARVALID	=> EP_AXI_ARVALID,
	S_AXI_ARREADY	=> EP_AXI_ARREADY,
	S_AXI_RDATA	    => EP_AXI_RDATA,
	S_AXI_RRESP	    => EP_AXI_RRESP,
	S_AXI_RVALID	=> EP_AXI_RVALID,
	S_AXI_RREADY	=> EP_AXI_RREADY
);

-- SPI master for AFEs and associated DACs

spim_afe_inst: spim_afe 
port map(
    afe_rst       => afe_rst,
    afe_pdn       => afe_pdn,
    afe0_miso     => afe0_miso,
    afe0_sclk     => afe0_sclk,
    afe0_mosi     => afe0_mosi,
    afe12_miso    => afe12_miso,
    afe12_sclk    => afe12_sclk,
    afe12_mosi    => afe12_mosi,
    afe34_miso    => afe34_miso,
    afe34_sclk    => afe34_sclk,
    afe34_mosi    => afe34_mosi,
    afe_sen       => afe_sen,
    trim_sync_n   => trim_sync_n,
    trim_ldac_n   => trim_ldac_n,
    offset_sync_n => offset_sync_n,
    offset_ldac_n => offset_ldac_n,

    S_AXI_ACLK	     => S_AXI_ACLK,
	S_AXI_ARESETN	 => S_AXI_ARESETN,
	S_AXI_AWADDR	 => AFE_AXI_AWADDR,
	S_AXI_AWPROT	 => AFE_AXI_AWPROT,
	S_AXI_AWVALID	 => AFE_AXI_AWVALID,
	S_AXI_AWREADY	 => AFE_AXI_AWREADY,
	S_AXI_WDATA	     => AFE_AXI_WDATA,
	S_AXI_WSTRB	     => AFE_AXI_WSTRB,
	S_AXI_WVALID	 => AFE_AXI_WVALID,
	S_AXI_WREADY	 => AFE_AXI_WREADY,
	S_AXI_BRESP	     => AFE_AXI_BRESP,
	S_AXI_BVALID     => AFE_AXI_BVALID,
	S_AXI_BREADY	 => AFE_AXI_BREADY,
	S_AXI_ARADDR     => AFE_AXI_ARADDR,
	S_AXI_ARPROT     => AFE_AXI_ARPROT,
	S_AXI_ARVALID    => AFE_AXI_ARVALID,
	S_AXI_ARREADY    => AFE_AXI_ARREADY,
	S_AXI_RDATA      => AFE_AXI_RDATA,
	S_AXI_RRESP      => AFE_AXI_RRESP,
	S_AXI_RVALID     => AFE_AXI_RVALID,
	S_AXI_RREADY     => AFE_AXI_RREADY
  );

-- I2C master

i2cm_inst: i2cm 
port map(
    pl_sda          => pl_sda,
    pl_scl          => pl_scl,
    S_AXI_ACLK	    => S_AXI_ACLK,
	S_AXI_ARESETN	=> S_AXI_ARESETN,
	S_AXI_AWADDR	=> I2C_AXI_AWADDR,
	S_AXI_AWPROT	=> I2C_AXI_AWPROT,
	S_AXI_AWVALID	=> I2C_AXI_AWVALID,
	S_AXI_AWREADY	=> I2C_AXI_AWREADY,
	S_AXI_WDATA	    => I2C_AXI_WDATA,
	S_AXI_WSTRB	    => I2C_AXI_WSTRB,
	S_AXI_WVALID	=> I2C_AXI_WVALID,
	S_AXI_WREADY	=> I2C_AXI_WREADY,
	S_AXI_BRESP	    => I2C_AXI_BRESP,
	S_AXI_BVALID	=> I2C_AXI_BVALID,
	S_AXI_BREADY	=> I2C_AXI_BREADY,
	S_AXI_ARADDR	=> I2C_AXI_ARADDR,
	S_AXI_ARPROT	=> I2C_AXI_ARPROT,
	S_AXI_ARVALID	=> I2C_AXI_ARVALID,
	S_AXI_ARREADY	=> I2C_AXI_ARREADY,
	S_AXI_RDATA	    => I2C_AXI_RDATA,
	S_AXI_RRESP	    => I2C_AXI_RRESP,
	S_AXI_RVALID	=> I2C_AXI_RVALID,
	S_AXI_RREADY	=> I2C_AXI_RREADY
  );

-- SPI master for 3 DACs

spim_dac_inst: spim_dac 
port map(
    dac_sclk        => dac_sclk,
    dac_din         => dac_din,
    dac_sync_n      => dac_sync_n,
    dac_ldac_n      => dac_ldac_n, 
    S_AXI_ACLK	    => S_AXI_ACLK,
	S_AXI_ARESETN	=> S_AXI_ARESETN,
	S_AXI_AWADDR	=> DAC_AXI_AWADDR,
	S_AXI_AWPROT	=> DAC_AXI_AWPROT,
	S_AXI_AWVALID	=> DAC_AXI_AWVALID,
	S_AXI_AWREADY	=> DAC_AXI_AWREADY,
	S_AXI_WDATA	    => DAC_AXI_WDATA,
	S_AXI_WSTRB	    => DAC_AXI_WSTRB,
	S_AXI_WVALID	=> DAC_AXI_WVALID,
	S_AXI_WREADY	=> DAC_AXI_WREADY,
	S_AXI_BRESP	    => DAC_AXI_BRESP,
	S_AXI_BVALID	=> DAC_AXI_BVALID,
	S_AXI_BREADY	=> DAC_AXI_BREADY,
	S_AXI_ARADDR	=> DAC_AXI_ARADDR,
	S_AXI_ARPROT	=> DAC_AXI_ARPROT,
	S_AXI_ARVALID	=> DAC_AXI_ARVALID,
	S_AXI_ARREADY	=> DAC_AXI_ARREADY,
	S_AXI_RDATA	    => DAC_AXI_RDATA,
	S_AXI_RRESP	    => DAC_AXI_RRESP,
	S_AXI_RVALID	=> DAC_AXI_RVALID,
	S_AXI_RREADY	=> DAC_AXI_RREADY
  );

-- SPI master for current monitor

spim_cm_inst: spim_cm 
port map(
    cm_sclk         => cm_sclk,
    cm_csn          => cm_csn,
    cm_din          => cm_din,
    cm_dout         => cm_dout,
    cm_drdyn        => cm_drdyn,
    S_AXI_ACLK	    => S_AXI_ACLK,
	S_AXI_ARESETN	=> S_AXI_ARESETN,
	S_AXI_AWADDR	=> CM_AXI_AWADDR,
	S_AXI_AWPROT	=> CM_AXI_AWPROT,
	S_AXI_AWVALID	=> CM_AXI_AWVALID,
	S_AXI_AWREADY	=> CM_AXI_AWREADY,
	S_AXI_WDATA	    => CM_AXI_WDATA,
	S_AXI_WSTRB	    => CM_AXI_WSTRB,
	S_AXI_WVALID	=> CM_AXI_WVALID,
	S_AXI_WREADY	=> CM_AXI_WREADY,
	S_AXI_BRESP	    => CM_AXI_BRESP,
	S_AXI_BVALID	=> CM_AXI_BVALID,
	S_AXI_BREADY	=> CM_AXI_BREADY,
	S_AXI_ARADDR	=> CM_AXI_ARADDR,
	S_AXI_ARPROT	=> CM_AXI_ARPROT,
	S_AXI_ARVALID	=> CM_AXI_ARVALID,
	S_AXI_ARREADY	=> CM_AXI_ARREADY,
	S_AXI_RDATA	    => CM_AXI_RDATA,
	S_AXI_RRESP	    => CM_AXI_RRESP,
	S_AXI_RVALID	=> CM_AXI_RVALID,
	S_AXI_RREADY	=> CM_AXI_RREADY
  );

-- Misc. Stuff

stuff_inst: stuff
port map(
    fan_tach        => fan_tach,
    fan_ctrl        => fan_ctrl,
    hvbias_en       => hvbias_en,
    mux_en          => mux_en,
    mux_a           => mux_a,
    stat_led        => stat_led,
    version         => version,
    S_AXI_ACLK	    => S_AXI_ACLK,
	S_AXI_ARESETN	=> S_AXI_ARESETN,
	S_AXI_AWADDR	=> STUFF_AXI_AWADDR,
	S_AXI_AWPROT	=> STUFF_AXI_AWPROT,
	S_AXI_AWVALID	=> STUFF_AXI_AWVALID,
	S_AXI_AWREADY	=> STUFF_AXI_AWREADY,
	S_AXI_WDATA	    => STUFF_AXI_WDATA,
	S_AXI_WSTRB	    => STUFF_AXI_WSTRB,
	S_AXI_WVALID	=> STUFF_AXI_WVALID,
	S_AXI_WREADY	=> STUFF_AXI_WREADY,
	S_AXI_BRESP	    => STUFF_AXI_BRESP,
	S_AXI_BVALID	=> STUFF_AXI_BVALID,
	S_AXI_BREADY	=> STUFF_AXI_BREADY,
	S_AXI_ARADDR	=> STUFF_AXI_ARADDR,
	S_AXI_ARPROT	=> STUFF_AXI_ARPROT,
	S_AXI_ARVALID	=> STUFF_AXI_ARVALID,
	S_AXI_ARREADY	=> STUFF_AXI_ARREADY,
	S_AXI_RDATA	    => STUFF_AXI_RDATA,
	S_AXI_RRESP	    => STUFF_AXI_RRESP,
	S_AXI_RVALID	=> STUFF_AXI_RVALID,
	S_AXI_RREADY	=> STUFF_AXI_RREADY
  );

-- reduce din_array, since we don't need the full 45 channels * 16 bits for the core

gena_din: for a in 4 downto 0 generate
genc_din: for c in 7 downto 0 generate

    din_array(a)(c)(13 downto 0) <= din_full_array(a)(c)(13 downto 0);

end generate genc_din;
end generate gena_din;

-- core logic is 40 self-trig senders + 10G Ethernet sender

core_inst: core
port map(

    clock => clock,
    reset => '0',
    timestamp => timestamp,
    din => din_array,

    S_AXI_ACLK	    => S_AXI_ACLK,
	S_AXI_ARESETN	=> S_AXI_ARESETN,
	S_AXI_AWADDR	=> CORE_AXI_AWADDR,
	S_AXI_AWPROT	=> CORE_AXI_AWPROT,
	S_AXI_AWVALID	=> CORE_AXI_AWVALID,
	S_AXI_AWREADY	=> CORE_AXI_AWREADY,
	S_AXI_WDATA	    => CORE_AXI_WDATA,
	S_AXI_WSTRB	    => CORE_AXI_WSTRB,
	S_AXI_WVALID	=> CORE_AXI_WVALID,
	S_AXI_WREADY	=> CORE_AXI_WREADY,
	S_AXI_BRESP	    => CORE_AXI_BRESP,
	S_AXI_BVALID	=> CORE_AXI_BVALID,
	S_AXI_BREADY	=> CORE_AXI_BREADY,
	S_AXI_ARADDR	=> CORE_AXI_ARADDR,
	S_AXI_ARPROT	=> CORE_AXI_ARPROT,
	S_AXI_ARVALID	=> CORE_AXI_ARVALID,
	S_AXI_ARREADY	=> CORE_AXI_ARREADY,
	S_AXI_RDATA	    => CORE_AXI_RDATA,
	S_AXI_RRESP	    => CORE_AXI_RRESP,
	S_AXI_RVALID	=> CORE_AXI_RVALID,
	S_AXI_RREADY	=> CORE_AXI_RREADY,

    eth_clk_p => eth_clk_p, 
    eth_clk_n => eth_clk_n,
    eth0_rx_p => eth0_rx_p,
    eth0_rx_n => eth0_rx_n,
    eth0_tx_p => eth0_tx_p,
    eth0_tx_n => eth0_tx_n,
    eth0_tx_dis => eth0_tx_dis
);

-- TO DO: add Xilinx IP block: ZYNQ_PS
-- this IP block requires parameters that must be set by the TCL build script

-- TO DO: add Xilinx IP block: AXI SmartConnecct
-- this IP block requires parameters that must be set by the TCL build script

-- Jonathan recommends we make a top level graphical block with the ZYNQ_PS and 
-- AXI SmartConnect blocks wired up. Bring the 9 AXI-Lite buses to "IO pins" on this 
-- block diagram, THEN export the block as VHDL. Instantiate that HERE. This way we 
-- can keep the project top level as VHDL and keep it GIT friendly.

end DAPHNE3_arch;
