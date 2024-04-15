-- testbench for automatic front end, one AFE chip example
-- jamieson olsen <jamieson@fnal.gov>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

use work.daphne2_package.all;

entity frontend_testbench is
end frontend_testbench;

architecture frontend_testbench_arch of frontend_testbench is

component AFE5808 -- simple model of one AFE chip
port(
    clkadc_p, clkadc_n: in std_logic; -- assumes 62.5MHz, period 16.0ns    
    afe_p: out std_logic_vector(8 downto 0); -- FCLK is bit 8
    afe_n: out std_logic_vector(8 downto 0)
  );
end component;

component front_end
port(
    afe_p: in array_5x9_type;
    afe_n: in array_5x9_type;
    afe_clk_p:  out std_logic; -- copy of 62.5MHz master clock sent to AFEs
    afe_clk_n:  out std_logic;
    clock:   in  std_logic; -- master clock 62.5MHz
    clock7x: in  std_logic; -- 7 x master clock = 437.5MHz
    sclk200: in  std_logic; -- 200MHz system clock, constant
	reset_clock: in  std_logic;
	reset_sclk200: in  std_logic;
    done:    out std_logic_vector(4 downto 0); -- status of automatic alignment FSM
    dout:    out array_5x9x14_type -- data synchronized to clock
  );
end component;

constant sclk200_period:   time := 5.0ns;   -- 200 MHz
constant aclk_period:   time := 16.0ns;  -- 62.5 MHz
constant aclk7x_period: time := 2.285ns; -- 62.5 MHz * 7 = 437.5MHz

signal reset: std_logic := '1';
signal sclk200, aclk, aclk7x: std_logic := '0';

signal afe_p, afe_n: array_5x9_type;
signal clkadc_p, clkadc_n: std_logic;

begin

reset <= '1', '0' after 96ns;

-- make tha clocks

sclk200 <= not sclk200 after sclk200_period/2;

aclk <= not aclk after aclk_period/2; 

fastclk_proc: process
begin
    wait until rising_edge(aclk);
    for i in 6 downto 0 loop
        aclk7x <= '1';
        wait for aclk7x_period/2;
        aclk7x <= '0';
        wait for aclk7x_period/2;
    end loop;
end process;

-- make 5 AFE chips....

afegen: for i in 4 downto 0 generate

    afe_inst: AFE5808
    port map(
        clkadc_p => clkadc_p, clkadc_n => clkadc_n,
        afe_p => afe_p(i), afe_n => afe_n(i)
    );

end generate afegen;

fe_inst: front_end
port map(
    afe_p => afe_p,
    afe_n => afe_n,
    afe_clk_p => clkadc_p,
    afe_clk_n => clkadc_n,
    clock => aclk,
    clock7x => aclk7x,
    sclk200 => sclk200,
    reset_sclk200 => reset,
	reset_clock => reset
  );

end frontend_testbench_arch;
