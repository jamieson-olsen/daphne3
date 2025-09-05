-- daphne3_package.vhd
-- Jamieson Olsen <jamieson@fnal.gov>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package daphne3_package is

    type array_4x4_type is array (3 downto 0) of std_logic_vector(3 downto 0);
    type array_4x6_type is array (3 downto 0) of std_logic_vector(5 downto 0);
    type array_4x8_type is array (3 downto 0) of std_logic_vector(7 downto 0);
    type array_4x14_type is array (3 downto 0) of std_logic_vector(13 downto 0);
    type array_4x32_type is array (3 downto 0) of std_logic_vector(31 downto 0);
    type array_4x64_type is array(3 downto 0) of std_logic_vector(63 downto 0);
    type array_5x4_type is array (4 downto 0) of std_logic_vector(3 downto 0);
    type array_5x8_type is array (4 downto 0) of std_logic_vector(7 downto 0);
    type array_5x9_type is array (4 downto 0) of std_logic_vector(8 downto 0);
    type array_8x4_type is array (7 downto 0) of std_logic_vector(3 downto 0);
    type array_8x6_type is array(7 downto 0) of std_logic_vector(5 downto 0);
    type array_8x14_type is array(7 downto 0) of std_logic_vector(13 downto 0);
    type array_8x32_type is array(7 downto 0) of std_logic_vector(31 downto 0);
    type array_8x64_type is array(7 downto 0) of std_logic_vector(63 downto 0);
    type array_9x14_type is array(8 downto 0) of std_logic_vector(13 downto 0);
    type array_9x16_type is array(8 downto 0) of std_logic_vector(15 downto 0);
    type array_9x32_type is array(8 downto 0) of std_logic_vector(31 downto 0);
    type array_10x6_type is array(9 downto 0) of std_logic_vector(5 downto 0);
    type array_10x14_type is array(9 downto 0) of std_logic_vector(13 downto 0);
    type array_20x14_type is array(19 downto 0) of std_logic_vector(13 downto 0);
    type array_32x6_type is array(31 downto 0) of std_logic_vector(5 downto 0);
    type array_40x14_type is array(39 downto 0) of std_logic_vector(13 downto 0);
    type array_40x16_type is array(39 downto 0) of std_logic_vector(15 downto 0);
    type array_40x64_type is array(39 downto 0) of std_logic_vector(63 downto 0);

    type array_4x4x6_type is array (3 downto 0) of array_4x6_type;
    type array_4x4x14_type is array (3 downto 0) of array_4x14_type;
    type array_4x8x6_type is array(3 downto 0) of array_8x6_type;
    type array_4x8x14_type is array(3 downto 0) of array_8x14_type;
    type array_4x10x6_type is array (3 downto 0) of array_10x6_type;
    type array_4x10x14_type is array (3 downto 0) of array_10x14_type;
    type array_5x8x4_type is array (4 downto 0) of array_8x4_type;
    type array_5x8x14_type is array (4 downto 0) of array_8x14_type;
    type array_5x8x32_type is array (4 downto 0) of array_8x32_type;
    type array_5x9x14_type is array (4 downto 0) of array_9x14_type;
    type array_5x9x16_type is array (4 downto 0) of array_9x16_type;
    type array_5x9x32_type is array (4 downto 0) of array_9x32_type;
    type array_8x4x8_type is array(7 downto 0) of array_4x8_type;
    type array_8x4x14_type is array(7 downto 0) of array_4x14_type;

    -- use records to simplify AXI Lite I/O

    type AXILITE_INREC is record
    	ACLK: std_logic;
    	ARESETN: std_logic;
    	AWADDR: std_logic_vector(31 downto 0);
    	AWPROT: std_logic_vector(2 downto 0);
    	AWVALID: std_logic;
    	WDATA: std_logic_vector(31 downto 0);
    	WSTRB: std_logic_vector(3 downto 0);
    	WVALID: std_logic;
    	BREADY: std_logic;
    	ARADDR: std_logic_vector(31 downto 0);
    	ARPROT: std_logic_vector(2 downto 0);
    	ARVALID: std_logic;
    	RREADY: std_logic;
    end record AXILITE_INREC;

    type AXILITE_OUTREC is record
    	WREADY: std_logic;
    	BRESP: std_logic_vector(1 downto 0);
       	BVALID: std_logic;
	    AWREADY: std_logic;
    	ARREADY: std_logic;
    	RDATA: std_logic_vector(31 downto 0);
    	RRESP: std_logic_vector(1 downto 0);
    	RVALID: std_logic;
    end record AXILITE_OUTREC;

end package;


