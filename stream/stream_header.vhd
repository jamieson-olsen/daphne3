-- stream_header.vhd
--
-- compute average baseline level over RUNLENGTH consecutive samples
-- note that after reset baseline will default to mid scale (0x2000) until
-- RUNLENGTH samples have been analyzed, then it will take on a real value.
--
-- if a sample is THRESHOLD counts ABOVE the calculated baseline value, report the
-- baseline value, sample value, and offset since from the last SOF
-- if multiple triggers are observed, report ONLY the FIRST trigger since SOF

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity stream_header is
generic( RUNLENGTH: integer := 32  -- Window size for baseline calculation: 32, 64, 128, or 256
); 
port(
    clock: in  std_logic;
    reset: in  std_logic;
    threshold: in std_logic_vector(13 downto 0);
    sof:   in  std_logic;  -- start of frame marker, assert JUST AFTER stream4 makes headers
    din:   in  std_logic_vector(13 downto 0);
    hdrdata: out std_logic_vector(47 downto 0)
);
end stream_header;

architecture stream_header_arch of stream_header is

    signal baseline_reg: std_logic_vector(13 downto 0) := "10000000000000"; -- mid-scale
    signal sum_reg: std_logic_vector(21 downto 0) := (others=>'0');
    signal runcount: integer range 0 to (RUNLENGTH-1) := 0;
    signal trig_baseline_reg: std_logic_vector(13 downto 0);
    signal trig_sample_reg: std_logic_vector(13 downto 0);
    signal trig, trig_reg: std_logic;
    signal offset_reg, trig_offset_reg: std_logic_vector(15 downto 0);

begin

    -- On each clock cycle add din to sum_reg. after N cycles, 
    -- copy sum_reg/N into baseline_reg and clear sum_reg.
    -- runs continuously and does not care about SOF marker at all

    baseline_proc: process(clock)
    begin
        if rising_edge(clock) then
            if (reset='1') then
                runcount <= 0;
                sum_reg <= (others=>'0');
                baseline_reg <= "10000000000000";
            else
                case (RUNLENGTH) is
                    when 32 =>
                        if (runcount=31) then
                            sum_reg <= "00000000" & din;
                            runcount <= 0;
                            baseline_reg <= sum_reg(18 downto 5); -- sum/32
                        else
                            sum_reg <= std_logic_vector( unsigned(sum_reg) + unsigned(din) );
                            runcount <= runcount + 1;
                        end if; 
                    when 64 => 
                        if (runcount=63) then
                            sum_reg <= "00000000" & din;
                            runcount <= 0;
                            baseline_reg <= sum_reg(19 downto 6); -- sum/64
                        else
                            sum_reg <= std_logic_vector( unsigned(sum_reg) + unsigned(din) );
                            runcount <= runcount + 1;
                        end if; 
                    when 128 => 
                        if (runcount=127) then
                            sum_reg <= "00000000" & din;
                            runcount <= 0;
                            baseline_reg <= sum_reg(20 downto 7); -- sum/128
                        else
                            sum_reg <= std_logic_vector( unsigned(sum_reg) + unsigned(din) );
                            runcount <= runcount + 1;
                        end if; 
                    when others => -- default is 256
                        if (runcount=255) then
                            sum_reg <= "00000000" & din;
                            runcount <= 0;
                            baseline_reg <= sum_reg(21 downto 8); -- sum/256
                        else
                            sum_reg <= std_logic_vector( unsigned(sum_reg) + unsigned(din) );
                            runcount <= runcount + 1;
                        end if;
                    end case;
            end if;
        end if;
    end process baseline_proc;

-- trigger occurs when input data > (baseline + threshold)

trig <= '1' when ( unsigned(din) > (unsigned(baseline_reg) + unsigned(threshold)) ) else '0';

-- capture the FIRST trigger after EOF

trig_proc: process(clock)
begin
    if rising_edge(clock) then
        if (reset='1' or sof='1') then
            trig_reg <= '0';
            offset_reg <= (others=>'0');
            trig_baseline_reg <= (others=>'0');
            trig_sample_reg <= (others=>'0');
            trig_offset_reg <= (others=>'0');
        else
            if (trig_reg='0' and trig='1') then  -- FIRST trigger observed, store it
                trig_baseline_reg <= baseline_reg;
                trig_sample_reg <= din;
                trig_offset_reg <= offset_reg;
                trig_reg <= '1'; -- ignore subsequent triggers
            else
                offset_reg <= std_logic_vector( unsigned(offset_reg) + 1 );
            end if;
        end if;
    end if;            
end process trig_proc;

-- 48 bit header output is:

hdrdata <= trig_offset_reg & "00" & trig_baseline_reg & "00" & trig_sample_reg;

end stream_header_arch;
