-- dual_st20_top.vhd
-- DAPHNE core logic, top level, self triggered mode sender
-- TWO 20:1 self triggered senders
-- Jamieson Olsen <jamieson@fnal.gov>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.daphne3_package.all;

entity dual_st20_top is
generic( baseline_runlength: integer := 256 ); -- options 32, 64, 128, or 256
port(
    clock: in std_logic; -- main clock 62.5 MHz
    reset: in std_logic;
    thresholds: in array_40x10_type; 
    version: in std_logic_vector(3 downto 0);
    timestamp: in std_logic_vector(63 downto 0);
    forcetrig: in std_logic;
	din: in array_40x14_type; -- 40 AFE channels feed into this module
    dout: out array_2x64_type;
    valid: out std_logic_vector(1 downto 0);
    last:  out std_logic_vector(1 downto 0)
);
end dual_st20_top;

architecture dual_st20_top_arch of dual_st20_top is

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

-- break up the 40 array into upper/lower 20 arrays

genbus: for i in 19 downto 0 generate
    din_lower(i) <= din(i);
    din_upper(i) <= din(i+20);
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

end dual_st20_top_arch;
