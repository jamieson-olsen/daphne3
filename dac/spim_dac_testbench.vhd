-- testbench for SPI serial DACs
-- jamieson olsen <jamieson@fnal.gov>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

use work.daphne3_package.all;

entity spim_dac_testbench is
end spim_dac_testbench;

architecture spim_dac_testbench_arch of spim_dac_testbench is

component AD5327 is
generic(refdes: STRING := "U?");
port(
    sclk: in std_logic; -- 30MHz max
    din: in std_logic;
    sync_n: in std_logic;
    ldac_n: in std_logic;
    sdo: out std_logic
);
end component;

component spim_dac
generic( CLKDIV: integer := 8 );
port(
    dac_sclk: out std_logic;
    dac_din: out std_logic;
    dac_sync_n: out std_logic;
    dac_ldac_n: out std_logic;
    AXI_IN: in AXILITE_INREC;
    AXI_OUT: out AXILITE_OUTREC
  );
end component;

signal sclk, cs_n, din, dout, drdyn: std_logic;
signal din0, din1, din2: std_logic;
signal sync_n, ldac_n: std_logic;

signal AXI_IN: AXILITE_INREC := (ACLK=>'0', ARESETN=>'0', AWADDR=>X"00000000", 
    AWPROT=>"000", AWVALID=>'0', WDATA=>X"00000000", WSTRB=>"0000", WVALID=>'0', 
    BREADY=>'0', ARADDR=>X"00000000", ARPROT=>"000", ARVALID=>'0', RREADY=>'0');
signal AXI_OUT: AXILITE_OUTREC;

constant ACLK_period: time := 10.0ns;  -- 100 MHz

begin

-- three serial DAC chips daisy chained...

firstdac_inst: AD5327
generic map(refdes => "U50")
port map(
    sclk => sclk,
    din => din0,
    sync_n => sync_n,
    ldac_n => ldac_n,
    sdo => din1
);

middledac_inst: AD5327
generic map(refdes => "U53")
port map(
    sclk => sclk,
    din => din1,
    sync_n => sync_n,
    ldac_n => ldac_n,
    sdo => din2
);

lastdac_inst: AD5327
generic map(refdes => "U5")
port map(
    sclk => sclk,
    din => din2,
    sync_n => sync_n,
    ldac_n => ldac_n,
    sdo => open
);

DUT: spim_dac
generic map( CLKDIV => 8 ) -- SCLK is 100MHz/8 = 12.5MHz OK
port map(

    dac_sclk => sclk,
    dac_din => din0,
    dac_sync_n => sync_n,
    dac_ldac_n => ldac_n,
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

wait for 500ns;
AXI_IN.ARESETN <= '1'; -- release AXI reset

wait for 500ns;
axipoke(addr => X"00000004", data => X"00005050"); -- data to sent to first DAC U50
wait for 500ns;
axipoke(addr => X"00000008", data => X"00005353"); -- data to sent to middle DAC U53
wait for 500ns;
axipoke(addr => X"0000000C", data => X"0000DAC5"); -- data to sent to last DAC U5

wait for 500ns;
axipoke(addr => X"00000000", data => X"DEADBEEF");  -- write anything to CTRL register... GO!

wait;
end process aximaster_proc;

end spim_dac_testbench_arch;
