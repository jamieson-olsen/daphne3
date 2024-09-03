-- testbench for the single self triggered core module STC3 (DAPHNE3 version)
-- jamieson olsen <jamieson@fnal.gov>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use STD.textio.all;
use ieee.std_logic_textio.all;

library unisim;
use unisim.vcomponents.all;

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
    runlength: integer := 256 -- baseline runlength must one one of 32, 64, 128, 256
);
port(
    clock: in std_logic; -- master clock 62.5MHz
    reset: in std_logic;
    threshold: std_logic_vector(13 downto 0); -- trig threshold relative to calculated baseline
    enable: in std_logic; 
    timestamp: in std_logic_vector(63 downto 0);
	din: in std_logic_vector(13 downto 0); -- aligned AFE data
    dout: out std_logic_vector(63 downto 0);
    valid: out std_logic;
    last: out std_logic
);
end component;

signal reset: std_logic := '1';
signal clock: std_logic := '0';
signal timestamp: std_logic_vector(63 downto 0) := X"0000000000000000";
signal din: std_logic_vector(13 downto 0) := "00000001000000";

begin

clock <= not clock after 8.000 ns; --  62.500 MHz
reset <= '1', '0' after 96ns;

ts_proc: process 
begin 
    wait until rising_edge(clock);
    timestamp <= std_logic_vector(unsigned(timestamp) + 1);
end process ts_proc;

waveform_proc: process
begin 

    -- establish baseline level mid scale 

    for i in 1 to 1000 loop
        wait until rising_edge(clock);
        din <= std_logic_vector( to_unsigned(8000+i,14) );
    end loop;

    -- sharp falling edge!

    wait until rising_edge(clock);
    din <= std_logic_vector( to_unsigned(5000,14) );
    wait until rising_edge(clock);
    din <= std_logic_vector( to_unsigned(3000,14) );
    wait until rising_edge(clock);
    din <= std_logic_vector( to_unsigned(2000,14) );
	
	-- now a slow rise back up to baseline....
	
    for i in 1 to 2000 loop
        wait until rising_edge(clock);
        din <= std_logic_vector( to_unsigned(2000+i,14) );
    end loop;

    wait;

end process waveform_proc;

DUT: stc3
generic map( runlength => 64 )
port map(
    clock => clock,
    reset => reset,
    enable => '1',
    threshold => "00000100000000",
    timestamp => timestamp,
	din => din
);

end stc3_testbench_arch;