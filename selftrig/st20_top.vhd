-- st20_top.vhd
-- DAPHNE core logic, top level, self triggered mode sender
-- 20 AFE channels -> one output link
-- 
-- Jamieson Olsen <jamieson@fnal.gov>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

library work;
use work.daphne3_package.all;

entity st20_top is
generic(
    baseline_runlength: integer := 256; -- options 32, 64, 128, or 256
    start_channel_number: integer := 0 -- 0 or 20
); 
port(
    thresholds: in array_20x10_type; -- counts relative to the calculated baseline
    version: in std_logic_vector(3 downto 0);

    clock: in std_logic; -- main clock 62.5 MHz
    reset: in std_logic;
    timestamp: in std_logic_vector(63 downto 0);
    forcetrig: in std_logic;
	din: in array_20x14_type; -- 20 AFE channels feed into this module

    record_count: out array_20x64_type; -- diagnostic counters
    full_count: out array_20x64_type;
    busy_count: out array_20x64_type;

    dout: out std_logic_vector(63 downto 0); -- output to single channel 10G sender
    valid: out std_logic;
    last:  out std_logic
);
end st20_top;

architecture st20_top_arch of st20_top is
 
    type state_type is (rst, scan, dump, pause);
    signal state: state_type;
    signal sel: integer range 0 to 19;
    signal fifo_rd_en: std_logic_vector(19 downto 0) := (others=>'0');
    signal ready: std_logic_vector(19 downto 0) := (others=>'0');
    type array_20x72_type is array(19 downto 0) of std_logic_vector(71 downto 0);
    signal fifo_dout: array_20x72_type;
    signal fifo_dout_mux: std_logic_vector(71 downto 0);

    component stc3 is
    generic( baseline_runlength: integer := 256 );
    port(
        ch_id: std_logic_vector(7 downto 0);
        version: std_logic_vector(3 downto 0);    
        threshold: std_logic_vector(9 downto 0);

        clock: in std_logic;
        reset: in std_logic;
        forcetrig: in std_logic;
        timestamp: in std_logic_vector(63 downto 0);
    	din: in std_logic_vector(13 downto 0);

        record_count: out std_logic_vector(63 downto 0);
        full_count: out std_logic_vector(63 downto 0);
        busy_count: out std_logic_vector(63 downto 0);

        ready: out std_logic;
        rd_en: in std_logic;
        dout: out std_logic_vector(71 downto 0)
    );
    end component;

begin

    -- make 20 self-trigger-channel (STC) machines...

    gen_stc: for i in 19 downto 0 generate

            stc3_inst: stc3
            generic map ( baseline_runlength => baseline_runlength )
            port map(   
                ch_id => std_logic_vector( to_unsigned(i+start_channel_number, 8) ),
                version => version,
                threshold => thresholds(i),

                clock => clock,
                reset => reset,
                forcetrig => forcetrig,
                timestamp => timestamp,
            	din => din(i),

                record_count => record_count(i),
                full_count => full_count(i),
                busy_count => busy_count(i),

                ready => ready(i),
                rd_en => fifo_rd_en(i),
                dout => fifo_dout(i)
              );

    end generate gen_stc;

    -- generate the read enables for the 20 channel FIFOs

    gen_rden: for i in 19 downto 0 generate
        fifo_rd_en(i) <= '1' when (sel=i and state=dump) else '0';
    end generate gen_rden;

    -- FSM scans the STC machines looking for a machine with a NON-EMPTY output FIFO. When it finds
    -- one it dumps one complete output record, then goes idle for one clock, then moves on to the next channel 
    -- and resumes scanning (round robin).

    fsm_proc: process(clock)
    begin
        if rising_edge(clock) then
            if (reset='1') then
                state <= rst;
            else
                case(state) is

                    when rst =>
                        sel <= 0;
                        state <= scan;

                    when scan => 
                        if ( ready(sel)='1' ) then -- current channel gots something to send, lets dump a whole record
                            state <= dump;
                        else
                            if (sel = 19) then -- otherwise, move on to next channel (round robin)
                                sel <= 0;
                            else
                                sel <= sel + 1;
                            end if;
                            state <= scan;
                        end if;

                    when dump => -- dump one entire output record to the output
                        if ( fifo_dout_mux(71 downto 64)=X"ED" ) then -- this the marker for the LAST word of record
                            state <= pause;
                        else
                            state <= dump;
                        end if;

                    when pause => -- pause for 1 clock, increment ch_select & resume scanning...
                        if (sel = 19) then
                            sel <= 0;
                        else
                            sel <= sel + 1;
                        end if;
                        state <= scan;

                    when others => 
                        state <= rst;
                end case;
            end if;
        end if;
    end process fsm_proc;

    -- big output data mux 20:1

    outmux_proc: process(sel,fifo_dout)
    begin
        fifo_dout_mux <= fifo_dout(sel);
    end process outmux_proc;
     
    -- register the outputs

    outreg_proc: process(clock)
    begin
        if rising_edge(clock) then

            if ( state=dump ) then
                dout <= fifo_dout_mux(63 downto 0); -- note strip off marker byte
                valid <= '1';
            else
                dout <= (others=>'0'); -- do a better job masking off the data bus while switching between STC3 modules
                valid <= '0';
            end if;

        end if;
    end process outreg_proc;

    last <= '1' when (state=pause) else '0';

end st20_top_arch;
