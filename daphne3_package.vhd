-- daphne3_package.vhd
-- Jamieson Olsen <jamieson@fnal.gov>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package daphne3_package is

    type array_4x4_type is array (3 downto 0) of std_logic_vector(3 downto 0);
    type array_4x6_type is array (3 downto 0) of std_logic_vector(5 downto 0);
    type array_4x14_type is array (3 downto 0) of std_logic_vector(13 downto 0);
    type array_4x32_type is array (3 downto 0) of std_logic_vector(31 downto 0);
    type array_5x4_type is array (4 downto 0) of std_logic_vector(3 downto 0);
    type array_5x8_type is array (4 downto 0) of std_logic_vector(7 downto 0);
    type array_5x9_type is array (4 downto 0) of std_logic_vector(8 downto 0);
    type array_8x4_type is array (7 downto 0) of std_logic_vector(3 downto 0);
    type array_8x14_type is array (7 downto 0) of std_logic_vector(13 downto 0);
    type array_8x32_type is array (7 downto 0) of std_logic_vector(31 downto 0);
    type array_9x14_type is array (8 downto 0) of std_logic_vector(13 downto 0);
    type array_9x16_type is array (8 downto 0) of std_logic_vector(15 downto 0);
    type array_9x32_type is array (8 downto 0) of std_logic_vector(31 downto 0);
    type array_10x6_type is array (9 downto 0) of std_logic_vector(5 downto 0);
    type array_10x14_type is array (9 downto 0) of std_logic_vector(13 downto 0);

    type array_4x4x6_type is array (3 downto 0) of array_4x6_type;
    type array_4x4x14_type is array (3 downto 0) of array_4x14_type;
    type array_4x10x6_type is array (3 downto 0) of array_10x6_type;
    type array_4x10x14_type is array (3 downto 0) of array_10x14_type;
    type array_5x8x4_type is array (4 downto 0) of array_8x4_type;
    type array_5x8x14_type is array (4 downto 0) of array_8x14_type;
    type array_5x8x32_type is array (4 downto 0) of array_8x32_type;
    type array_5x9x14_type is array (4 downto 0) of array_9x14_type;
    type array_5x9x16_type is array (4 downto 0) of array_9x16_type;
    type array_5x9x32_type is array (4 downto 0) of array_9x32_type;

    -- write anything to this address to force spybuffer trigger

    constant TRIGGER_ADDR: std_logic_vector(31 downto 0) := X"00002000";

    -- control registers for the front end alignment logic

    constant FE_CTRL_ADDR: std_logic_vector(31 downto 0) := X"00002010";
    constant FE_STAT_ADDR: std_logic_vector(31 downto 0) := X"00002011";

    constant FE_AFE0_TAP_ADDR: std_logic_vector(31 downto 0) := X"00002020";
    constant FE_AFE1_TAP_ADDR: std_logic_vector(31 downto 0) := X"00002021";
    constant FE_AFE2_TAP_ADDR: std_logic_vector(31 downto 0) := X"00002022";
    constant FE_AFE3_TAP_ADDR: std_logic_vector(31 downto 0) := X"00002023";
    constant FE_AFE4_TAP_ADDR: std_logic_vector(31 downto 0) := X"00002024";

    constant FE_AFE0_BITSLIP_ADDR: std_logic_vector(31 downto 0) := X"00002030";
    constant FE_AFE1_BITSLIP_ADDR: std_logic_vector(31 downto 0) := X"00002031";
    constant FE_AFE2_BITSLIP_ADDR: std_logic_vector(31 downto 0) := X"00002032";
    constant FE_AFE3_BITSLIP_ADDR: std_logic_vector(31 downto 0) := X"00002033";
    constant FE_AFE4_BITSLIP_ADDR: std_logic_vector(31 downto 0) := X"00002034";

    -- output link parameters

    constant DAQ_OUT_PARAM_ADDR: std_logic_vector(31 downto 0) := X"00003000";

    constant DEFAULT_DAQ_OUT_SLOT_ID:     std_logic_vector(3 downto 0) := "0010";
    constant DEFAULT_DAQ_OUT_CRATE_ID:    std_logic_vector(9 downto 0) := "0000000001";
    constant DEFAULT_DAQ_OUT_DETECTOR_ID: std_logic_vector(5 downto 0) := "000010";
    constant DEFAULT_DAQ_OUT_VERSION_ID:  std_logic_vector(5 downto 0) := "000001";

    -- DAQ output link mode selection register

    constant DAQ_OUTMODE_BASEADDR: std_logic_vector(31 downto 0) := X"00003001";

    constant DEFAULT_DAQ_OUTMODE: std_logic_vector(7 downto 0) := X"00";

    -- master clock and timing endpoint status register

    constant MCLK_STAT_ADDR: std_logic_vector(31 downto 0) := X"00004000";

    -- master clock and timing endpoint control register

    constant MCLK_CTRL_ADDR: std_logic_vector(31 downto 0) := X"00004001";
    
    -- write anything to this address to reset master clock MMCM1

    constant MMCM1_RST_ADDR: std_logic_vector(31 downto 0) := X"00004002";

    -- write anything to this address to reset timing endpoint logic

    constant EP_RST_ADDR: std_logic_vector(31 downto 0) := X"00004003";

    -- choose which inputs are connected to each streaming core sender.
    -- This is a block of 16 registers and is R/W 0x5000 - 0x500F  

    constant CORE_INMUX_ADDR: std_logic_vector(31 downto 0) := "0000000000000000010100000000----";

    -- address of the threshold register for the self trig senders

    constant THRESHOLD_BASEADDR: std_logic_vector(31 downto 0) := X"00006000";

    constant DEFAULT_THRESHOLD: std_logic_vector(13 downto 0) := "00000100000000";

    -- enable disable individual input channels for self triggered sender only

    constant ST_ENABLE_ADDR: std_logic_vector(31 downto 0) := X"00006001";

    constant DEFAULT_ST_ENABLE: std_logic_vector(39 downto 0) := X"0000000000"; -- all self triggered channels OFF 

end package;


