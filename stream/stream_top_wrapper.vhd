-- stream_top_wrapper.vhd
-- eight stream4 modules + wib sender

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.daphne3_package.all;

entity stream_top_wrapper
generic(
    N_SRC: positive  := 2;   -- each mux has 2 inputs
    N_MGT: positive  := 4    -- four transceivers
);
port(
    clock: in std_logic; -- 62.5MHz master clock
    reset: in std_logic;
    ts: in std_logic_vector(63 downto 0); -- timestamp

    din00: std_logic_vector(13 downto 0); -- AFE data after alignment
    din01: std_logic_vector(13 downto 0);
    din02: std_logic_vector(13 downto 0);
    din03: std_logic_vector(13 downto 0);
    din04: std_logic_vector(13 downto 0);
    din05: std_logic_vector(13 downto 0);
    din06: std_logic_vector(13 downto 0);
    din07: std_logic_vector(13 downto 0);
    din08: std_logic_vector(13 downto 0);
    din09: std_logic_vector(13 downto 0);
    din10: std_logic_vector(13 downto 0);
    din11: std_logic_vector(13 downto 0);
    din12: std_logic_vector(13 downto 0);
    din13: std_logic_vector(13 downto 0);
    din14: std_logic_vector(13 downto 0);
    din15: std_logic_vector(13 downto 0);
    din16: std_logic_vector(13 downto 0);
    din17: std_logic_vector(13 downto 0);
    din18: std_logic_vector(13 downto 0);
    din19: std_logic_vector(13 downto 0);
    din20: std_logic_vector(13 downto 0);
    din21: std_logic_vector(13 downto 0);
    din22: std_logic_vector(13 downto 0);
    din23: std_logic_vector(13 downto 0);
    din24: std_logic_vector(13 downto 0);
    din25: std_logic_vector(13 downto 0);
    din26: std_logic_vector(13 downto 0);
    din27: std_logic_vector(13 downto 0);
    din28: std_logic_vector(13 downto 0);
    din29: std_logic_vector(13 downto 0);
    din30: std_logic_vector(13 downto 0);
    din31: std_logic_vector(13 downto 0);

	S_AXI_ACLK	    : in std_logic;  -- axi lite interface is used for IPBUS stuff...
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
	S_AXI_RREADY	: in std_logic;

    eth_clk_p: in std_logic; -- I/O for mgt refclk 156.25MHz
    eth_clk_n: in std_logic;

    eth_rx_p: in std_logic_vector(N_MGT-1 downto 0); -- I/O for SFPs
    eth_rx_n: in std_logic_vector(N_MGT-1 downto 0);
    eth_tx_p: out std_logic_vector(N_MGT-1 downto 0);
    eth_tx_n: out std_logic_vector(N_MGT-1 downto 0);
    eth_tx_dis: out std_logic_vector(N_MGT-1 downto 0)

  );
end stream_top_wrapper;

architecture stream_top_wrapper_arch of stream_top_wrapper is

component stream4
    generic( BLOCKS_PER_RECORD: integer := 64 ); 
    port(
        clock: in std_logic;
        areset: in std_logic;
        ts: in std_logic_vector(63 downto 0);
        din: array_4x14_type;
        dout:  out std_logic_vector(63 downto 0);
        valid: out std_logic;
        last: out std_logic
    );
end component;

component wib_eth_readout
    generic(
        N_SRC: positive;
        N_MGT: positive;
        IN_BUF_DEPTH: natural;
        REF_FREQ: t_freq := f156_25
    );
    port(
        ipb_clk: in std_logic;
        ipb_rst: in std_logic;
        ipb_in: in  ipb_wbus;
        ipb_out: out ipb_rbus;
        eth_rx_p: in std_logic_vector(N_MGT-1 downto 0); -- Ethernet rx from SFP
        eth_rx_n: in std_logic_vector(N_MGT-1 downto 0);
        eth_tx_p: out std_logic_vector(N_MGT-1 downto 0); -- Ethernet tx to SFP
        eth_tx_n: out std_logic_vector(N_MGT-1 downto 0);
        eth_tx_dis: out std_logic_vector(N_MGT-1 downto 0); -- SFP tx_disable
        eth_clk_p: in std_logic; -- Transceiver refclk
        eth_clk_n: in std_logic;
        clk: in std_logic; -- DUNE base clock
        rst: in std_logic; -- DUNE base clock sync reset
        d: in array_of_src_d_arrays(N_MGT-1 downto 0) (N_SRC-1 downto 0); -- Data from sources
        ts: in std_logic_vector(63 downto 0);
        nuke: out std_logic;
        soft_rst: out std_logic;
        ext_mac_addr    : in mac_addr_array(N_MGT-1 downto 0);
        ext_ip_addr     : in ip_addr_array(N_MGT-1 downto 0);
        ext_port_addr   : in udp_port_array(N_MGT-1 downto 0)     
    );
end component;

begin

type stream_din_mgt_type is array(N_MGT-1 downto 0) of array_4x14_type;
type stream_din_mgt_mux_type is array(N_SRC-1 downto 0) of stream_din_mgt_type;

signal stream_din: stream_din_mgt_mux_type;
signal d: array_of_src_d_arrays; -- not sure where adam defines this

-- simple input mapping into stream_din(mgt)(mux)(input)

stream_din(0)(0)(0) <= din00;
stream_din(0)(0)(1) <= din01;
stream_din(0)(0)(2) <= din02;
stream_din(0)(0)(3) <= din03;

stream_din(0)(1)(0) <= din04;
stream_din(0)(1)(1) <= din05;
stream_din(0)(1)(2) <= din06;
stream_din(0)(1)(3) <= din07;

stream_din(1)(0)(0) <= din08;
stream_din(1)(0)(1) <= din09;
stream_din(1)(0)(2) <= din10;
stream_din(1)(0)(3) <= din11;

stream_din(1)(1)(0) <= din12;
stream_din(1)(1)(1) <= din13;
stream_din(1)(1)(2) <= din14;
stream_din(1)(1)(3) <= din15;

stream_din(2)(0)(0) <= din16;
stream_din(2)(0)(1) <= din17;
stream_din(2)(0)(2) <= din18;
stream_din(2)(0)(3) <= din19;

stream_din(2)(1)(0) <= din20;
stream_din(2)(1)(1) <= din21;
stream_din(2)(1)(2) <= din22;
stream_din(2)(1)(3) <= din23;

stream_din(3)(0)(0) <= din24;
stream_din(3)(0)(1) <= din25;
stream_din(3)(0)(2) <= din26;
stream_din(3)(0)(3) <= din27;

stream_din(3)(1)(0) <= din28;
stream_din(3)(1)(1) <= din29;
stream_din(3)(1)(2) <= din30;
stream_din(3)(1)(3) <= din31;

-- eight streaming senders

genMGT: for mgt in N_MGT-1 downto 0 generate
genMUX: for mux in N_SRC-1 downto 0 generate

    stream4_inst: stream4
        generic map( BLOCKS_PER_RECORD => 64 )
        port map(
            clock  => clock,
            areset => reset,
            ts     => ts,
            din    => stream_din(mgt)(mux),
            dout   => d(mgt)(mux).data, -- just guesssing here???
            valid  => d(mgt)(mux).valid, 
            last   => d(mgt)(mux).last
        );

end generate genMUX;
end generate genMGT;

-- 10G Ethernet sender

wib_eth_readout_inst: component wib_eth_readout
    generic map(
        N_SRC => N_SRC,
        N_MGT => N_MGT
    );
    port map(

        ipb_clk => ipb_clk, -- IPBUS 
        ipb_rst => ipb_rst,
        ipb_in => ipb_in,
        ipb_out => ipb_out,

        eth_rx_p => eth_rx_p, 
        eth_rx_n => eth_rx_n,
        eth_tx_p => eth_tx_p,
        eth_tx_n => eth_tx_n,
        eth_tx_dis => eth_tx_dis,

        eth_clk_p => eth_clk_p, 
        eth_clk_n => eth_clk_n,

        clk => clock,
        rst => reset,

        d => d,
        ts => ts,

        nuke => open,
        soft_rst => open,

        ext_mac_addr =>    : in mac_addr_array(N_MGT-1 downto 0); -- not sure where this is defined
        ext_ip_addr  =>     : in ip_addr_array(N_MGT-1 downto 0);
        ext_port_addr =>  : in udp_port_array(N_MGT-1 downto 0)     
    );

-- another module needed here!
-- something to translate AXI_LITE to IPBUS
-- this should exist already for the wib....




end stream_top_wrapper_arch;
