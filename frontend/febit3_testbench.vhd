-- testbench for febit3
-- jamieson olsen <jamieson@fnal.gov>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

entity febit3_testbench is
end febit3_testbench;

architecture febit3_testbench_arch of febit3_testbench is

component AFE5808 -- simple model of one AFE chip
port(
    clkadc_p, clkadc_n: in std_logic; -- assumes 62.5MHz, period 16.0ns    
    afe_p: out std_logic_vector(8 downto 0); -- FCLK is bit 8
    afe_n: out std_logic_vector(8 downto 0)
  );
end component;

component febit3 is
port(
    din_p, din_n: in std_logic;  -- LVDS data input from AFE chip
    clk:          in std_logic;  -- fast bit clock 500MHz
    clkdiv:       in std_logic;  -- byte clock 125MHz
    clock:        in std_logic;  -- word/master clock 62.5MHz
    reset:        in std_logic;
    load:         in std_logic;                     
    cntvalue:     in std_logic_vector(8 downto 0);
    en_vtc:       in std_logic;  -- IDELAY temperature/voltage compensation (async)
    bitslip:      in std_logic_vector(3 downto 0);
    dout:         out std_logic_vector(15 downto 0)
  );
end component;

constant clock_period:    time := 16.0ns;  -- 62.5 MHz
constant clkdiv_period:   time := 8.0ns;   -- 125 MHz
constant clk_period:      time := 2.0ns;   -- 500 MHz

signal reset: std_logic := '1';
signal clock, clkdiv, clk: std_logic := '1';

signal afe_p, afe_n: std_logic_vector(8 downto 0);
signal clkadc_p, clkadc_n: std_logic;

signal cntvalue: std_logic_vector(8 downto 0) := "000000000";
signal load: std_logic := '0';

begin

reset <= '1', '0' after 96ns;

clock  <= not clock after clock_period/2;
clkdiv <= not clkdiv after clkdiv_period/2;
clk    <= not clk after clk_period/2;

obufds_inst: OBUFDS
generic map ( IOSTANDARD => "DEFAULT", SLEW => "FAST" )
port map ( I => clock, O => clkadc_p, OB => clkadc_n );

afe_inst: AFE5808
port map(
    clkadc_p => clkadc_p,
    clkadc_n => clkadc_n,
    afe_p => afe_p, 
    afe_n => afe_n
);

febit3_inst: febit3
port map(
    din_p => afe_p(8), -- 8=fclk 7=countup
    din_n => afe_n(8),
    clk => clk,
    clkdiv => clkdiv,
    clock => clock,
    reset => reset,
    load => load,
    cntvalue => cntvalue,
    en_vtc => '0',
    bitslip => "1000"
  );

-- sweep delay value to find bit edges

bitsweep: process
begin

    wait for 1us;

    for d in 0 to 511 loop -- do the timing scan

        wait until falling_edge(clkdiv);
        cntvalue <= std_logic_vector( to_unsigned(d,9) );

        wait until falling_edge(clkdiv);    
        load <= '1';

        wait until falling_edge(clkdiv);
        load <= '0';

        wait for 500ns;

    end loop;

    wait for 10us;

    wait until falling_edge(clkdiv);
    cntvalue <= std_logic_vector( to_unsigned(112,9) ); -- pick the sweet spot 
    wait until falling_edge(clkdiv);    
    load <= '1';
    wait until falling_edge(clkdiv);
    load <= '0';

    wait;

end process bitsweep;


end febit3_testbench_arch;
