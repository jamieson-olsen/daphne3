-- selftrig_core.vhd
-- DAPHNE core logic, top level, self triggered mode sender
-- TWO 20:1 self triggered senders
-- Jamieson Olsen <jamieson@fnal.gov>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.daphne3_package.all;

entity selftrig_core is
generic( baseline_runlength: integer := 256 ); -- options 32, 64, 128, or 256
port(
    clock: in std_logic; -- 62.5 MHz
    reset: in std_logic;
    thresholds: in array_40x10_type; 
    version: in std_logic_vector(3 downto 0);
    timestamp: in std_logic_vector(63 downto 0);
    forcetrig: in std_logic;
	din: in array_5x9x16_type; 
    dout: out array_2x64_type;
    valid: out std_logic_vector(1 downto 0);
    last:  out std_logic_vector(1 downto 0)
);
end selftrig_core;

architecture selftrig_core_arch of selftrig_core is

component st20_top
generic(
    baseline_runlength: integer := 256; -- options 32, 64, 128, or 256
    start_channel_number: integer := 0 -- 0 or 20
); 
port(
    thresholds: in array_20x10_type;
    version: in std_logic_vector(3 downto 0);
    clock: in std_logic; -- main clock 62.5 MHz
    reset: in std_logic;
    timestamp: in std_logic_vector(63 downto 0);
    forcetrig: in std_logic;
	din: in array_20x14_type; -- 20 AFE channels feed into this module
    dout: out std_logic_vector(63 downto 0); -- output to single channel 10G sender
    valid: out std_logic;
    last: out std_logic
);
end component;

signal din_lower, din_upper: array_20x14_type;
signal thresholds_lower, thresholds_upper: array_20x10_type;

begin

-- break up the 5x9x16 array into upper/lower 20x14 arrays
-- note when truncating from 16->14 bits discard the two LSbs
-- do not take afe channel 8 as that is the frame marker

din_lower( 0) <= din(0)(0)(15 downto 2);
din_lower( 1) <= din(0)(1)(15 downto 2);
din_lower( 2) <= din(0)(2)(15 downto 2);
din_lower( 3) <= din(0)(3)(15 downto 2);
din_lower( 4) <= din(0)(4)(15 downto 2);
din_lower( 5) <= din(0)(5)(15 downto 2);
din_lower( 6) <= din(0)(6)(15 downto 2);
din_lower( 7) <= din(0)(7)(15 downto 2);
din_lower( 8) <= din(1)(0)(15 downto 2);
din_lower( 9) <= din(1)(1)(15 downto 2);
din_lower(10) <= din(1)(2)(15 downto 2);
din_lower(11) <= din(1)(3)(15 downto 2);
din_lower(12) <= din(1)(4)(15 downto 2);
din_lower(13) <= din(1)(5)(15 downto 2);
din_lower(14) <= din(1)(6)(15 downto 2);
din_lower(15) <= din(1)(7)(15 downto 2);
din_lower(16) <= din(2)(0)(15 downto 2);
din_lower(17) <= din(2)(1)(15 downto 2);
din_lower(18) <= din(2)(2)(15 downto 2);
din_lower(19) <= din(2)(3)(15 downto 2);

din_upper( 0) <= din(2)(4)(15 downto 2);
din_upper( 1) <= din(2)(5)(15 downto 2);
din_upper( 2) <= din(2)(6)(15 downto 2);
din_upper( 3) <= din(2)(7)(15 downto 2);
din_upper( 4) <= din(3)(0)(15 downto 2);
din_upper( 5) <= din(3)(1)(15 downto 2);
din_upper( 6) <= din(3)(2)(15 downto 2);
din_upper( 7) <= din(3)(3)(15 downto 2);
din_upper( 8) <= din(3)(4)(15 downto 2);
din_upper( 9) <= din(3)(5)(15 downto 2);
din_upper(10) <= din(3)(6)(15 downto 2);
din_upper(11) <= din(3)(7)(15 downto 2);
din_upper(12) <= din(4)(0)(15 downto 2);
din_upper(13) <= din(4)(1)(15 downto 2);
din_upper(14) <= din(4)(2)(15 downto 2);
din_upper(15) <= din(4)(3)(15 downto 2);
din_upper(16) <= din(4)(4)(15 downto 2);
din_upper(17) <= din(4)(5)(15 downto 2);
din_upper(18) <= din(4)(6)(15 downto 2);
din_upper(19) <= din(4)(7)(15 downto 2);

genbus: for i in 19 downto 0 generate
    thresholds_lower(i) <= thresholds(i);
    thresholds_upper(i) <= thresholds(i+20);   
end generate genbus;

-- lower 20 channel sender

st20_lower_inst: st20_top
generic map( baseline_runlength => baseline_runlength, start_channel_number => 0 )
port map(
    thresholds => thresholds_lower,
    version => version,
    clock => clock,
    reset => reset,
    timestamp => timestamp,
    forcetrig => forcetrig,
	din => din_lower,
    dout => dout(0),
    valid => valid(0),
    last => last(0)
);

-- upper 20 channel sender

st20_upper_inst: st20_top
generic map( baseline_runlength => baseline_runlength, start_channel_number => 20 ) 
port map(
    thresholds => thresholds_upper,
    version => version,
    clock => clock,
    reset => reset,
    timestamp => timestamp,
    forcetrig => forcetrig,
	din => din_upper,
    dout => dout(1),
    valid => valid(1),
    last => last(1)
);

end selftrig_core_arch;
