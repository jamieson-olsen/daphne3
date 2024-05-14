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
    vbias_en: out std_logic; -- enable HV bias source
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
    cm_dout: out std_logic;
    cm_din: in std_logic;

    -- SPI master (for 3 DACs)

    dac_sclk:  out std_logic;
    dac_din:   out std_logic;
    dac_syncn: out std_logic;
    dac_ldacn: out std_logic;

    -- SPI master (for AFEs and associated DACs)

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
    afe34_ldacn_off: out std_logic_vector(1 downto 0)

  );
end DAPHNE3;

architecture DAPHNE3_arch of DAPHNE3 is

-- There are 8 (9?) AXI-LITE interfaces in this design:
--
-- 1. timing endpoint
-- 2. front end 
-- 3. spy buffers
-- 4. i2c master (multiple devices)
-- 5. spi master (current monitor)
-- 6. spi master (afe + dac)
-- 7. spi master (3 dacs)
-- 8. misc stuff (fans, vbias, mux control, leds, etc. etc.)
-- 9. core logic? (reserved)
--
-- NOTE: all modules are written assuming that the AXI LITE clock is 100MHz

component front_end -- front end data alignment logic
port(
    afe_p, afe_n: in array_5x9_type; -- 5 x 9 = 45 LVDS pairs (7..0 = data, 8 = fclk)
    afe_clk_p, afe_clk_n: out std_logic; -- copy of 62.5MHz master clock fanned out to AFEs
    clk500:  in  std_logic; -- 500MHz bit clock (these 3 clocks must be related/aligned)
    clk125:  in  std_logic; -- 125MHz byte clock
    clock:   in  std_logic; -- 62.5MHz master clock
    dout:    out array_5x9x16_type; -- data synchronized to clock
    trig:    out std_logic; -- user generated trigger sync to clock
    S_AXI_ACLK: in std_logic; -- AXI-LITE 100MHz
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

component spybuffers -- input spy buffers
port(
    clock: in std_logic; -- master clock
    reset: in std_logic; -- active high reset async
    trig:  in std_logic; -- trigger pulse sync to clock
    din:   in array_5x9x16_type; -- AFE data sync to clock
    timestamp: in std_logic_vector(63 downto 0); -- timestamp sync to clock
	S_AXI_ACLK	    : in std_logic; -- AXI-LITE 100MHz
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

component endpoint -- timing endpoint
port(
    sysclk100:   in std_logic;  -- 100MHz constant system clock from PS or oscillator
    reset_async: in std_logic;  -- async hard reset from the PS
    soft_reset:  out std_logic;  -- soft reset from user sync to axi clock
    sfp_tmg_los: in std_logic; -- loss of signal
    rx0_tmg_p, rx0_tmg_n: in std_logic; -- LVDS recovered serial data ACKCHYUALLY the clock!
    sfp_tmg_tx_dis: out std_logic; -- high to disable timing SFP TX
    tx0_tmg_p, tx0_tmg_n: out std_logic; -- send data upstream
    clock:   out std_logic;  -- master clock 62.5MHz
    clk500:  out std_logic;  -- front end clock 500MHz
    clk125:  out std_logic;  -- front end clock 125MHz
    timestamp: out std_logic_vector(63 downto 0); -- sync to mclk
	S_AXI_ACLK: in std_logic; -- AXI-LITE 100MHz
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

component i2cm is -- I2C master for lots of things
port(
    pl_sda: inout std_logic;
    pl_scl: out std_logic;
	S_AXI_ACLK	    : in std_logic; -- AXI-LITE 100MHz
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

component spim_dac -- SPI master for 3 DAC chips
port(
    dac_sclk: out std_logic;
    dac_din: out std_logic;
    dac_syncn: out std_logic;
    dac_ldacn: out std_logic;
	S_AXI_ACLK	    : in std_logic; -- AXI-LITE 100MHz
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

component spim_cm -- SPI master current monitor
port(
    cm_sclk: out std_logic;
    cm_csn: out std_logic;
    cm_din: out std_logic;
    cm_dout: in std_logic;
    cm_drdyn: in std_logic;
	S_AXI_ACLK	    : in std_logic; -- AXI-LITE 100MHz
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

component spim_afe 
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
	S_AXI_ACLK	    : in std_logic; -- AXI-LITE 100MHz
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

component stuff -- catch all module for misc signals
port(
    fan_tach: in  std_logic_vector(1 downto 0); -- fan tach speed monitoring
    fan_ctrl: out std_logic; -- pwm speed control common to both fans
    vbias_en: out std_logic; -- high = high voltage bias generator is ON
    mux_en: out std_logic_vector(1 downto 0); -- analog mux enables
    mux_a: out std_logic_vector(1 downto 0); -- analog mux selects
    stat_led: out std_logic_vector(5 downto 0); -- general purpose LEDs
	S_AXI_ACLK	    : in std_logic; -- AXI-LITE 100MHz
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

signal afe_p_array, afe_n_array: array_5x9_type;
signal din_array: array_5x9x16_type;
signal trig: std_logic;
signal timestamp: std_logic_vector(63 downto 0);
signal clock, clk125, clk500: std_logic;
signal soft_reset: std_logic;

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

front_end_inst: front_end -- front end deskew and alignment
port map(
    afe_p           => afe_p_array, -- AFE high speed data LVDS 
    afe_n           => afe_n_array,
    afe_clk_p       => afe_clk_p, -- 62.5MHz clock output to AFEs LVDS
    afe_clk_n       => afe_clk_n,
    clock           => clock, -- 62.5MHz master clock
    clk125          => clk125, -- 125MHz
    clk500          => clk500, -- 500MHz
    dout            => din_array, -- AFE data aligned in master clock domain
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

spybuffers_inst: spybuffers -- input spy buffers
port map(
    clock           => clock,
    reset           => soft_reset,
    trig            => trig,
    din             => din_array,
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

endpoint_inst: endpoint -- timing endpoint
port map(
    sysclk100       => sysclk100, -- 100MHz system clock from clock generator
    reset_async     => reset_async, -- hard async reset from PS
    soft_reset      => soft_reset, -- user soft reset for front end and core
    sfp_tmg_los     => sfp_tmg_los, -- timing endpoint sfp signals
    rx0_tmg_p       => rx0_tmg_p,
    rx0_tmg_n       => rx0_tmg_n,
    sfp_tmg_tx_dis  => sfp_tmg_tx_dis,
    tx0_tmg_p       => tx0_tmg_p,
    tx0_tmg_n       => tx0_tmg_n,
    clock           => clock, -- 62.5MHz master clock 
    clk500          => clk500, -- 500MHz clock used by the front end
    clk125          => clk125, -- 125MHz clock used by the front end
    timestamp       => timestamp, -- sync to master clock
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

spim_afe_inst: spim_afe -- SPI master for AFEs and associated DACs
port map(
    afe_rst          => afe_rst, -- AFE hard reset common to all AFEs
    afe_pdn          => afe_pdn, -- AFE power down common to all AFEs
    afe0_miso        => afe0_miso,
    afe0_sclk        => afe0_sclk,
    afe0_sdata       => afe0_sdata,
    afe0_sen         => afe0_sen,
    afe0_csn_trim    => afe0_csn_trim,
    afe0_csn_off     => afe0_csn_off,
    afe0_ldacn_trim  => afe0_ldacn_trim,
    afe0_ldacn_off   => afe0_ldacn_off,
    afe12_miso       => afe12_miso,
    afe12_sclk       => afe12_sclk,
    afe12_sdata      => afe12_sdata,
    afe12_sen        => afe12_sen,
    afe12_csn_trim   => afe12_csn_trim,
    afe12_csn_off    => afe12_csn_off,
    afe12_ldacn_trim => afe12_ldacn_trim,
    afe12_ldacn_off  => afe12_ldacn_off,
    afe34_miso       => afe34_miso,
    afe34_sclk       => afe34_sclk,
    afe34_sdata      => afe34_sdata,
    afe34_sen        => afe34_sen,
    afe34_csn_trim   => afe34_csn_trim,
    afe34_csn_off    => afe34_csn_off,
    afe34_ldacn_trim => afe34_ldacn_trim,
    afe34_ldacn_off  => afe34_ldacn_off,
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

i2cm_inst: i2cm -- I2C master
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

spim_dac_inst: spim_dac -- SPI master for 3 DACs
port map(
    dac_sclk        => dac_sclk,
    dac_din         => dac_din,
    dac_syncn       => dac_syncn,
    dac_ldacn       => dac_ldacn, 
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
end component;

spim_cm_inst: spim_cm -- SPI master for current monitor
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

stuff_inst: stuff -- this module is a 'catch all' for the misc stuff
port map(
    fan_tach        => fan_tach,
    fan_ctrl        => fan_ctrl,
    vbias_en        => vbias_en,
    mux_en          => mux_en,
    mux_a           => mux_a,
    stat_led        => stat_led,
    S_AXI_ACLK	    => S_AXI_ACLK,
	S_AXI_ARESETN	=> S_AXI_ARESETN,
	S_AXI_AWADDR	=> STF_AXI_AWADDR,
	S_AXI_AWPROT	=> STF_AXI_AWPROT,
	S_AXI_AWVALID	=> STF_AXI_AWVALID,
	S_AXI_AWREADY	=> STF_AXI_AWREADY,
	S_AXI_WDATA	    => STF_AXI_WDATA,
	S_AXI_WSTRB	    => STF_AXI_WSTRB,
	S_AXI_WVALID	=> STF_AXI_WVALID,
	S_AXI_WREADY	=> STF_AXI_WREADY,
	S_AXI_BRESP	    => STF_AXI_BRESP,
	S_AXI_BVALID	=> STF_AXI_BVALID,
	S_AXI_BREADY	=> STF_AXI_BREADY,
	S_AXI_ARADDR	=> STF_AXI_ARADDR,
	S_AXI_ARPROT	=> STF_AXI_ARPROT,
	S_AXI_ARVALID	=> STF_AXI_ARVALID,
	S_AXI_ARREADY	=> STF_AXI_ARREADY,
	S_AXI_RDATA	    => STF_AXI_RDATA,
	S_AXI_RRESP	    => STF_AXI_RRESP,
	S_AXI_RVALID	=> STF_AXI_RVALID,
	S_AXI_RREADY	=> STF_AXI_RREADY
  );

-- Xilinx IP block: ZYNQ_PS
-- this IP block requires parameters that must be set by the TCL build script

-- Xilinx IP block: AXI SmartConnecct
-- this IP block requires parameters that must be set by the TCL build script

end DAPHNE3_arch;
