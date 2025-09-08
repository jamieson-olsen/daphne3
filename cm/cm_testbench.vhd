-- testbench for current monitor module
-- jamieson olsen <jamieson@fnal.gov>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

use work.daphne3_package.all;

entity cm_testbench is
end cm_testbench;

architecture cm_testbench_arch of cm_testbench is

component ADS1261 is -- simple BFM of the current monitor chip
port(
    sclk: in std_logic;
    din:  in std_logic;
    cs_n: in std_logic;
    dout: out std_logic;
    drdyn: out std_logic
);
end component;

component spim_cm -- custom SPI master logic for the current monitor
port(
    cm_sclk: out std_logic;
    cm_csn: out std_logic;
    cm_din: out std_logic;
    cm_dout: in std_logic;
    cm_drdyn: in std_logic;
    AXI_IN: in AXILITE_INREC;
    AXI_OUT: out AXILITE_OUTREC 
  );
end component;

signal sclk, cs_n, din, dout, drdyn: std_logic;

signal AXI_IN: AXILITE_INREC := (ACLK=>'0', ARESETN=>'0', AWADDR=>X"00000000", 
    AWPROT=>"000", AWVALID=>'0', WDATA=>X"00000000", WSTRB=>"0000", WVALID=>'0', 
    BREADY=>'0', ARADDR=>X"00000000", ARPROT=>"000", ARVALID=>'0', RREADY=>'0');
signal AXI_OUT: AXILITE_OUTREC;

constant ACLK_period: time := 10.0ns;  -- 100 MHz

begin

cm_inst: ADS1261
port map(
    sclk => sclk,
    din => din,
    cs_n => cs_n,
    dout => dout,
    drdyn => drdyn
);

DUT: spim_cm
port map(

    cm_sclk => sclk,
    cm_csn => cs_n,
    cm_din => din,
    cm_dout => dout,
    cm_drdyn => drdyn,
    AXI_IN => AXI_IN,
    AXI_OUT => AXI_OUT
  );

-- now we simulate the AXI-LITE master doing reads and writes...

AXI_IN.ACLK <= not AXI_IN.ACLK after ACLK_period/2;

aximaster_proc: process

procedure axipoke( constant addr: in std_logic_vector;
                   constant data: in std_logic_vector ) is
begin
    wait until rising_edge(AXI_IN.ACLK);
    AXI_IN.AWADDR <= addr;
    AXI_IN.AWVALID <= '1';
    AXI_IN.WDATA <= data;
    AXI_IN.WVALID <= '1';
    AXI_IN.BREADY <= '1';
    AXI_IN.WSTRB <= "1111";
    wait until (rising_edge(AXI_IN.ACLK) and AXI_OUT.AWREADY='1' and AXI_OUT.WREADY='1');
    AXI_IN.AWADDR <= X"00000000";
    AXI_IN.AWVALID <= '0';
    AXI_IN.WDATA <= X"00000000";
    AXI_IN.AWVALID <= '0';
    AXI_IN.WSTRB <= "0000";
    wait until (rising_edge(AXI_IN.ACLK) and AXI_OUT.BVALID='1');
    AXI_IN.BREADY <= '0';
end procedure axipoke;

procedure axipeek( constant addr: in std_logic_vector ) is
begin
    wait until rising_edge(AXI_IN.ACLK);
    AXI_IN.ARADDR <= addr;
    AXI_IN.ARVALID <= '1';
    AXI_IN.RREADY <= '1';
    wait until (rising_edge(AXI_IN.ACLK) and AXI_OUT.ARREADY='1');
    AXI_IN.ARADDR <= X"00000000";
    AXI_IN.ARVALID <= '0';
    wait until (rising_edge(AXI_IN.ACLK) and AXI_OUT.RVALID='1');
    AXI_IN.RREADY <= '0';
end procedure axipeek;

begin

    wait for 300ns;
    AXI_IN.ARESETN <= '1'; -- release AXI reset
    
    wait for 500ns;
    axipoke(addr => X"00000000", data => X"00000012"); -- Write 4 bytes into the input FIFO 
    wait for 500ns;
    axipoke(addr => X"00000000", data => X"00000034"); 
    wait for 500ns;
    axipoke(addr => X"00000000", data => X"00000056"); 
    wait for 500ns;
    axipoke(addr => X"00000000", data => X"00000078"); 
    
    wait for 500ns;
    axipoke(addr => X"00000004", data => X"DEADBEEF"); -- GO!
    
    wait for 5us; -- wait while SPI shifting is going on
    
    axipeek(addr => X"00000000"); -- read four bytes from the output FIFO
    wait for 300ns;
    axipeek(addr => X"00000000");
    wait for 300ns;
    axipeek(addr => X"00000000");
    wait for 400ns;
    axipeek(addr => X"00000000");

wait;
end process aximaster_proc;

end cm_testbench_arch;
