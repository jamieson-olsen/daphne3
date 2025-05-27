-- st40_top.vhd
-- DAPHNE core logic, top level, self triggered mode sender
-- all 40 AFE channels -> one output link to DAQ
-- 
-- Jamieson Olsen <jamieson@fnal.gov>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

entity st40_top is
generic( baseline_runlength: integer := 256 ); -- options 32, 64, 128, or 256
port(

    threshold: in std_logic_vector(9 downto 0); -- counts below calculated baseline
    slot_id: in std_logic_vector(3 downto 0);
    crate_id: in std_logic_vector(9 downto 0);
    detector_id: in std_logic_vector(5 downto 0);
    version_id: in std_logic_vector(5 downto 0);
    enable: in std_logic_vector(39 downto 0);

    clock: in std_logic; -- main clock 62.5 MHz
    reset: in std_logic;
    timestamp: in std_logic_vector(63 downto 0);
	afe_dat: in array_40x14_type; -- ALL AFE channels feed into this module

    dout: out std_logic_vector(63 downto 0); -- output to 10G sender
    dv: out std_logic;
    last: out std_logic
);
end st40_top;

architecture st40_top_arch of st40_top is
 
    type state_type is (rst, scan, dump, idle);
    signal state: state_type;

    signal sela: integer range 0 to 4;
    signal selc: integer range 0 to 7;
    signal fifo_ae: array_5x8_type;
    signal fifo_rden: array_5x8_type;
    signal fifo_ready: std_logic;
    signal fifo_do: array_5x8x32_type;
    signal fifo_ko: array_5x8x4_type;

    component stc3 is
    generic( baseline_runlength: integer := 256 ); -- options 32, 64, 128, or 256
    port(
        link_id: std_logic_vector(5 downto 0);
        ch_id: std_logic_vector(5 downto 0);
        slot_id: std_logic_vector(3 downto 0);
        crate_id: std_logic_vector(9 downto 0);
        detector_id: std_logic_vector(5 downto 0);
        version_id: std_logic_vector(5 downto 0);
        threshold: std_logic_vector(9 downto 0); -- trig threshold relative to calculated baseline

        clock: in std_logic; -- master clock 62.5MHz
        reset: in std_logic;
        enable: in std_logic;
        forcetrig: in std_logic; -- force a trigger
        timestamp: in std_logic_vector(63 downto 0);
    	din: in std_logic_vector(13 downto 0); -- aligned AFE data
        FIFO_rd_en: in std_logic; -- output FIFO read enable
        FIFO_dout: out std_logic_vector(71 downto 0); -- output FIFO data
        FIFO_empty: out std_logic -- output FIFO flag
    );
    end component;

begin

    -- make 40 self-trigger-channel (STC) machines

    gen_stc: for i in 39 downto 0 generate

            stc3_inst: stc3 
            port map(   
                threshold => threshold,
                slot_id => slot_id,
                crate_id => crate_id,
                ch_id => i,
                detector_id => detector_id,
                version_id => version_id,
                enable => enable(i),

                clock => clock,
                reset => reset,
                timestamp => timestamp,
            	din => afe_dat(i),
                forcetrig => forcetrig,

                fifo_rd_en => fifo_rd_en(i),
                fifo_dout => fifo_dout(i),
                fifo_empty => fifo_empty(i)
              );

    end generate gen_stc;

    -- fifo read enable and fifo flag selection



    -- sel_reg is a straight 6 bit register, but it is encoded with values 0-7, 10-17, 20-27, 30-37, 40-47
    -- there are gaps, so be careful when incrementing and looping...

    fifo_ready_proc: process(sela, selc, fifo_ae)
    begin
        fifo_ready <= '0'; -- default
        loop_a: for a in 4 downto 0 loop
            loop_c: for c in 7 downto 0 loop
                if (sela=a and selc=c and fifo_ae(a)(c)='1') then
                    fifo_ready <= '1';
                end if;
            end loop loop_c;
        end loop loop_a;
    end process fifo_ready_proc;

    gen_rden_a: for a in 4 downto 0 generate
        gen_rden_c: for c in 7 downto 0 generate
            fifo_rden(a)(c) <= '1' when (sela=a and selc=c and state=dump) else '0';
        end generate gen_rden_c;
    end generate gen_rden_a;

    -- FSM scans all STC machines in round robin manner, looking for a FIFO almost empty "fifo_ae" flag set. when it finds
    -- this, it reads one complete frame from that machine, then sends a few idles, then returns to scanning again.

    fsm_proc: process(fclk)
    begin
        if rising_edge(fclk) then
            if (reset='1') then
                state <= rst;
            else
                case(state) is

                    when rst =>
                        sela <= 0;
                        selc <= 0;
                        state <= scan;

                    when scan => 
                        if (fifo_ready='1') then
                            state <= dump;
                        else
                            if (selc=7) then
                                if (sela=4) then -- loop around when sel = 4 7
                                    sela <= 0;
                                    selc <= 0;
                                else
                                    sela <= sela + 1;
                                    selc <= 0;
                                end if;
                            else
                                selc <= selc + 1;
                            end if;
                            state <= scan;
                        end if;

                    when dump =>
                        if (k="0001" and d(7 downto 0)=X"DC") then -- this the EOF word, done reading from this STC
                            state <= idle;
                        else
                            state <= dump;
                        end if;

                    when idle => -- send one idle word and resume scanning...
                        if (selc = 7) then
                            if (sela = 4) then -- loop around when sel = 4 7
                                sela <= 0;
                                selc <= 0;
                            else
                                sela <= sela + 1;
                                selc <= 0;
                            end if;
                        else
                            selc <= selc + 1;
                        end if;
                        state <= scan;

                    when others => 
                        state <= rst;
                end case;
            end if;
        end if;
    end process fsm_proc;

    -- output muxes
     
    outmux_proc: process(fifo_do, fifo_ko, sela, selc, state)
    begin
        d <= X"000000BC"; -- default
        k <= "0001"; -- default
        loop_a: for a in 4 downto 0 loop
        loop_c: for c in 7 downto 0 loop
            if ( sela=a and selc=c and state=dump ) then
                d <= fifo_do(a)(c);
                k <= fifo_ko(a)(c);
            end if;
        end loop loop_c;
        end loop loop_a;
    end process outmux_proc;

    -- register the outputs

    outreg_proc: process(fclk)
    begin
        if rising_edge(fclk) then
            dout_reg <= d;
            kout_reg <= k;
        end if;
    end process outreg_proc;

    dout <= dout_reg;
    kout <= kout_reg;

end st40_top_arch;
