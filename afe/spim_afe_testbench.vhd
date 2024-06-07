-- testbench for AFE chip SPI interface
-- each AFE has two daisy-chained offset DACs and two daisy-chained trim DACs
-- groups 1+2 and 3+4 share some common SPI signals
-- jamieson olsen <jamieson@fnal.gov>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

use work.daphne3_package.all;

entity cm_testbench is
end cm_testbench;

architecture cm_testbench_arch of cm_testbench is

component AFE5808A is -- simple BFM of the AFE SPI interface
port(
    rst: in std_logic;
    pdn: in std_logic;
    sclk: in std_logic;
    sdata: in std_logic;
    sen: in std_logic;
    sdout: out std_logic
);
end component;

component AD5327 -- simple BFM of a serial SPI DAC
port(
    sclk: in std_logic;
    din: in std_logic;
    sync_n: in std_logic;
    ldac_n: in std_logic;
    sdo: out std_logic
);
end component;

component spim_afe
port(
    afe_rst: out std_logic; -- high = hard reset all AFEs
    afe_pdn: out std_logic; -- low = power down all AFEs

    afe0_miso: in std_logic;
    afe0_sclk: out std_logic;
    afe0_sdata: out std_logic;
    afe0_sen: out std_logic;
    afe0_trim_csn: out std_logic;
    afe0_trim_ldacn: out std_logic;
    afe0_offset_csn: out std_logic;
    afe0_offset_ldacn: out std_logic;

    afe12_miso: in std_logic;
    afe12_sclk: out std_logic;
    afe12_sdata: out std_logic;
    afe1_sen: out std_logic;
    afe2_sen: out std_logic;
    afe1_trim_csn: out std_logic;
    afe1_trim_ldacn: out std_logic;
    afe1_offset_csn: out std_logic;
    afe1_offset_ldacn: out std_logic;
    afe2_trim_csn: out std_logic;
    afe2_trim_ldacn: out std_logic;
    afe2_offset_csn: out std_logic;
    afe2_offset_ldacn: out std_logic;

    afe34_miso: in std_logic;
    afe34_sclk: out std_logic;
    afe34_sdata: out std_logic;
    afe3_sen: out std_logic;
    afe4_sen: out std_logic;
    afe3_trim_csn: out std_logic;
    afe3_trim_ldacn: out std_logic;
    afe3_offset_csn: out std_logic;
    afe3_offset_ldacn: out std_logic;
    afe4_trim_csn: out std_logic;
    afe4_trim_ldacn: out std_logic;
    afe4_offset_csn: out std_logic;
    afe4_offset_ldacn: out std_logic;

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

-- AXI master -> slave signals

signal S_AXI_ACLK: std_logic := '0';
constant S_AXI_ACLK_period: time := 10.0ns;  -- 100 MHz
signal S_AXI_ARESETN: std_logic := '0'; -- start off with AXI bus in reset
signal S_AXI_AWADDR: std_logic_vector(31 downto 0) := (others=>'0');
signal S_AXI_AWPROT: std_logic_vector(2 downto 0) := (others=>'0');
signal S_AXI_AWVALID: std_logic := '0';
signal S_AXI_WDATA: std_logic_vector(31 downto 0) := (others=>'0');
signal S_AXI_WSTRB: std_logic_vector(3 downto 0) := (others=>'0');
signal S_AXI_WVALID: std_logic := '0';
signal S_AXI_BREADY: std_logic := '0';
signal S_AXI_ARADDR: std_logic_vector(31 downto 0) := (others=>'0');
signal S_AXI_ARPROT: std_logic_vector(2 downto 0) := (others=>'0');
signal S_AXI_ARVALID: std_logic := '0';
signal S_AXI_RREADY: std_logic := '0';

-- AXI slave -> master signals

signal S_AXI_AWREADY: std_logic;
signal S_AXI_WREADY: std_logic;
signal S_AXI_BRESP: std_logic_vector(1 downto 0);
signal S_AXI_BVALID: std_logic;
signal S_AXI_ARREADY: std_logic;
signal S_AXI_RDATA: std_logic_vector(31 downto 0);
signal S_AXI_RRESP: std_logic_vector(1 downto 0);
signal S_AXI_RVALID: std_logic;

signal afe_rst, afe_pdn: std_logic;

signal afe0_sclk, afe0_sdata, afe0_sen, afe0_miso: std_logic;
signal afe0_offset_csn, afe0_offset_ldacn, afe0_offset_sdo: std_logic;
signal afe0_trim_csn, afe0_trim_ldacn, afe0_trim_sdo: std_logic;

signal afe12_sclk, afe12_sdata, afe1_sen, afe2_sen, afe12_miso: std_logic;
signal afe1_offset_csn, afe1_offset_ldacn, afe1_offset_sdo: std_logic;
signal afe1_trim_csn, afe1_trim_ldacn, afe1_trim_sdo: std_logic;
signal afe2_offset_csn, afe2_offset_ldacn, afe2_offset_sdo: std_logic;
signal afe2_trim_csn, afe2_trim_ldacn, afe2_trim_sdo: std_logic;

signal afe34_sclk, afe34_sdata, afe3_sen, afe4_sen, afe34_miso: std_logic;
signal afe3_offset_csn, afe3_offset_ldacn, afe3_offset_sdo: std_logic;
signal afe3_trim_csn, afe3_trim_ldacn, afe3_trim_sdo: std_logic;
signal afe4_offset_csn, afe4_offset_ldacn, afe4_offset_sdo: std_logic;
signal afe4_trim_csn, afe4_trim_ldacn, afe4_trim_sdo: std_logic;

begin

-- AFE0 group

AFE0_inst: AFE5808A
port map(
    rst   => afe_rst,
    pdn   => afe_pdn,
    sclk  => afe0_sclk,
    sdata => afe0_sdata,
    sen   => afe0_sen,
    sdout => afe0_miso
);

AFE0_OFFSET0_inst: AD5327 
port map(
    sclk   => afe0_sclk,
    din    => afe0_sdata,
    sync_n => afe0_offset_csn,
    ldac_n => afe0_offset_ldacn,
    sdo    => afe0_offset_sdo
);

AFE0_OFFSET1_inst: AD5327 
port map(
    sclk   => afe0_sclk,
    din    => afe0_offset_sdo,
    sync_n => afe0_offset_csn,
    ldac_n => afe0_offset_ldacn,
    sdo    => open
);

AFE0_TRIM0_inst: AD5327
port map(
    sclk   => afe0_sclk,
    din    => afe0_sdata,
    sync_n => afe0_trim_csn,
    ldac_n => afe0_trim_ldacn,
    sdo    => afe0_trim_sdo
);

AFE0_TRIM1_inst: AD5327
port map(
    sclk   => afe0_sclk,
    din    => afe0_trim_sdo,
    sync_n => afe0_trim_csn,
    ldac_n => afe0_trim_ldacn,
    sdo    => open
);

-- AFE1 group

AFE1_inst: AFE5808A
port map(
    rst   => afe_rst,
    pdn   => afe_pdn,
    sclk  => afe12_sclk,
    sdata => afe12_sdata,
    sen   => afe1_sen,
    sdout => afe12_miso
);

AFE1_OFFSET0_inst: AD5327
port map(
    sclk   => afe12_sclk,
    din    => afe12_sdata,
    sync_n => afe1_offset_csn,
    ldac_n => afe1_offset_ldacn,
    sdo    => afe1_offset_sdo
);

AFE1_OFFSET1_inst: AD5327
port map(
    sclk   => afe12_sclk,
    din    => afe1_offset_sdo,
    sync_n => afe1_offset_csn,
    ldac_n => afe1_offset_ldacn,
    sdo    => open
);

AFE1_TRIM0_inst: AD5327
port map(
    sclk   => afe12_sclk,
    din    => afe12_sdata,
    sync_n => afe1_trim_csn,
    ldac_n => afe1_trim_ldacn,
    sdo    => afe1_trim_sdo
);

AFE1_TRIM1_inst: AD5327
port map(
    sclk   => afe12_sclk,
    din    => afe1_trim_sdo,
    sync_n => afe1_trim_csn,
    ldac_n => afe1_trim_ldacn,
    sdo    => open
);

-- AFE2 group

AFE2_inst: AFE5808A
port map(
    rst   => afe_rst,
    pdn   => afe_pdn,
    sclk  => afe12_sclk,
    sdata => afe12_sdata,
    sen   => afe2_sen,
    sdout => afe12_miso
);

AFE2_OFFSET0_inst: AD5327
port map(
    sclk   => afe12_sclk,
    din    => afe12_sdata,
    sync_n => afe2_offset_csn,
    ldac_n => afe2_offset_ldacn,
    sdo    => afe2_offset_sdo
);

AFE2_OFFSET1_inst: AD5327
port map(
    sclk   => afe12_sclk,
    din    => afe2_offset_sdo,
    sync_n => afe2_offset_csn,
    ldac_n => afe2_offset_ldacn,
    sdo    => open
);

AFE2_TRIM0_inst: AD5327
port map(
    sclk   => afe12_sclk,
    din    => afe12_sdata,
    sync_n => afe2_trim_csn,
    ldac_n => afe2_trim_ldacn,
    sdo    => afe2_trim_sdo
);

AFE2_TRIM1_inst: AD5327
port map(
    sclk   => afe12_sclk,
    din    => afe2_trim_sdo,
    sync_n => afe2_trim_csn,
    ldac_n => afe2_trim_ldacn,
    sdo    => open
);

-- AFE3 group

AFE3_inst: AFE5808A
port map(
    rst   => afe_rst,
    pdn   => afe_pdn,
    sclk  => afe34_sclk,
    sdata => afe34_sdata,
    sen   => afe3_sen,
    sdout => afe34_miso
);

AFE3_OFFSET0_inst: AD5327
port map(
    sclk   => afe34_sclk,
    din    => afe34_sdata,
    sync_n => afe3_offset_csn,
    ldac_n => afe3_offset_ldacn,
    sdo    => afe3_offset_sdo
);

AFE3_OFFSET1_inst: AD5327
port map(
    sclk   => afe34_sclk,
    din    => afe3_offset_sdo,
    sync_n => afe3_offset_csn,
    ldac_n => afe3_offset_ldacn,
    sdo    => open
);

AFE3_TRIM0_inst: AD5327
port map(
    sclk   => afe34_sclk,
    din    => afe34_sdata,
    sync_n => afe3_trim_csn,
    ldac_n => afe3_trim_ldacn,
    sdo    => afe3_trim_sdo
);

AFE3_TRIM1_inst: AD5327
port map(
    sclk   => afe34_sclk,
    din    => afe3_trim_sdo,
    sync_n => afe3_trim_csn,
    ldac_n => afe3_trim_ldacn,
    sdo    => open
);

-- AFE4 group

AFE4_inst: AFE5808A
port map(
    rst   => afe_rst,
    pdn   => afe_pdn,
    sclk  => afe34_sclk,
    sdata => afe34_sdata,
    sen   => afe4_sen,
    sdout => afe34_miso
);

AFE4_OFFSET0_inst: AD5327
port map(
    sclk   => afe34_sclk,
    din    => afe34_sdata,
    sync_n => afe4_offset_csn,
    ldac_n => afe4_offset_ldacn,
    sdo    => afe4_offset_sdo
);

AFE4_OFFSET1_inst: AD5327
port map(
    sclk   => afe34_sclk,
    din    => afe4_offset_sdo,
    sync_n => afe4_offset_csn,
    ldac_n => afe4_offset_ldacn,
    sdo    => open
);

AFE4_TRIM0_inst: AD5327
port map(
    sclk   => afe34_sclk,
    din    => afe34_sdata,
    sync_n => afe4_trim_csn,
    ldac_n => afe4_trim_ldacn,
    sdo    => afe4_trim_sdo
);

AFE4_TRIM1_inst: AD5327
port map(
    sclk   => afe34_sclk,
    din    => afe4_trim_sdo,
    sync_n => afe4_trim_csn,
    ldac_n => afe4_trim_ldacn,
    sdo    => open
);

DUT: spim_afe
port map(

    afe_rst => afe_rst,
    afe_pdn => afe_pdn,

    afe0_sclk         => afe0_sclk,
    afe0_sdata        => afe0_sdata,
    afe0_sen          => afe0_sen,
    afe0_miso         => afe0_miso,
    afe0_trim_csn     => afe0_trim_csn,
    afe0_trim_ldacn   => afe0_trim_ldacn,
    afe0_offset_csn   => afe0_offset_csn,
    afe0_offset_ldacn => afe0_offset_ldacn,

    afe12_sclk         => afe12_sclk,
    afe12_sdata        => afe12_sdata,
    afe1_sen           => afe1_sen,
    afe2_sen           => afe2_sen,
    afe12_miso         => afe12_miso,
    afe1_trim_csn      => afe1_trim_csn,
    afe1_trim_ldacn    => afe1_trim_ldacn,
    afe1_offset_csn    => afe1_offset_csn,
    afe1_offset_ldacn  => afe1_offset_ldacn,
    afe2_trim_csn      => afe2_trim_csn,
    afe2_trim_ldacn    => afe2_trim_ldacn,
    afe2_offset_csn    => afe2_offset_csn,
    afe2_offset_ldacn  => afe2_offset_ldacn,

    afe34_sclk         => afe34_sclk,
    afe34_sdata        => afe34_sdata,
    afe3_sen           => afe3_sen,
    afe4_sen           => afe4_sen,
    afe34_miso         => afe34_miso,
    afe3_trim_csn      => afe3_trim_csn,
    afe3_trim_ldacn    => afe3_trim_ldacn,
    afe3_offset_csn    => afe3_offset_csn,
    afe3_offset_ldacn  => afe3_offset_ldacn,
    afe4_trim_csn      => afe4_trim_csn,
    afe4_trim_ldacn    => afe4_trim_ldacn,
    afe4_offset_csn    => afe4_offset_csn,
    afe4_offset_ldacn  => afe4_offset_ldacn,

    S_AXI_ACLK    => S_AXI_ACLK,
    S_AXI_ARESETN => S_AXI_ARESETN,
    S_AXI_AWADDR  => S_AXI_AWADDR,
    S_AXI_AWPROT  => S_AXI_AWPROT,
    S_AXI_AWVALID => S_AXI_AWVALID,
    S_AXI_AWREADY => S_AXI_AWREADY,
    S_AXI_WDATA   => S_AXI_WDATA,
    S_AXI_WSTRB   => S_AXI_WSTRB,
    S_AXI_WVALID  => S_AXI_WVALID,
    S_AXI_WREADY  => S_AXI_WREADY, 
    S_AXI_BRESP   => S_AXI_BRESP,
    S_AXI_BVALID  => S_AXI_BVALID,
    S_AXI_BREADY  => S_AXI_BREADY,
    S_AXI_ARADDR  => S_AXI_ARADDR,
    S_AXI_ARPROT  => S_AXI_ARPROT,
    S_AXI_ARVALID => S_AXI_ARVALID,
    S_AXI_ARREADY => S_AXI_ARREADY,
    S_AXI_RDATA   => S_AXI_RDATA,
    S_AXI_RRESP   => S_AXI_RRESP,
    S_AXI_RVALID  => S_AXI_RVALID,
    S_AXI_RREADY  => S_AXI_RREADY
  );

-- now we simulate the AXI-LITE master doing reads and writes...

S_AXI_ACLK <= not S_AXI_ACLK after S_AXI_ACLK_period/2;

aximaster_proc: process

procedure axipoke( constant addr: in std_logic_vector;
                   constant data: in std_logic_vector ) is
begin
    wait until rising_edge(S_AXI_ACLK);
    S_AXI_AWADDR <= addr;
    S_AXI_AWVALID <= '1';
    S_AXI_WDATA <= data;
    S_AXI_WVALID <= '1';
    S_AXI_BREADY <= '1';
    S_AXI_WSTRB <= "1111";
    wait until (rising_edge(S_AXI_ACLK) and S_AXI_AWREADY='1' and S_AXI_WREADY='1');
    S_AXI_AWADDR <= X"00000000";
    S_AXI_AWVALID <= '0';
    S_AXI_WDATA <= X"00000000";
    S_AXI_AWVALID <= '0';
    S_AXI_WSTRB <= "0000";
    wait until (rising_edge(S_AXI_ACLK) and S_AXI_BVALID='1');
    S_AXI_BREADY <= '0';
end procedure axipoke;

procedure axipeek( constant addr: in std_logic_vector ) is
begin
    wait until rising_edge(S_AXI_ACLK);
    S_AXI_ARADDR <= addr;
    S_AXI_ARVALID <= '1';
    S_AXI_RREADY <= '1';
    wait until (rising_edge(S_AXI_ACLK) and S_AXI_ARREADY='1');
    S_AXI_ARADDR <= X"00000000";
    S_AXI_ARVALID <= '0';
    wait until (rising_edge(S_AXI_ACLK) and S_AXI_RVALID='1');
    S_AXI_RREADY <= '0';
end procedure axipeek;

begin

wait for 300ns;
S_AXI_ARESETN <= '1'; -- release AXI reset
wait for 500ns;

-- assume the AXI slave base address is 0

-- get ready to transfer 4 bytes

axipoke(addr => X"00000000", data => X"00000012"); 
wait for 500ns;
axipoke(addr => X"00000000", data => X"00000034"); 
wait for 500ns;
axipoke(addr => X"00000000", data => X"00000056"); 
wait for 500ns;
axipoke(addr => X"00000000", data => X"00000078"); 

-- go!

wait for 500ns;
axipoke(addr => X"00000004", data => X"DEADBEEF");

-- wait while it is busy....
wait for 1000ns;

-- read what was sent back

wait for 500ns;
axipeek(addr => X"00000000");
wait for 500ns;
axipeek(addr => X"00000000");
wait for 500ns;
axipeek(addr => X"00000000");
wait for 500ns;
axipeek(addr => X"00000000");

wait;
end process aximaster_proc;

end cm_testbench_arch;
