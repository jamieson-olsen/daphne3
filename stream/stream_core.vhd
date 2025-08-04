-- stream_core.vhd
--
-- DAPHNE_MEZZ streaming core top level
-- four streaming senders, each with 8 inputs
-- programmable mux selects which inputs are connected to which sender
-- data is constantly arriving at 62.5MHz
-- four channel "HERMES" 10G sender IP block
-- 
-- Jamieson Olsen <jamieson@fnal.gov>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.daphne3_package.all;

entity stream_core is
port(
    -- mostly static stuff...
    slot_id:     in std_logic_vector(3 downto 0); -- "0010"
    crate_id:    in std_logic_vector(9 downto 0); -- "0000000011"
    detector_id: in std_logic_vector(5 downto 0); -- "000010"
    version_id:  in std_logic_vector(5 downto 0); -- "000011"
    mux_ctrl:    in array_4x8x6_type; -- input channel mapping

    clock: in std_logic;  -- 62.5MHz master clock
    clk125: in std_logic; -- 125MHz (MUST be aligned to clock!)
    areset: in std_logic; -- async reset active high
    ts: in std_logic_vector(63 downto 0); -- sync to clock
    din: array_40x14_type -- afe data streams sync to clock
  );
end stream_core;

architecture stream_core_arch of stream_core is

    component stream8 -- single streaming sender with 8 inputs
    port(
        link_id: std_logic_vector(5 downto 0);
        slot_id: std_logic_vector(3 downto 0);
        crate_id: std_logic_vector(9 downto 0);
        detector_id: std_logic_vector(5 downto 0);
        version_id: std_logic_vector(5 downto 0);

        clock: in std_logic; -- 62.5MHz master clock
        areset: in std_logic; -- async reset active high
        ts: in std_logic_vector(63 downto 0);
        din: array_8x14_type;
    
        clk125: in std_logic; -- 125MHz phase aligned to clock
        dout:  out std_logic_vector(63 downto 0);
        valid: out std_logic;
        last: out std_logic
    );
    end component;

    signal sender_din: array_4x8x14_type;
    signal sender_dout: array_4x64_type;
    signal sender_valid, sender_last: std_logic_vector(3 downto 0);
    signal counter_reg: std_logic_vector(13 downto 0) := "00000000000000";
    signal rand_reg:    std_logic_vector(13 downto 0) := "00100111010101";

begin

-- make a few test counters for debugging
-- rand_reg is LFSR with taps selected for max run length

counter_proc: process(clock)
begin
    if rising_edge(clock) then
        counter_reg <= std_logic_vector( unsigned(counter_reg) + 1 );
        rand_reg  <= rand_reg(12 downto 0) & (rand_reg(13) xor rand_reg(12) xor rand_reg(10) xor rand_reg(7));
    end if;
end process counter_proc;

-- big old programmable input mux
-- each sender has 8 inputs; each input may be dynamically connected
-- to any input channel (or debug pattern, or zero).
-- this is controlled by mux_ctrl, a block of 32 6-bit registers
--
-- e.g. if mux_ctrl(2)(6)="000111" this means that 
-- sender 2 input 6 is connected to physical channel 7

gen_send: for s in 3 downto 0 generate
    gen_chan: for c in 7 downto 0 generate

    sender_din(s)(c) <= din( 0) when (mux_ctrl(s)(c)="000000") else -- reg values 0-39 select the input
                        din( 1) when (mux_ctrl(s)(c)="000001") else
                        din( 2) when (mux_ctrl(s)(c)="000010") else
                        din( 3) when (mux_ctrl(s)(c)="000011") else
                        din( 4) when (mux_ctrl(s)(c)="000100") else
                        din( 5) when (mux_ctrl(s)(c)="000101") else
                        din( 6) when (mux_ctrl(s)(c)="000110") else
                        din( 7) when (mux_ctrl(s)(c)="000111") else
                        din( 8) when (mux_ctrl(s)(c)="001000") else
                        din( 9) when (mux_ctrl(s)(c)="001001") else
                        din(10) when (mux_ctrl(s)(c)="001010") else
                        din(11) when (mux_ctrl(s)(c)="001011") else
                        din(12) when (mux_ctrl(s)(c)="001100") else
                        din(13) when (mux_ctrl(s)(c)="001101") else
                        din(14) when (mux_ctrl(s)(c)="001110") else
                        din(15) when (mux_ctrl(s)(c)="001111") else

                        din(16) when (mux_ctrl(s)(c)="010000") else
                        din(17) when (mux_ctrl(s)(c)="010001") else
                        din(18) when (mux_ctrl(s)(c)="010010") else
                        din(19) when (mux_ctrl(s)(c)="010011") else
                        din(20) when (mux_ctrl(s)(c)="010100") else
                        din(21) when (mux_ctrl(s)(c)="010101") else
                        din(22) when (mux_ctrl(s)(c)="010110") else
                        din(23) when (mux_ctrl(s)(c)="010111") else
                        din(24) when (mux_ctrl(s)(c)="011000") else
                        din(25) when (mux_ctrl(s)(c)="011001") else
                        din(26) when (mux_ctrl(s)(c)="011010") else
                        din(27) when (mux_ctrl(s)(c)="011011") else
                        din(28) when (mux_ctrl(s)(c)="011100") else
                        din(29) when (mux_ctrl(s)(c)="011101") else
                        din(30) when (mux_ctrl(s)(c)="011110") else
                        din(31) when (mux_ctrl(s)(c)="011111") else

                        din(32) when (mux_ctrl(s)(c)="100000") else
                        din(33) when (mux_ctrl(s)(c)="100001") else
                        din(34) when (mux_ctrl(s)(c)="100010") else
                        din(35) when (mux_ctrl(s)(c)="100011") else
                        din(36) when (mux_ctrl(s)(c)="100100") else
                        din(37) when (mux_ctrl(s)(c)="100101") else
                        din(38) when (mux_ctrl(s)(c)="100110") else
                        din(39) when (mux_ctrl(s)(c)="100111") else

                        "11111111111111" when (mux_ctrl(s)(c)="101000") else -- test mode 40: fixed pattern = all 1s
                        "00000011111111" when (mux_ctrl(s)(c)="101001") else -- test mode 41: fixed pattern = lower 8 bits set
                        "11111100000000" when (mux_ctrl(s)(c)="101010") else -- test mode 42: fixed pattern = upper 6 bits set
                        "11000000000011" when (mux_ctrl(s)(c)="101011") else -- test mode 43: fixed pattern = two MSb and two LSb set
                        counter_reg      when (mux_ctrl(s)(c)="101100") else -- test mode 44: incrementing counter
                        rand_reg         when (mux_ctrl(s)(c)="101101") else -- test mode 45: pseudorandom generator

                        (others=>'0'); -- all other values force the associated input to zero

    end generate gen_chan;
end generate gen_send;

-- instantiate 4 8-input streaming senders

gen_senders: for s in 3 downto 0 generate

    stream_sender_inst: stream8
    port map(

        link_id => std_logic_vector( to_unsigned(s,4) ), 
        slot_id => slot_id, 
        crate_id => crate_id,
        detector_id => detector_id,
        version_id => version_id,

        areset => areset,
        clock  => clock,
        ts     => ts,
        din    => sender_din(s),
    
        clk125 => clk125,
        dout   => sender_dout(s),
        valid  => sender_valid(s),
        last   => sender_last(s)
    );

end generate gen_senders;

-- 4 channel 10G Ethernet sender "Hermes"
-- Adam Barcock <adam.barcock@stfc.ac.uk>





end stream_core_arch;
