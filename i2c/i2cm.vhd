-- i2cm.vhd
-- i2c master for PL DAPHNE3
-- don't use the Xilinx IP, roll our own I2C master here...
-- Jamieson Olsen <jamieson@fnal.gov>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.daphne3_package.all;

entity i2cm is
port(
    pl_sda: inout std_logic;
    pl_scl: out std_logic;
    AXI_IN: in AXILITE_INREC;
    AXI_OUT: out AXILITE_OUTREC   
  );
end i2cm;

architecture i2cm_arch of i2cm is

	signal axi_awaddr: std_logic_vector(31 downto 0);
	signal axi_awready: std_logic;
	signal axi_wready: std_logic;
	signal axi_bresp: std_logic_vector(1 downto 0);
	signal axi_bvalid: std_logic;
	signal axi_araddr: std_logic_vector(31 downto 0);
	signal axi_arready: std_logic;
	signal axi_rdata: std_logic_vector(31 downto 0);
	signal axi_rresp: std_logic_vector(1 downto 0);
	signal axi_rvalid: std_logic;
	signal axi_arready_reg: std_logic;
    signal axi_arvalid: std_logic;       

	signal rden, wren: std_logic;
	signal aw_en: std_logic;
    signal addra: std_logic_vector(10 downto 0);

begin

-- Xilinx IP core for I2C master goes here...

end i2cm_arch;
