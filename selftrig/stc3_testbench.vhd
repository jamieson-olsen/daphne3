-- testbench for the single self triggered core module STC3 (DAPHNE3 version)
-- jamieson olsen <jamieson@fnal.gov>
-- testing

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;
use ieee.std_logic_textio.all;

entity stc3_testbench is
end stc3_testbench;

architecture stc3_testbench_arch of stc3_testbench is

component stc3 is
generic( baseline_runlength: integer := 256 ); -- options 32, 64, 128, or 256
port(
    ch_id: std_logic_vector(7 downto 0);
    version: std_logic_vector(3 downto 0);
    threshold: std_logic_vector(9 downto 0); -- counts relative to calculated avg baseline
    clock: in std_logic; -- master clock 62.5MHz
    reset: in std_logic;   
    forcetrig: in std_logic;
    timestamp: in std_logic_vector(63 downto 0);
	din: in std_logic_vector(13 downto 0); -- aligned AFE data
    rd_en: in std_logic; -- read enable
    dout:  out std_logic_vector(71 downto 0);
    ready: out std_logic
);
end component;

signal reset: std_logic := '1';
signal clock, forcetrig: std_logic := '0';
signal ts: std_logic_vector(63 downto 0) := X"0000000000000000";
signal din: std_logic_vector(13 downto 0) := "00000000000000";

begin

clock <= not clock after 8.000 ns; --  62.500 MHz
reset <= '1', '0' after 96ns;

--transactor: process(clock)
--    file test_vector: text open read_mode is "$dsn/src/selftrig/stc3_testbench.txt";
--    variable row: line;
--    variable v_ts: std_logic_vector(31 downto 0); -- hex string 8 char
--    variable v_din: std_logic_vector(15 downto 0); -- hex string 4 char
--begin 
--    if rising_edge(clock) then
--   
--        if(not endfile(test_vector)) then
--            readline(test_vector,row);
--        end if;
--
--        hread(row, v_ts);
--        hread(row, v_din);
--
--        ts <= X"00000000" & v_ts;
--        din <= v_din(13 downto 0);
--
--    end if;    
--end process transactor;

--forcetrigproc: process
--begin
--    wait for 30us;
--    wait until rising_edge(clock);
--    forcetrig <= '1';
--    wait until rising_edge(clock);
--    forcetrig <= '0';
--    wait;
--end process forcetrigproc;





-- simple ramp mode from AFE

ramp_maker: process(clock)
begin 
    if rising_edge(clock) then
        ts <= std_logic_vector( unsigned(ts) + 1 );
        din <= std_logic_vector( unsigned(din) + 1 );
    end if;    
end process ramp_maker;

forcetrig <= '0';





DUT: stc3
generic map( baseline_runlength => 256 ) 
port map(
    ch_id => "00100001",
    version => "1010",
    threshold => "0100000000", -- theshold is 256 counts above baseline
    clock => clock,
    reset => reset,
    forcetrig => '0',
    timestamp => ts,
	din => din,
    rd_en => '0'
);

end stc3_testbench_arch;