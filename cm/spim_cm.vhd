-- spim_cm.vhd  (this is a work in progress!)
--
-- spi master for current monitor (ADS1261IRHBT)
--
-- This is kind of a strange SPI chip in that the number of bytes to transfer varies 
-- depending on the command. Most commands are 16 bits. The RREG command (40h + rrh) is 24 bits.
-- The RDATA command (12h) is 48 bits. Optionally CRC bytes can be sent along with the commands.
--
-- to handle the varible number of bytes, use a FIFO interface. There are two FIFOs. The input FIFO
-- holds the bytes to send to the SPI device. As these bytes/bits are being shifted into the SPI device
-- the bits coming out of the SPI device are collected and those bytes are stored in the OUTPUT FIFO.
-- The FIFOs should contain only data for ONE SPI sequence at a time; don't try to put multiple SPI
-- transfers in there or else the SPI device will get confused. The output FIFO is automatically flushed
-- every time a GO! is issued. AXI data width is 32 bits but only the lower 8 bits are used here when
-- reading/writing FIFOs.
--
-- Base+0: write up to 16 bytes to the INPUT FIFO
--         read up to 16 bytes from the OUTPUT FIFO
-- Base+4: write anything here to trigger an SPI transfer (GO!)
--         reading this register returns the BUSY flag in the LSb 
--
-- example: we want to write four bytes to the device and read back 4 bytes at the same time.
-- 1. write the four bytes to base+0, this is four seprate writes and the byte is in the lower 8 bits
-- 2. write to the GO register base+4
-- 3. this module shifts the X bits into (and out of) the CM device
-- 4. read base+4 and check to see if the module is still busy
-- 5. when not busy, OK to read four bytes from the output FIFO

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.daphne3_package.all;

entity spim_cm is
port(
    cm_sclk: out std_logic; -- max 10MHz
    cm_csn: out std_logic;
    cm_din: out std_logic;
    cm_dout: in std_logic;
    cm_drdyn: in std_logic;
    AXI_IN: in AXILITE_INREC;
    AXI_OUT: out AXILITE_OUTREC 
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

begin

-- process 1: AXI slave writes to INPUT FIFO, reads from OUTPUT FIFO. Writes to command register trigger GO pulse,
--  reads from status register return FSM BUSY status

-- while(GO=1) do:
--  Flush OUTPUT FIFO
--  Begin SPI sequence
--      While (INPUT FIFO != EMPTY) do:
--          Read a byte from INPUT FIFO
--          SPI shift 8 bits
--          Store byte in OUTPUT FIFO
--  End SPI sequence

-- ummm.... where is the code?!?

end spim_cm_arch;
