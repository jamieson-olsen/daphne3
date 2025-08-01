-- testbench for the 4 channel DAPHNE_MEZZ streaming core design
-- jamieson olsen <jamieson@fnal.gov>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.daphne3_package.all;

entity stream4_testbench is
end stream4_testbench;

architecture stream4_testbench_arch of stream4_testbench is

component stream4 is
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

signal areset: std_logic := '1';

signal clock: std_logic := '0';
signal ts: std_logic_vector(63 downto 0) := X"0000000000000000";
signal afe_data: array_4x14_type := ("01100000000000", "01000000000000", "00100000000000", "00000000000000");

begin

clock  <= not clock after 8.000 ns; --  62.500 MHz
areset <= '1', '0' after 96ns;

process
begin 
    wait until rising_edge(clock);
    ts <= std_logic_vector(unsigned(ts) + 1);
    datloop: for i in 3 downto 0 loop 
        afe_data(i) <= std_logic_vector( unsigned(afe_data(i)) + 1 );
    end loop datloop;
end process;

DUT: stream4
generic map( BLOCKS_PER_RECORD => 128 )
port map(
    areset => areset,
    clock => clock,
    ts   => ts,
	din  => afe_data
);

end stream4_testbench_arch;
