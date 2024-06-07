-- spim_cm.vhd
--
-- spi master for current monitor (ADS1261IRHBT)
--
-- This is kind of a strange SPI chip in that the number of bytes to transfer varies 
-- depending on the command. Most commands are 16 bits. The RREG command (40h + rrh) is 24 bits.
-- The RDATA command (12h) is 48 bits. Optionally CRC bytes can be sent along with the commands.
--
-- to handle the varible number of bytes, use a FIFO like interface here. 
--
-- Base+0: data FIFO, write up to 16 bytes to transfer, read up to 16 bytes returned.
--         only the lower 8 bits of the 32 bit are used here.
-- Base+4: write anything here to trigger an SPI transfer
--         reading this register returns the BUSY flag in the LSb 
--
-- example: we want to write four bytes to the device and read back 4 bytes at the same time.
-- 1. write the four bytes to base+0, this is four seprate writes and the byte is in the lower 8 bits
-- 2. write to the GO register base+4
-- 3. this module shifts the 32 bits into (and out of) the CM device
-- 4. read base+4 and check to see if the module is still busy
-- 5. when not busy, OK to read four bytes from the output FIFO

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spim_cm is
port(
    cm_sclk: out std_logic; -- max 10MHz
    cm_csn: out std_logic;
    cm_din: out std_logic;
    cm_dout: in std_logic;
    cm_drdyn: in std_logic;

    -- AXI-LITE interface

    S_AXI_ACLK	    : in std_logic; -- 100MHz
    S_AXI_ARESETN	: in std_logic;
	S_AXI_AWADDR	: in std_logic_vector(31 downto 0);
	S_AXI_AWPROT	: in std_logic_vector(2 downto 0);
	S_AXI_AWVALID	: in std_logic;
	S_AXI_AWREADY	: out std_logic;
	S_AXI_WDATA	    : in std_logic_vector(31 downto 0);
	S_AXI_WSTRB	    : in std_logic_vector(3 downto 0);
	S_AXI_WVALID	: in std_logic;
	S_AXI_WREADY	: out std_logic;
	S_AXI_BRESP	    : out std_logic_vector(1 downto 0);
	S_AXI_BVALID	: out std_logic;
	S_AXI_BREADY	: in std_logic;
	S_AXI_ARADDR	: in std_logic_vector(31 downto 0);
	S_AXI_ARPROT	: in std_logic_vector(2 downto 0);
	S_AXI_ARVALID	: in std_logic;
	S_AXI_ARREADY	: out std_logic;
	S_AXI_RDATA	    : out std_logic_vector(31 downto 0);
	S_AXI_RRESP	    : out std_logic_vector(1 downto 0);
	S_AXI_RVALID	: out std_logic;
	S_AXI_RREADY	: in std_logic
  );
end spim_cm;

architecture spim_cm_arch of spim_cm is

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
    signal ram_dout: std_logic_vector(31 downto 0);

begin

-- placeholder

end spim_cm_arch;
