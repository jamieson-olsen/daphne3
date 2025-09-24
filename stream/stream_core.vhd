-- stream_core.vhd
-- DAPHNE_MEZZ streaming core top level
-- EIGHT streaming senders, each with 4 inputs
-- data is constantly arriving at 62.5MHz
-- Jamieson Olsen <jamieson@fnal.gov>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.daphne3_package.all;

entity stream_core is
generic( BLOCKS_PER_RECORD: integer := 35 ); 
port(
    clock: in std_logic;  -- 62.5MHz master clock
    reset: in std_logic; -- async reset active high
    version: in std_logic_vector(3 downto 0);
    ts: in std_logic_vector(63 downto 0); -- sync to clock
    din: in array_8x4x14_type;
    channel_id: in array_8x4x8_type;
    dout: out array_8x64_type;
    valid: out std_logic_vector(7 downto 0);
    last: out std_logic_vector(7 downto 0)
  );
end stream_core;

architecture stream_core_arch of stream_core is

component stream4
generic( BLOCKS_PER_RECORD: integer := 64 ); 
port(
    clock: in std_logic;
    reset: in std_logic;
    version: in std_logic_vector(3 downto 0);
    channel_id: in array_4x8_type; 
    ts: in std_logic_vector(63 downto 0);
    din: array_4x14_type;
    dout:  out std_logic_vector(63 downto 0);
    valid: out std_logic;
    last: out std_logic
  );
end component;

begin

gen_senders: for i in 0 to 7 generate

    stream4_inst: stream4
    generic map( BLOCKS_PER_RECORD => BLOCKS_PER_RECORD )
    port map(
        clock => clock,
        reset => reset,
        version => version,
        channel_id => channel_id(i),
        ts => ts,
        din => din(i),
        dout => dout(i),
        valid => valid(i),
        last => last(i)
      );

end generate gen_senders;

end stream_core_arch;
