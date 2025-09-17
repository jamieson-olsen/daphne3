-- testbench for the new input spy buffer with axi lite interface
-- jamieson olsen <jamieson@fnal.gov>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library xpm;
use xpm.vcomponents.all;

use work.daphne3_package.all;

entity inspybuff_tb is
end inspybuff_tb;

architecture inspybuff_tb_arch of inspybuff_tb is

component inspybuff
	port (
	    clock: in std_logic;
	    din: in array_40x14_type; 
	    trigger: in std_logic;
        AXI_IN: in AXILITE_INREC;  
        AXI_OUT: out AXILITE_OUTREC
  	);
end component;

constant clock_period: time := 16.0ns;  -- 62.5 MHz
signal clock: std_logic := '0';
signal din: array_40x14_type := (
"00000000000000","00000000000000","00000000000000","00000000000000",
"00000000000000","00000000000000","00000000000000","00000000000000",
"00000000000000","00000000000000","00000000000000","00000000000000",
"00000000000000","00000000000000","00000000000000","00000000000000",
"00000000000000","00000000000000","00000000000000","00000000000000",
"00000000000000","00000000000000","00000000000000","00000000000000",
"00000000000000","00000000000000","00000000000000","00000000000000",
"00000000000000","00000000000000","00000000000000","00000000000000",
"00000000000000","00000000000000","00000000000000","00000000000000",
"00000000000000","00000000000000","00000000000000","00000000000000");
signal trigger: std_logic := '0';

signal AXI_IN: AXILITE_INREC := (ACLK=>'0', ARESETN=>'0', AWADDR=>X"00000000", 
    AWPROT=>"000", AWVALID=>'0', WDATA=>X"00000000", WSTRB=>"0000", WVALID=>'0', 
    BREADY=>'0', ARADDR=>X"00000000", ARPROT=>"000", ARVALID=>'0', RREADY=>'0');
signal AXI_OUT: AXILITE_OUTREC;

constant ACLK_period: time := 10.0ns;  -- 100 MHz

begin

clock <= not clock after clock_period/2;

fakesender_proc: process -- some dumb repeating thing
begin
    wait until rising_edge(clock);  
    for c in 39 downto 0 loop
        din(c)(13 downto 8) <= std_logic_vector( to_unsigned(c,6) );
        din(c)(7 downto 0)  <= std_logic_vector( unsigned(din(c)(7 downto 0))+1 );
    end loop;
end process fakesender_proc;

trig_proc: process -- make a trigger pulse 
begin
    wait for 2500ns;
    wait until rising_edge(clock);  
    trigger <= '1';
    wait until rising_edge(clock);
    trigger <= '0';
    wait;
end process trig_proc;

DUT: inspybuff
port map(
    clock => clock,
    din => din,
    trigger => trigger,
    AXI_IN => AXI_IN,
    AXI_OUT => AXI_OUT
);

-- now do the axi stuff...

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
    report "axipeek: read 0x" & to_hstring(AXI_OUT.RDATA);
    AXI_IN.RREADY <= '0';
end procedure axipeek;

begin

wait for 100ns;
AXI_IN.ARESETN <= '1'; -- release AXI reset
wait for 1us;
axipoke(addr => X"00000000", data => X"0000000C"); -- arm it, select channel 12
wait for 1us;
axipeek(addr => X"00000000"); -- poll status register
wait for 70us;
axipeek(addr => X"00000000"); -- poll status register
wait for 200ns;
axipeek(addr => X"00000001");
wait for 200ns;
axipeek(addr => X"00000001");
wait for 200ns;
axipeek(addr => X"00000001");
wait for 200ns;
axipeek(addr => X"00000001");
wait for 200ns;
axipeek(addr => X"00000001");
wait for 200ns;
axipeek(addr => X"00000001");
wait for 200ns;
axipeek(addr => X"00000001");
wait;
end process aximaster_proc;

end inspybuff_tb_arch;
