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

entity spim_afe_testbench is
end spim_afe_testbench;

architecture spim_afe_testbench_arch of spim_afe_testbench is

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
    afe0_mosi: out std_logic;

    afe12_miso: in std_logic;
    afe12_sclk: out std_logic;
    afe12_mosi: out std_logic;

    afe34_miso: in std_logic;
    afe34_sclk: out std_logic;
    afe34_mosi: out std_logic;

    afe_sen: out std_logic_vector(4 downto 0);
    trim_sync_n: out std_logic_vector(4 downto 0);
    trim_ldac_n: out std_logic_vector(4 downto 0);
    offset_sync_n: out std_logic_vector(4 downto 0);
    offset_ldac_n: out std_logic_vector(4 downto 0);

    AXI_IN: in AXILITE_INREC; 
    AXI_OUT: out AXILITE_OUTREC 

  );
end component;

signal AXI_IN: AXILITE_INREC := (ACLK=>'0', ARESETN=>'0', AWADDR=>X"00000000", 
    AWPROT=>"000", AWVALID=>'0', WDATA=>X"00000000", WSTRB=>"0000", WVALID=>'0', 
    BREADY=>'0', ARADDR=>X"00000000", ARPROT=>"000", ARVALID=>'0', RREADY=>'0');
signal AXI_OUT: AXILITE_OUTREC;

constant ACLK_period: time := 10.0ns;  -- 100 MHz

signal afe_rst, afe_pdn: std_logic;

signal afe0_miso: std_logic;
signal afe0_sclk: std_logic;
signal afe0_mosi: std_logic;

signal afe12_miso: std_logic;
signal afe12_sclk: std_logic;
signal afe12_mosi: std_logic;

signal afe34_miso: std_logic;
signal afe34_sclk: std_logic;
signal afe34_mosi: std_logic;

signal afe_sen: std_logic_vector(4 downto 0);
signal trim_sync_n: std_logic_vector(4 downto 0);
signal trim_ldac_n: std_logic_vector(4 downto 0);
signal offset_sync_n: std_logic_vector(4 downto 0);
signal offset_ldac_n: std_logic_vector(4 downto 0);

signal afe0_offset_sdo, afe0_trim_sdo: std_logic;
signal afe1_offset_sdo, afe1_trim_sdo: std_logic;
signal afe2_offset_sdo, afe2_trim_sdo: std_logic;
signal afe3_offset_sdo, afe3_trim_sdo: std_logic;
signal afe4_offset_sdo, afe4_trim_sdo: std_logic;

begin

-- AFE0 group

AFE0_inst: AFE5808A
port map(
    rst   => afe_rst,
    pdn   => afe_pdn,
    sclk  => afe0_sclk,
    sdata => afe0_mosi,
    sen   => afe_sen(0),
    sdout => afe0_miso
);

AFE0_OFFSET0_inst: AD5327 
port map(
    sclk   => afe0_sclk,
    din    => afe0_mosi,
    sync_n => offset_sync_n(0),
    ldac_n => offset_ldac_n(0),
    sdo    => afe0_offset_sdo
);

AFE0_OFFSET1_inst: AD5327 
port map(
    sclk   => afe0_sclk,
    din    => afe0_offset_sdo,
    sync_n => offset_sync_n(0),
    ldac_n => offset_ldac_n(0),
    sdo    => open
);

AFE0_TRIM0_inst: AD5327
port map(
    sclk   => afe0_sclk,
    din    => afe0_mosi,
    sync_n => trim_sync_n(0),
    ldac_n => trim_ldac_n(0),
    sdo    => afe0_trim_sdo
);

AFE0_TRIM1_inst: AD5327
port map(
    sclk   => afe0_sclk,
    din    => afe0_trim_sdo,
    sync_n => trim_sync_n(0),
    ldac_n => trim_ldac_n(0),
    sdo    => open
);

-- AFE1 group

AFE1_inst: AFE5808A
port map(
    rst   => afe_rst,
    pdn   => afe_pdn,
    sclk  => afe12_sclk,
    sdata => afe12_mosi,
    sen   => afe_sen(1),
    sdout => afe12_miso
);

AFE1_OFFSET0_inst: AD5327
port map(
    sclk   => afe12_sclk,
    din    => afe12_mosi,
    sync_n => offset_sync_n(1),
    ldac_n => offset_ldac_n(1),
    sdo    => afe1_offset_sdo
);

AFE1_OFFSET1_inst: AD5327
port map(
    sclk   => afe12_sclk,
    din    => afe1_offset_sdo,
    sync_n => offset_sync_n(1),
    ldac_n => offset_ldac_n(1),
    sdo    => open
);

AFE1_TRIM0_inst: AD5327
port map(
    sclk   => afe12_sclk,
    din    => afe12_mosi,
    sync_n => trim_sync_n(1),
    ldac_n => trim_ldac_n(1),
    sdo    => afe1_trim_sdo
);

AFE1_TRIM1_inst: AD5327
port map(
    sclk   => afe12_sclk,
    din    => afe1_trim_sdo,
    sync_n => trim_sync_n(1),
    ldac_n => trim_ldac_n(1),
    sdo    => open
);

-- AFE2 group

AFE2_inst: AFE5808A
port map(
    rst   => afe_rst,
    pdn   => afe_pdn,
    sclk  => afe12_sclk,
    sdata => afe12_mosi,
    sen   => afe_sen(2),
    sdout => afe12_miso
);

AFE2_OFFSET0_inst: AD5327
port map(
    sclk   => afe12_sclk,
    din    => afe12_mosi,
    sync_n => offset_sync_n(2),
    ldac_n => offset_ldac_n(2),
    sdo    => afe2_offset_sdo
);

AFE2_OFFSET1_inst: AD5327
port map(
    sclk   => afe12_sclk,
    din    => afe2_offset_sdo,
    sync_n => offset_sync_n(2),
    ldac_n => offset_ldac_n(2),
    sdo    => open
);

AFE2_TRIM0_inst: AD5327
port map(
    sclk   => afe12_sclk,
    din    => afe12_mosi,
    sync_n => trim_sync_n(2),
    ldac_n => trim_ldac_n(2),
    sdo    => afe2_trim_sdo
);

AFE2_TRIM1_inst: AD5327
port map(
    sclk   => afe12_sclk,
    din    => afe2_trim_sdo,
    sync_n => trim_sync_n(2),
    ldac_n => trim_ldac_n(2),
    sdo    => open
);

-- AFE3 group

AFE3_inst: AFE5808A
port map(
    rst   => afe_rst,
    pdn   => afe_pdn,
    sclk  => afe34_sclk,
    sdata => afe34_mosi,
    sen   => afe_sen(3),
    sdout => afe34_miso
);

AFE3_OFFSET0_inst: AD5327
port map(
    sclk   => afe34_sclk,
    din    => afe34_mosi,
    sync_n => offset_sync_n(3),
    ldac_n => offset_ldac_n(3),
    sdo    => afe3_offset_sdo
);

AFE3_OFFSET1_inst: AD5327
port map(
    sclk   => afe34_sclk,
    din    => afe3_offset_sdo,
    sync_n => offset_sync_n(3),
    ldac_n => offset_ldac_n(3),
    sdo    => open
);

AFE3_TRIM0_inst: AD5327
port map(
    sclk   => afe34_sclk,
    din    => afe34_mosi,
    sync_n => trim_sync_n(3),
    ldac_n => trim_ldac_n(3),
    sdo    => afe3_trim_sdo
);

AFE3_TRIM1_inst: AD5327
port map(
    sclk   => afe34_sclk,
    din    => afe3_trim_sdo,
    sync_n => trim_sync_n(3),
    ldac_n => trim_ldac_n(3),
    sdo    => open
);

-- AFE4 group

AFE4_inst: AFE5808A
port map(
    rst   => afe_rst,
    pdn   => afe_pdn,
    sclk  => afe34_sclk,
    sdata => afe34_mosi,
    sen   => afe_sen(4),
    sdout => afe34_miso
);

AFE4_OFFSET0_inst: AD5327
port map(
    sclk   => afe34_sclk,
    din    => afe34_mosi,
    sync_n => offset_sync_n(4),
    ldac_n => offset_ldac_n(4),
    sdo    => afe4_offset_sdo
);

AFE4_OFFSET1_inst: AD5327
port map(
    sclk   => afe34_sclk,
    din    => afe4_offset_sdo,
    sync_n => offset_sync_n(4),
    ldac_n => offset_ldac_n(4),
    sdo    => open
);

AFE4_TRIM0_inst: AD5327
port map(
    sclk   => afe34_sclk,
    din    => afe34_mosi,
    sync_n => trim_sync_n(4),
    ldac_n => trim_ldac_n(4),
    sdo    => afe4_trim_sdo
);

AFE4_TRIM1_inst: AD5327
port map(
    sclk   => afe34_sclk,
    din    => afe4_trim_sdo,
    sync_n => trim_sync_n(4),
    ldac_n => trim_ldac_n(4),
    sdo    => open
);

DUT: spim_afe
port map(

    afe_rst => afe_rst,
    afe_pdn => afe_pdn,

    afe0_miso => afe0_miso,
    afe0_sclk => afe0_sclk,
    afe0_mosi => afe0_mosi,

    afe12_miso => afe12_miso,
    afe12_sclk => afe12_sclk,
    afe12_mosi => afe12_mosi,

    afe34_miso => afe34_miso,
    afe34_sclk => afe34_sclk,
    afe34_mosi => afe34_mosi,

    afe_sen => afe_sen,
    trim_sync_n => trim_sync_n,
    trim_ldac_n => trim_ldac_n,
    offset_sync_n => offset_sync_n,
    offset_ldac_n => offset_ldac_n,

    AXI_IN => AXI_IN,
    AXI_OUT => AXI_OUT

  );

-- now we simulate the AXI-LITE master doing reads and writes...

AXI_IN.ACLK <= not AXI_IN.ACLK after ACLK_period/2;

aximaster_proc: process

procedure axipoke( constant addr: in std_logic_vector;
                   constant data: in std_logic_vector ) is
begin
    wait until rising_edge(AXI_IN.ACLK);
    AXI_IN.AWADDR <= addr;
    AXI_IN.AWVALID <= '1';
    AXI_IN.WDATA <= data;
    AXI_IN.WVALID <= '1';
    AXI_IN.BREADY <= '1';
    AXI_IN.WSTRB <= "1111";
    wait until (rising_edge(AXI_IN.ACLK) and AXI_OUT.AWREADY='1' and AXI_OUT.WREADY='1');
    AXI_IN.AWADDR <= X"00000000";
    AXI_IN.AWVALID <= '0';
    AXI_IN.WDATA <= X"00000000";
    AXI_IN.AWVALID <= '0';
    AXI_IN.WSTRB <= "0000";
    wait until (rising_edge(AXI_IN.ACLK) and AXI_OUT.BVALID='1');
    AXI_IN.BREADY <= '0';
end procedure axipoke;

procedure axipeek( constant addr: in std_logic_vector ) is
begin
    wait until rising_edge(AXI_IN.ACLK);
    AXI_IN.ARADDR <= addr;
    AXI_IN.ARVALID <= '1';
    AXI_IN.RREADY <= '1';
    wait until (rising_edge(AXI_IN.ACLK) and AXI_OUT.ARREADY='1');
    AXI_IN.ARADDR <= X"00000000";
    AXI_IN.ARVALID <= '0';
    wait until (rising_edge(AXI_IN.ACLK) and AXI_OUT.RVALID='1');
    AXI_IN.RREADY <= '0';
end procedure axipeek;

begin

wait for 500ns;
AXI_IN.ARESETN <= '1'; -- release AXI reset

wait for 500ns;
axipoke(addr => X"00000000", data => X"00000003"); -- power down all AFEs and hard reset all AFEs

wait for 500ns;
axipoke(addr => X"00000000", data => X"00000001"); -- release power down, continue to force hard reset all AFEs

wait for 500ns;
axipoke(addr => X"00000000", data => X"00000000"); -- release hard reset all AFEs

wait for 500ns;

-- -------------------------------------------------------------

axipoke(addr => X"00000004", data => X"008000FF"); -- write 24 bits to AFE0 SPI interface (busy for ~3us)
wait for 3us;

axipoke(addr => X"00000008", data => X"7DAC0001"); -- write trim0 dacs (busy for ~4us)
wait for 4us;

axipoke(addr => X"0000000C", data => X"0FF5E770"); -- write offset0 dacs (busy for ~4us)
wait for 4us;

-- -------------------------------------------------------------

axipoke(addr => X"00000010", data => X"008111FF"); -- write 24 bits to AFE1 SPI interface (busy for ~3us)
wait for 3us;

axipoke(addr => X"00000014", data => X"7DAC0002"); -- write trim1 dacs (busy for ~4us)
wait for 4us;

axipoke(addr => X"00000018", data => X"0FF5E771"); -- write offset1 dacs (busy for ~4us)
wait for 4us;

-- -------------------------------------------------------------

axipoke(addr => X"0000001C", data => X"008222FF"); -- write 24 bits to AFE2 SPI interface (busy for ~3us)
wait for 3us;

axipoke(addr => X"00000020", data => X"7DAC0002"); -- write trim2 dacs (busy for ~4us)
wait for 4us;

axipoke(addr => X"00000024", data => X"0FF5E772"); -- write offset2 dacs (busy for ~4us)
wait for 4us;

-- -------------------------------------------------------------

axipoke(addr => X"00000028", data => X"008333FF"); -- write 24 bits to AFE3 SPI interface (busy for ~3us)
wait for 3us;

axipoke(addr => X"0000002C", data => X"7DAC0003"); -- write trim3 dacs (busy for ~4us)
wait for 4us;

axipoke(addr => X"00000030", data => X"0FF5E773"); -- write offset3 dacs (busy for ~4us)
wait for 4us;

-- -------------------------------------------------------------

axipoke(addr => X"00000034", data => X"008444FF"); -- write 24 bits to AFE4 SPI interface (busy for ~3us)
wait for 3us;

axipoke(addr => X"00000038", data => X"7DAC0004"); -- write trim4 dacs (busy for ~4us)
wait for 4us;

axipoke(addr => X"0000003C", data => X"0FF5E774"); -- write offset4 dacs (busy for ~4us)
wait for 4us;

-- -------------------------------------------------------------

wait;
end process aximaster_proc;

end spim_afe_testbench_arch;
