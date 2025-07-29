-- testbench for the 8 channel DAPHNE_MEZZ streaming core design
-- jamieson olsen <jamieson@fnal.gov>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.daphne3_package.all;

entity stream8_testbench is
end stream8_testbench;

architecture stream8_testbench_arch of stream8_testbench is

component stream8 is
port(

    link_id: std_logic_vector(5 downto 0);
    slot_id: std_logic_vector(3 downto 0);
    crate_id: std_logic_vector(9 downto 0);
    detector_id: std_logic_vector(5 downto 0);
    version_id: std_logic_vector(5 downto 0);

    clock: in std_logic; -- 62.5MHz
    areset: in std_logic;
    ts: in std_logic_vector(63 downto 0);
    din: array_8x14_type;

    clk125: in std_logic; 
    dout:  out std_logic_vector(63 downto 0);
    valid: out std_logic;
    last: out std_logic
  );
end component;

signal areset: std_logic := '1';

signal clock, clk125: std_logic := '0';
signal ts: std_logic_vector(63 downto 0) := X"0000000000000000";
signal afe_data: array_8x14_type := ("11100000000000", "11000000000000", "10100000000000", "10000000000000", "01100000000000", "01000000000000", "00100000000000", "00000000000000");

begin

clock  <= not clock after 8.000 ns; --  62.500 MHz
clk125 <= not clk125 after 4.000 ns; -- 125.000 MHz

areset <= '1', '0' after 96ns;

process
begin 
    wait until rising_edge(clock);
    ts <= std_logic_vector(unsigned(ts) + 1);
    datloop: for i in 7 downto 0 loop 
        afe_data(i) <= std_logic_vector( unsigned(afe_data(i)) + 1 );
    end loop datloop;
end process;

DUT: stream8
port map(

    link_id => "000000",
    slot_id => "0010",
    crate_id => "0000000011",
    detector_id => "000010",
    version_id => "000011",

    areset => areset,
    clock => clock,
    ts => ts,
	din => afe_data,
    clk125 => clk125
);

end stream8_testbench_arch;
