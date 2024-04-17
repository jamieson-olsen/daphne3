-- DAPHNE3.vhd
--
-- PL logic component which encapsulates the front end and spy buffers
-- eventually it will also include the core logic as well
--
-- all exposed ports are simple std_logic and std_logic_vector to be compatible
-- with the vivado project graphical top level
--
-- Jamieson Olsen <jamieson@fnal.gov>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.daphne3_package.all;

entity DAPHNE3 is
-- generic(version: std_logic_vector(27 downto 0) := X"1234567"); -- git commit number is passed in from tcl build script
port(

    -- PL/PS internal signals 

    reset: in std_logic; -- async reset from the PS

    clock:   in  std_logic; -- 62.5MHz master clock
    clk125:  in  std_logic; -- 125MHz byte clock
    clk500:  in  std_logic; -- 500MHz bit clock

    ts: std_logic_vector(63 downto 0); -- timestamp sync to clock

    -- AFE LVDS high speed data interface (connect to IO pins)

    afe0_p, afe0_n: in std_logic_vector(8 downto 0);
    afe1_p, afe1_n: in std_logic_vector(8 downto 0);
    afe2_p, afe2_n: in std_logic_vector(8 downto 0);
    afe3_p, afe3_n: in std_logic_vector(8 downto 0);
    afe4_p, afe4_n: in std_logic_vector(8 downto 0);

    afe_clk_p, afe_clk_n: out std_logic; -- copy of 62.5MHz master clock sent to AFEs

    -- AXI-Lite interface for spy buffers

    SB_AXI_ACLK: in std_logic;
    SB_AXI_ARESETN: in std_logic;
    SB_AXI_AWADDR: in std_logic_vector(31 downto 0);
    SB_AXI_AWPROT: in std_logic_vector(2 downto 0);
    SB_AXI_AWVALID: in std_logic;
    SB_AXI_AWREADY: out std_logic;
    SB_AXI_WDATA: in std_logic_vector(31 downto 0);
    SB_AXI_WSTRB: in std_logic_vector(3 downto 0);
    SB_AXI_WVALID: in std_logic;
    SB_AXI_WREADY: out std_logic;
    SB_AXI_BRESP: out std_logic_vector(1 downto 0);
    SB_AXI_BVALID: out std_logic;
    SB_AXI_BREADY: in std_logic;
    SB_AXI_ARADDR: in std_logic_vector(31 downto 0);
    SB_AXI_ARPROT: in std_logic_vector(2 downto 0);
    SB_AXI_ARVALID: in std_logic;
    SB_AXI_ARREADY: out std_logic;
    SB_AXI_RDATA: out std_logic_vector(31 downto 0);
    SB_AXI_RRESP: out std_logic_vector(1 downto 0);
    SB_AXI_RVALID: out std_logic;
    SB_AXI_RREADY: in std_logic;

    -- AXI-Lite interface for the front end registers

    FE_AXI_ACLK: in std_logic;
    FE_AXI_ARESETN: in std_logic;
    FE_AXI_AWADDR: in std_logic_vector(31 downto 0);
    FE_AXI_AWPROT: in std_logic_vector(2 downto 0);
    FE_AXI_AWVALID: in std_logic;
    FE_AXI_AWREADY: out std_logic;
    FE_AXI_WDATA: in std_logic_vector(31 downto 0);
    FE_AXI_WSTRB: in std_logic_vector(3 downto 0);
    FE_AXI_WVALID: in std_logic;
    FE_AXI_WREADY: out std_logic;
    FE_AXI_BRESP: out std_logic_vector(1 downto 0);
    FE_AXI_BVALID: out std_logic;
    FE_AXI_BREADY: in std_logic;
    FE_AXI_ARADDR: in std_logic_vector(31 downto 0);
    FE_AXI_ARPROT: in std_logic_vector(2 downto 0);
    FE_AXI_ARVALID: in std_logic;
    FE_AXI_ARREADY: out std_logic;
    FE_AXI_RDATA: out std_logic_vector(31 downto 0);
    FE_AXI_RRESP: out std_logic_vector(1 downto 0);
    FE_AXI_RVALID: out std_logic;
    FE_AXI_RREADY: in std_logic

  );
end DAPHNE3;

architecture DAPHNE3_arch of DAPHNE3 is

component front_end 
port(

    -- AFE interface: 

    afe_p, afe_n: in array_5x9_type; -- 5 x 9 = 45 LVDS pairs (7..0 = data, 8 = fclk)
    afe_clk_p, afe_clk_n: out std_logic; -- copy of 62.5MHz master clock fanned out to AFEs

    -- high speed FPGA fabric interface:

    clk500:  in  std_logic; -- 500MHz bit clock (these 3 clocks must be related/aligned)
    clk125:  in  std_logic; -- 125MHz byte clock
    clock:   in  std_logic; -- 62.5MHz master clock
    dout:    out array_5x9x16_type; -- data synchronized to clock
    trig:    out std_logic; -- user generated trigger sync to clock

    -- AXI-Lite interface:

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

component spybuffers
port(
    clock: in std_logic; -- master clock
    reset: in std_logic; -- active high reset async
    trig:  in std_logic; -- trigger pulse sync to clock
    din:   in array_5x9x16_type; -- AFE data sync to clock
    ts:    in std_logic_vector(63 downto 0); -- timestamp sync to clock
    
    -- AXI-LITE interface

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

signal afe_p_array, afe_n_array: array_5x9_type;
signal din_array: array_5x9x16_type;
signal trig: std_logic;

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

front_end_inst: front_end
port map(
    afe_p => afe_p_array,
    afe_n => afe_n_array,
    afe_clk_p => afe_clk_p,
    afe_clk_n => afe_clk_n,
    clock => clock,
    clk125 => clk125,
    clk500 => clk500,
    dout => din_array,
    trig => trig,
	S_AXI_ACLK	    => FE_AXI_ACLK,
	S_AXI_ARESETN	=> FE_AXI_ARESETN,
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

spybuffers_inst: spybuffers
port map(
    clock => clock,
    reset => reset,
    trig => trig,
    din => din_array, -- array_5x9x16_type
    ts => ts,
	S_AXI_ACLK	    => SB_AXI_ACLK,
	S_AXI_ARESETN	=> SB_AXI_ARESETN,
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

end DAPHNE3_arch;
