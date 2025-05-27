-- testbench for the single self triggered core module STC
-- jamieson olsen <jamieson@fnal.gov>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use STD.textio.all;
use ieee.std_logic_textio.all;

use work.daphne2_package.all;

entity st10_top_testbench is
end st10_top_testbench;

architecture st10_top_testbench_arch of st10_top_testbench is

component st10_top is
generic( link_id: std_logic_vector(5 downto 0)  := "000000" );
port(
    reset: in std_logic;

    threshold: std_logic_vector(13 downto 0);
    slot_id: std_logic_vector(3 downto 0);
    crate_id: std_logic_vector(9 downto 0);
    detector_id:   std_logic_vector(5 downto 0);
    version_id:  std_logic_vector(5 downto 0);

    aclk: in std_logic; -- AFE clock 62.500 MHz
    timestamp: in std_logic_vector(63 downto 0);
	afe_dat: in array_10x14_type;
    ch_id: in array_10x6_type; -- input channel IDs

    fclk: in std_logic; -- transmit clock to FELIX 120.237 MHz 
    dout: out std_logic_vector(31 downto 0);
    kout: out std_logic_vector(3 downto 0)
);
end component;

signal reset: std_logic := '1';
signal aclk: std_logic := '0';
signal timestamp: std_logic_vector(63 downto 0) := X"0000000000000000";

signal fclk: std_logic := '0';
signal afe_dat: array_10x14_type;

constant ch_id: array_10x6_type := ("011010", "011000", "010011", "010001", "010000", "001100", "001000", "000110", "000011", "000000");

begin

aclk <= not aclk after 8.000 ns; --  62.500 MHz
fclk <= not fclk after 4.158 ns; -- 120.237 MHz

reset <= '1', '0' after 96ns;

ts_proc: process 
begin 
    wait until falling_edge(aclk);
    timestamp <= std_logic_vector(unsigned(timestamp) + 1);
end process ts_proc;

pulse_proc: process 
begin
    afe_dat(0) <= "00001000000000";
    afe_dat(1) <= "00001000000000";
    afe_dat(2) <= "00001000000000";
    afe_dat(3) <= "00001000000000";
    afe_dat(4) <= "00001000000000";
    afe_dat(5) <= "00001000000000";
    afe_dat(6) <= "00001000000000";
    afe_dat(7) <= "00001000000000";
    afe_dat(8) <= "00001000000000";
    afe_dat(9) <= "00001000000000";

    wait for 1000ns;
    wait until falling_edge(aclk);
    afe_dat(3) <= "00000000000001";
    wait until falling_edge(aclk);
    afe_dat(3) <= "00000000000010";
    wait until falling_edge(aclk);
    afe_dat(3) <= "00000000000011";
    wait until falling_edge(aclk);
    afe_dat(3) <= "00000000000100";
    wait until falling_edge(aclk);
    afe_dat(3) <= "00001000000000";

    wait for 500ns;
    wait until falling_edge(aclk);
    afe_dat(7) <= "00000000000101";
    wait until falling_edge(aclk);
    afe_dat(7) <= "00000000000110";
    wait until falling_edge(aclk);
    afe_dat(7) <= "00000000000111";
    wait until falling_edge(aclk);
    afe_dat(7) <= "00000000001000";
    wait until falling_edge(aclk);
    afe_dat(7) <= "00001000000000";

    wait for 25us;
    wait until falling_edge(aclk);
    afe_dat(3) <= "00000000001001";
    wait until falling_edge(aclk);
    afe_dat(3) <= "00000000001010";
    wait until falling_edge(aclk);
    afe_dat(3) <= "00000000001011";
    wait until falling_edge(aclk);
    afe_dat(3) <= "00000000001100";
    wait until falling_edge(aclk);
    afe_dat(3) <= "00001000000000";

    wait;
end process pulse_proc;

DUT: st10_top
generic map ( link_id => "000001" )
port map(
    reset => reset,

    threshold => "00000000100000",
    slot_id => "0011",
    crate_id => "0000100100",
    detector_id => "100000",
    version_id => "001100",

    aclk => aclk,
    timestamp => timestamp,
	afe_dat => afe_dat,
    ch_id => ch_id,
    fclk => fclk
);

end st10_top_testbench_arch;
