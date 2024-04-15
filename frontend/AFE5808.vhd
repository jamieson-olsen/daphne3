-- AFE5808.vhd
-- simple model of an AFE chip in 16 bit mode, configured for sending LSb first
-- 14 bit ADC data padded into 16 bits by adding two zeros in the LSb positions
-- FOR EXAMPLE: the 14 bit data 0x218F is transmitted:  00 1111 0001 1000 
-- dclk output is omitted because the FPGA does need it...
-- jamieson olsen <jamieson@fnal.gov>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

entity AFE5808 is
port(
    clkadc_p, clkadc_n: in std_logic; -- assumes 62.5MHz, period 16.0ns
    afe_p, afe_n: out std_logic_vector(8 downto 0)
  );
end AFE5808;

architecture AFE5808_arch of AFE5808 is

    signal d0_vec: std_logic_vector(15 downto 0) := "1000000000000100"; -- 0x2001
    signal d1_vec: std_logic_vector(15 downto 0) := "1100000000001100"; -- 0x3003
    signal d2_vec: std_logic_vector(15 downto 0) := "1010101010101000"; -- 0x1555
    signal d3_vec: std_logic_vector(15 downto 0) := "0101010101010100"; -- 0x2AAA
    signal d4_vec: std_logic_vector(15 downto 0) := "1111111111111100"; -- 0x3FFF
    signal d5_vec: std_logic_vector(15 downto 0) := "0000000000000000"; -- 0x0000 
    signal d6_vec: std_logic_vector(15 downto 0) := "0010101011110000"; -- 0x0ABC
    signal d7_vec: std_logic_vector(15 downto 0) := "0000000000000000"; -- count up
    signal d8_vec: std_logic_vector(15 downto 0) := "1111111100000000"; -- aka FCLK 

    constant bit_time: time := 1.000ns;  -- 16.000ns / 16

    signal d: std_logic_vector(8 downto 0);
    signal clkadc: std_logic;

begin

    IBUFDS_inst : IBUFDS
        generic map ( DIFF_TERM => FALSE, IBUF_LOW_PWR => TRUE, IOSTANDARD => "DEFAULT" )
        port map ( I => clkadc_p, IB => clkadc_n, O => clkadc );

    -- create a 16x internal clock

    sender: process
    begin
        wait until rising_edge(clkadc);
        d7_vec <= std_logic_vector(unsigned(d7_vec)+4);
        for i in 0 to 15 loop  -- send LSb first!!!
            d(0) <= d0_vec(i);
            d(1) <= d1_vec(i);
            d(2) <= d2_vec(i);
            d(3) <= d3_vec(i);
            d(4) <= d4_vec(i);
            d(5) <= d5_vec(i);
            d(6) <= d6_vec(i);
            d(7) <= d7_vec(i);
            d(8) <= d8_vec(i);
            wait for bit_time;
        end loop;   
    end process sender;

    -- LVDS output buffers....

    genout: for i in 8 downto 0 generate

        obufds_inst: OBUFDS
         generic map ( IOSTANDARD => "DEFAULT", SLEW => "FAST" )
         port map ( I => d(i), O => afe_p(i), OB => afe_n(i) );

    end generate genout;


end AFE5808_arch;
