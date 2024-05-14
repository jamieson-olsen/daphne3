-- stuff.vhd
--
-- this module is a "catch all" for a bunch of misc stuff that exists on the PL side
-- and needs to connect to the PS side via a single axi-lite interface. things like:
--
-- 1. pwm control and monitor of 2 chassis fans
-- 2. analog mux select and enable pins 
-- 3. vbias high voltage control
-- 4. user leds
--
-- fan tach inputs are pulsed low TWO times per revolution
--
-- fan pwm control is 25kHz clock, note that this signal is inverted by Q2 on the board
-- the fans have internal pullup on this PWM signal. so if ctrl=0 the fan PWM signal will be HIGH
-- and will run at FULL SPEED. if ctrl=1 the PWM signal will be LOW and the fans will be OFF.
-- if ctrl is a 25kHz clock (high 25%, low 75%) then the fans will be running at 75%
-- if ctrl is a 25kHz clock (high 75%, low 25%) then the fans will be running at 25%
--
-- "stuff" has some 32-bit registers:
--
-- base+0: fan speed control register. 0=off, 255=full speed. power on default is full speed. read/write
-- base+4: fan0 actual speed in RPM, readonly
-- base+8: fan0 actual speed in RPM, readonly
-- base+12: vbias control is bit 0, read/write, default is 0 (off)
-- base+16: analog mux control bits(1..0)=mux_en(1..0)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity stuff is
port(
    fan_tach: in  std_logic_vector(1 downto 0); -- fan tach speed monitoring
    fan_ctrl: out std_logic; -- pwm speed control common to both fans
    vbias_en: out std_logic; -- high = high voltage bias generator is ON
    mux_en: out std_logic_vector(1 downto 0); -- analog mux enables
    mux_a: out std_logic_vector(1 downto 0); -- analog mux selects
    stat_led: out std_logic_vector(5 downto 0); -- general purpose LEDs
  
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
end stuff;

architecture stuff_arch of stuff is

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

end stuff_arch;
