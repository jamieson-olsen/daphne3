-- trig.vhd
-- an EXAMPLE of a very simple trigger algorithm for the DAPHNE self triggered mode
--
-- baseline, threshold, din are UNSIGNED 
--
-- In this EXAMPLE the trigger algorithm is VERY simple and requires only a few clock cycles
-- however, this module ADDS extra pipeline stages so that the overall latency 
-- is 256 clocks. this is done to allow for more advanced triggers. If a more advanced trigger
-- is used in place of this module, the overall latency MUST match this module, since the 
-- rest of the self-triggered sender logic depends on it. This module assumes that the pulse is 
-- negative going. So the trigger threshold specifies the number of counts BELOW the calculated
-- baseline. the trigger condition is 1 sample above the threshold followed by two samples 
-- below the threshold.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

entity trig is
port(
    clock: in std_logic;
    din: in std_logic_vector(13 downto 0); -- raw AFE data aligned to clock
    ts: in std_logic_vector(63 downto 0); -- timestamp
    threshold: in std_logic_vector(9 downto 0); -- counts below baseline
    baseline: in std_logic_vector(13 downto 0); -- average signal level computed over past N samples
    trig_sample_dat: out std_logic_vector(13 downto 0); -- the sample that caused the trigger
    trig_sample_ts:  out std_logic_vector(63 downto 0); -- the timestamp of the sample that caused the trigger
    trig: out std_logic -- trigger pulse (after latency delay)
);
end trig;

architecture trig_arch of trig is

    signal din0, din1, din2: std_logic_vector(13 downto 0) := "00000000000000";
    signal trig_thresh, trig_sample_reg: std_logic_vector(13 downto 0) := (others=>'0');
    signal ts_reg, trig_ts_reg: std_logic_vector(63 downto 0) := (others=>'0');
    signal triggered_i: std_logic := '0';
    signal triggered_dly32_i, triggered_dly64_i, triggered_dly96_i, triggered_dly128_i: std_logic := '0';
    signal triggered_dly160_i, triggered_dly192_i, triggered_dly224_i: std_logic := '0';

begin

    trig_pipeline_proc: process(clock)
    begin
        if rising_edge(clock) then
            din0 <= din;  -- latest sample
            din1 <= din0; -- previous sample
            din2 <= din1; -- previous previous sample
            ts_reg <= ts;
        end if;
    end process trig_pipeline_proc;

    -- user-specified threshold is RELATIVE to the calculated average baseline level
    -- NOTE that the trigger pulse is NEGATIVE going! We want to SUBTRACT the relative 
    -- threshold from the calculated average baseline level.

    trig_thresh <= std_logic_vector( unsigned(baseline) - unsigned(threshold) );

    -- our super basic trigger condition is this: one sample ABOVE trig_thresh followed by two samples
    -- BELOW trig_thresh.

    triggered_i <= '1' when ( din2>trig_thresh and din1<trig_thresh and din0<trig_thresh ) else '0';

    -- add in some fake/synthetic latency, adjust it so total trigger latency is 256 clocks

    srlc32e_0_inst : srlc32e
    port map(
        clk => clock,
        ce  => '1',
        a   => "11111",
        d   => triggered_i,
        q   => open,
        q31 => triggered_dly32_i
    );

    srlc32e_1_inst : srlc32e
    port map(
        clk => clock,
        ce  => '1',
        a   => "11111",
        d   => triggered_dly32_i,
        q   => open,
        q31 => triggered_dly64_i
    );

    srlc32e_2_inst : srlc32e
    port map(
        clk => clock,
        ce  => '1',
        a   => "11111",
        d   => triggered_dly64_i,
        q   => open,
        q31 => triggered_dly96_i
    );

    srlc32e_3_inst : srlc32e
    port map(
        clk => clock,
        ce  => '1',
        a   => "11111",
        d   => triggered_dly96_i,
        q   => triggered_dly128_i,
        q31 => open
    );

    srlc32e_4_inst : srlc32e
    port map(
        clk => clock,
        ce  => '1',
        a   => "11111",
        d   => triggered_dly128_i,
        q   => triggered_dly160_i,
        q31 => open
    );

    srlc32e_5_inst : srlc32e
    port map(
        clk => clock,
        ce  => '1',
        a   => "11111",
        d   => triggered_dly160_i,
        q   => triggered_dly192_i,
        q31 => open
    );

    srlc32e_6_inst : srlc32e
    port map(
        clk => clock,
        ce  => '1',
        a   => "11111",
        d   => triggered_dly192_i,
        q   => triggered_dly224_i,
        q31 => open
    );

    srlc32e_7_inst : srlc32e
    port map(
        clk => clock,
        ce  => '1',
        a   => "11101", -- may need to fine tune this delay here
        d   => triggered_dly224_i,
        q   => trig,
        q31 => open
    );

    -- capture the sample and timestamp that caused the trigger 

    samplecap_proc: process(clock)
    begin
        if rising_edge(clock) then
            if (triggered_i='1') then
                trig_sample_reg <= din0;
                trig_ts_reg     <= ts_reg;
            end if;
        end if;    
    end process samplecap_proc;

    trig_sample_dat <= trig_sample_reg;
    trig_sample_ts  <= trig_ts_reg;

end trig_arch;
