-- testbench for a single output spy buffer with axi lite interface
-- jamieson olsen <jamieson@fnal.gov>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library xpm;
use xpm.vcomponents.all;

use work.daphne3_package.all;

entity outspybuff_tb is
end outspybuff_tb;

architecture outspybuff_tb_arch of outspybuff_tb is

component outspybuff
	port (
	    clock: in std_logic;
	    din: in std_logic_vector(63 downto 0);
	    valid: in std_logic;
	    last: in std_logic;
        AXI_IN: in AXILITE_INREC;  
        AXI_OUT: out AXILITE_OUTREC
  	);
end component;

constant clock_period: time := 16.0ns;  -- 62.5 MHz
signal clock: std_logic := '0';
signal din: std_logic_vector(63 downto 0) := (others=>'0');
signal valid, last: std_logic := '0';

signal AXI_IN: AXILITE_INREC := (ACLK=>'0', ARESETN=>'0', AWADDR=>X"00000000", 
    AWPROT=>"000", AWVALID=>'0', WDATA=>X"00000000", WSTRB=>"0000", WVALID=>'0', 
    BREADY=>'0', ARADDR=>X"00000000", ARPROT=>"000", ARVALID=>'0', RREADY=>'0');
signal AXI_OUT: AXILITE_OUTREC;

constant ACLK_period: time := 10.0ns;  -- 100 MHz

begin

clock <= not clock after clock_period/2;

fakesender_proc: process -- some dumb repeating thing
begin
    wait for 500ns;

    for i in 0 to 255 loop
        wait until rising_edge(clock);
        din <= X"DEADBEEF" & std_logic_vector( to_unsigned(i+437,32) );
        valid <= '1'; 
        if (i=255) then
            last <= '1';
        else
            last <= '0';
        end if;       
    end loop;

    wait until rising_edge(clock);
    last <= '0';
    valid <= '0';
    din <= (others=>'0');

end process fakesender_proc;

DUT: outspybuff
port map(
    clock => clock,
    din => din,
    valid => valid,
    last => last,
    AXI_IN => AXI_IN,
    AXI_OUT => AXI_OUT );

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
axipoke(addr => X"00000000", data => X"DEADBEEF"); -- arm it
wait for 1us;
axipeek(addr => X"00000000"); -- poll status register
wait for 22us;
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

end outspybuff_tb_arch;
