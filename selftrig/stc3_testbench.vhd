-- testbench for the single self triggered core module STC3 (DAPHNE3 version)
-- jamieson olsen <jamieson@fnal.gov>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;
use ieee.std_logic_textio.all;

entity stc3_testbench is
end stc3_testbench;

architecture stc3_testbench_arch of stc3_testbench is

component stc3 is
generic( 
    link_id: std_logic_vector(5 downto 0) := "000000"; 
    ch_id: std_logic_vector(5 downto 0) := "000000";
    slot_id: std_logic_vector(3 downto 0) := "0010";
    crate_id: std_logic_vector(9 downto 0) := "0000000011";
    detector_id: std_logic_vector(5 downto 0) := "000010";
    version_id: std_logic_vector(5 downto 0) := "000011";
    runlength: integer := 256; -- baseline runlength must one one of 32, 64, 128, 256
    threshold: std_logic_vector(13 downto 0):= "00001111101000" -- trig threshold relative to calculated baseline
);
port(
    clock: in std_logic; -- master clock 62.5MHz
    reset: in std_logic;
    
    enable: in std_logic; 
    forcetrig: in std_logic;
    timestamp: in std_logic_vector(63 downto 0);
	din: in std_logic_vector(13 downto 0); -- aligned AFE data

    FIFO_rd_en: in std_logic; -- read enable
    FIFO_dout:  out std_logic_vector(71 downto 0);
    FIFO_empty: out std_logic
);
end component;

signal reset: std_logic := '1';
signal clock, forcetrig: std_logic := '0';
signal ts: std_logic_vector(63 downto 0) := X"0000000000000000";
signal din: std_logic_vector(13 downto 0) := "00000001000000";

begin

clock <= not clock after 8.000 ns; --  62.500 MHz
reset <= '1', '0' after 96ns;

transactor: process(clock)
    file test_vector: text open read_mode is "$dsn/src/selftrig/stc3_testbench.txt";
    variable row: line;
    variable v_ts: std_logic_vector(31 downto 0); -- hex string 8 char
    variable v_din: std_logic_vector(15 downto 0); -- hex string 4 char
begin 
    if rising_edge(clock) then
   
        if(not endfile(test_vector)) then
            readline(test_vector,row);
        end if;

        hread(row, v_ts);
        hread(row, v_din);

        ts <= X"00000000" & v_ts;
        din <= v_din(13 downto 0);

    end if;    
end process transactor;

forcetrigproc: process
begin
    wait for 30us;
    wait until rising_edge(clock);
    forcetrig <= '1';
    wait until rising_edge(clock);
    forcetrig <= '0';
    wait;
end process forcetrigproc;

DUT: stc3
generic map( runlength => 64 ) 
port map(
    clock => clock,
    reset => reset,
    enable => '1',
    forcetrig => '0',
    timestamp => ts,
	din => din,
    FIFO_rd_en => '0'
);

end stc3_testbench_arch;