-- testbench for DAPHNE3 deskew and alignment front end
-- TO DO: update this for AXI-LITE control and 5 AFEs!!!
--
-- jamieson olsen <jamieson@fnal.gov>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

use work.daphne3_package.all;

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
    
    -- AFE signals
    
    afe_p, afe_n: in array_5x9_type; -- LVDS data from AFEs
    afe_clk_p, afe_clk_n: out std_logic; -- fwd master clock to AFEs

    -- FPGA (PL) signals

    clock:  in std_logic; -- master clock 62.5MHz
    clk500: in std_logic; -- iserdes clock 500MHz
    clk125: in std_logic; -- iserdes clock 125MHz
    dout: out array_5x9x16_type; -- data synchronized to master clock
    trig: out std_logic; -- user generated trigger from AXI write to special register

    -- FPGA (PS) signals aka AXI-Lite slave:

    S_AXI_ACLK: in std_logic;
    S_AXI_ARESETN: in std_logic;
    S_AXI_AWADDR: in std_logic_vector(31 downto 0);
    S_AXI_AWPROT: in std_logic_vector(2 downto 0);
    S_AXI_AWVALID: in std_logic;
    S_AXI_AWREADY: out std_logic;
    S_AXI_WDATA: in std_logic_vector(31 downto 0);
    S_AXI_WSTRB: in std_logic_vector(3 downto 0);
    S_AXI_WVALID: in std_logic;
    S_AXI_WREADY: out std_logic;
    S_AXI_BRESP: out std_logic_vector(1 downto 0);
    S_AXI_BVALID: out std_logic;
    S_AXI_BREADY: in std_logic;
    S_AXI_ARADDR: in std_logic_vector(31 downto 0);
    S_AXI_ARPROT: in std_logic_vector(2 downto 0);
    S_AXI_ARVALID: in std_logic;
    S_AXI_ARREADY: out std_logic;
    S_AXI_RDATA: out std_logic_vector(31 downto 0);
    S_AXI_RRESP: out std_logic_vector(1 downto 0);
    S_AXI_RVALID: out std_logic;
    S_AXI_RREADY: in std_logic

  );
end component;

signal clock, clk125, clk500: std_logic := '1';
constant clock_period:    time := 16.0ns;  -- 62.5 MHz
constant clk125_period:   time := 8.0ns;   -- 125 MHz
constant clk500_period:   time := 2.0ns;   -- 500 MHz

signal afe_p, afe_n: array_5x9_type;
signal afe_clk_p, afe_clk_n: std_logic;
signal afe_dout: array_5x9x16_type;

signal S_AXI_ACLK: std_logic := '0';
constant S_AXI_ACLK_period: time := 10.0ns;  -- 100 MHz
signal S_AXI_ARESETN: std_logic := '0';
signal S_AXI_AWADDR: std_logic_vector(31 downto 0);
signal S_AXI_AWPROT: std_logic_vector(2 downto 0);
signal S_AXI_AWVALID: std_logic;
signal S_AXI_AWREADY: std_logic;
signal S_AXI_WDATA: std_logic_vector(31 downto 0);
signal S_AXI_WSTRB: std_logic_vector(3 downto 0);
signal S_AXI_WVALID: std_logic;
signal S_AXI_WREADY: std_logic;
signal S_AXI_BRESP: std_logic_vector(1 downto 0);
signal S_AXI_BVALID: std_logic;
signal S_AXI_BREADY: std_logic;
signal S_AXI_ARADDR: std_logic_vector(31 downto 0);
signal S_AXI_ARPROT: std_logic_vector(2 downto 0);
signal S_AXI_ARVALID: std_logic;
signal S_AXI_ARREADY: std_logic;
signal S_AXI_RDATA: std_logic_vector(31 downto 0);
signal S_AXI_RRESP: std_logic_vector(1 downto 0);
signal S_AXI_RVALID: std_logic;
signal S_AXI_RREADY: std_logic;

begin

clock  <= not clock  after clock_period/2;
clk125 <= not clk125 after clk125_period/2;
clk500 <= not clk500 after clk500_period/2;

-- instantiate the 5 AFE chips....

afegen: for i in 4 downto 0 generate

    afe_inst: AFE5808
    port map(
        clkadc_p => afe_clk_p, clkadc_n => afe_clk_n,
        afe_p => afe_p(i), afe_n => afe_n(i)
    );

end generate afegen;

-- instantiate the device under test...

DUT: front_end
port map(

    -- AFE signals...
    afe_p => afe_p,
    afe_n => afe_n,
    afe_clk_p => afe_clk_p,
    afe_clk_n => afe_clk_n,

    -- PL signals...
    clock => clock,
    clk500 => clk500,
    clk125 => clk125,
    dout => afe_dout,
    trig => open,

    -- PS signals...

    S_AXI_ACLK => S_AXI_ACLK,
    S_AXI_ARESETN => S_AXI_ARESETN,
    S_AXI_AWADDR => S_AXI_AWADDR,
    S_AXI_AWPROT => S_AXI_AWPROT,
    S_AXI_AWVALID => S_AXI_AWVALID,
    S_AXI_AWREADY => S_AXI_AWREADY,
    S_AXI_WDATA => S_AXI_WDATA,
    S_AXI_WSTRB => S_AXI_WSTRB,
    S_AXI_WVALID => S_AXI_WVALID,
    S_AXI_WREADY => S_AXI_WREADY, 
    S_AXI_BRESP => S_AXI_BRESP,
    S_AXI_BVALID => S_AXI_BVALID,
    S_AXI_BREADY => S_AXI_BREADY,
    S_AXI_ARADDR => S_AXI_ARADDR,
    S_AXI_ARPROT => S_AXI_ARPROT,
    S_AXI_ARVALID => S_AXI_ARVALID,
    S_AXI_ARREADY => S_AXI_ARREADY,
    S_AXI_RDATA => S_AXI_RDATA,
    S_AXI_RRESP => S_AXI_RRESP,
    S_AXI_RVALID => S_AXI_RVALID,
    S_AXI_RREADY => S_AXI_RREADY
  );

-- now we simulate the AXI-LITE master doing reads and writes...

S_AXI_ACLK <= not S_AXI_ACLK after S_AXI_ACLK_period/2;

aximaster_proc: process
-- function axilitepoke(addr32,data32)
-- function axilitepeek(addr32)
begin

wait for 300ns;
S_AXI_ARESETN <= '1'; -- release reset

wait for 100ns;

-- momentary reset the iserdes
-- clear the EN_VTC bit
-- sweep idelay tap values
-- set the EN_VTC bit

wait;
end process aximaster_proc;


end frontend_testbench_arch;
