-- stream_input_mux.vhd
-- For DAPHNE_MEZZ streaming sender
-- 5x9 input buses -> 8x4 output buses 
-- 32 8-bit registers for control, these are R/W
--
-- adding 32 additional registers, each 14 bits, for programmable thresholds
-- these are R/W
--
-- Jamieson Olsen <jamieson@fnal.gov>
--
-- axi-lite memory map:
--
-- address      description
--
-- base+0x00    select register for dout(0)(0)
-- base+0x04    select register for dout(0)(1)
-- base+0x08    select register for dout(0)(2)
-- base+0x0C    select register for dout(0)(3)
--
-- base+0x10    select register for dout(1)(0)
-- base+0x14    select register for dout(1)(1)
-- base+0x18    select register for dout(1)(2)
-- base+0x1C    select register for dout(1)(3)
--
-- base+0x20    select register for dout(2)(0)
-- base+0x24    select register for dout(2)(1)
-- base+0x28    select register for dout(2)(2)
-- base+0x2C    select register for dout(2)(3)
--
-- base+0x30    select register for dout(3)(0)
-- base+0x34    select register for dout(3)(1)
-- base+0x38    select register for dout(3)(2)
-- base+0x3C    select register for dout(3)(3)
--
-- base+0x40    select register for dout(4)(0)
-- base+0x44    select register for dout(4)(1)
-- base+0x48    select register for dout(4)(2)
-- base+0x4C    select register for dout(4)(3)
--
-- base+0x50    select register for dout(5)(0)
-- base+0x54    select register for dout(5)(1)
-- base+0x58    select register for dout(5)(2)
-- base+0x5C    select register for dout(5)(3)
--
-- base+0x60    select register for dout(6)(0)
-- base+0x64    select register for dout(6)(1)
-- base+0x68    select register for dout(6)(2)
-- base+0x6C    select register for dout(6)(3)
--
-- base+0x70    select register for dout(7)(0)
-- base+0x74    select register for dout(7)(1)
-- base+0x78    select register for dout(7)(2)
-- base+0x7C    select register for dout(7)(3)
--
-- base+0x80 = threshold for dout(0)(0)
-- base+0x84 = threshold for dout(0)(1)
-- ....
-- base+0xFC = threshold for dout(7)(3)
--
-- The select register (muxctrl_reg) is 8 bits
-- normal values for input channels are 0-39, where:
-- 0 = AFE0 channel 0
-- 1 = AFE0 channel 1 
-- ...
-- 7 = AFE0 channel 7
-- 8 = AFE1 channel 1
-- ...
-- 39 = AFE4 channel 7
-- 
-- values above 39 are for test modes, see description in the code
-- further down in this file for details
--
-- remember: in the streaming mode sender this module determines what data is sent
-- to the core. it does NOT control what the input spy buffers see!

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.daphne3_package.all;

entity stream_input_mux is
port(
    clock: in std_logic; -- 62.5MHz master clock
    din: in array_5x9x16_type; -- from the front end
    dout: out array_8x4x14_type;
    muxctrl: out array_8x4x8_type;
    threshold: out array_8x4x14_type;
    AXI_IN: in AXILITE_INREC;
    AXI_OUT: out AXILITE_OUTREC
  );
end stream_input_mux;

architecture stream_input_mux_arch of stream_input_mux is

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
signal reg_rden: std_logic;
signal reg_wren: std_logic;
signal reg_data_out:std_logic_vector(31 downto 0);
signal aw_en: std_logic;

signal muxctrl_reg: array_8x4x8_type; -- afe number in upper nibble, afe channel number in lower nibble
signal threshold_reg: array_8x4x14_type; -- programmable threshold value 14 bits

signal counter_reg: std_logic_vector(13 downto 0) := "00000000000000";
signal rand_reg:    std_logic_vector(13 downto 0) := "00100111010101";

begin

-- make a few test counters for debugging
-- rand_reg is LFSR with taps selected for max run length

counter_proc: process(clock)
begin
    if rising_edge(clock) then
        counter_reg <= std_logic_vector( unsigned(counter_reg) + 1 );
        rand_reg  <= rand_reg(12 downto 0) & (rand_reg(13) xor rand_reg(12) xor rand_reg(10) xor rand_reg(7));
    end if;
end process counter_proc;

-- big old programmable mux: 5x9 inputs ---> 8x4 outputs
-- this is controlled by afe_reg and afe_ch_reg, a block of regs
-- these registers are R/W from AXI LITE interface
--
-- some examples:
-- if mux_ctrl(2)(3)=X"07" then dout(2)(3) is connected to din(0)(7)
-- if mux_ctrl(4)(1)=X"3B" then dout(4)(1) is forced to all zeros
-- if mux_ctrl(5)(1)=X"2D" then dout(5)(1) is a pseudorandom pattern

-- do the 16->14 bit truncation here

gen_send: for s in 7 downto 0 generate
    gen_chan: for c in 3 downto 0 generate

        dout(s)(c) <= din(0)(0)(15 downto 2) when (muxctrl_reg(s)(c)=X"00") else 
                      din(0)(1)(15 downto 2) when (muxctrl_reg(s)(c)=X"01") else 
                      din(0)(2)(15 downto 2) when (muxctrl_reg(s)(c)=X"02") else 
                      din(0)(3)(15 downto 2) when (muxctrl_reg(s)(c)=X"03") else 
                      din(0)(4)(15 downto 2) when (muxctrl_reg(s)(c)=X"04") else 
                      din(0)(5)(15 downto 2) when (muxctrl_reg(s)(c)=X"05") else 
                      din(0)(6)(15 downto 2) when (muxctrl_reg(s)(c)=X"06") else 
                      din(0)(7)(15 downto 2) when (muxctrl_reg(s)(c)=X"07") else 

                      din(1)(0)(15 downto 2) when (muxctrl_reg(s)(c)=X"08") else 
                      din(1)(1)(15 downto 2) when (muxctrl_reg(s)(c)=X"09") else 
                      din(1)(2)(15 downto 2) when (muxctrl_reg(s)(c)=X"0A") else 
                      din(1)(3)(15 downto 2) when (muxctrl_reg(s)(c)=X"0B") else 
                      din(1)(4)(15 downto 2) when (muxctrl_reg(s)(c)=X"0C") else 
                      din(1)(5)(15 downto 2) when (muxctrl_reg(s)(c)=X"0D") else 
                      din(1)(6)(15 downto 2) when (muxctrl_reg(s)(c)=X"0E") else 
                      din(1)(7)(15 downto 2) when (muxctrl_reg(s)(c)=X"0F") else 

                      din(2)(0)(15 downto 2) when (muxctrl_reg(s)(c)=X"10") else 
                      din(2)(1)(15 downto 2) when (muxctrl_reg(s)(c)=X"11") else 
                      din(2)(2)(15 downto 2) when (muxctrl_reg(s)(c)=X"12") else 
                      din(2)(3)(15 downto 2) when (muxctrl_reg(s)(c)=X"13") else 
                      din(2)(4)(15 downto 2) when (muxctrl_reg(s)(c)=X"14") else 
                      din(2)(5)(15 downto 2) when (muxctrl_reg(s)(c)=X"15") else 
                      din(2)(6)(15 downto 2) when (muxctrl_reg(s)(c)=X"16") else 
                      din(2)(7)(15 downto 2) when (muxctrl_reg(s)(c)=X"17") else 

                      din(3)(0)(15 downto 2) when (muxctrl_reg(s)(c)=X"18") else 
                      din(3)(1)(15 downto 2) when (muxctrl_reg(s)(c)=X"19") else 
                      din(3)(2)(15 downto 2) when (muxctrl_reg(s)(c)=X"1A") else 
                      din(3)(3)(15 downto 2) when (muxctrl_reg(s)(c)=X"1B") else 
                      din(3)(4)(15 downto 2) when (muxctrl_reg(s)(c)=X"1C") else 
                      din(3)(5)(15 downto 2) when (muxctrl_reg(s)(c)=X"1D") else 
                      din(3)(6)(15 downto 2) when (muxctrl_reg(s)(c)=X"1E") else 
                      din(3)(7)(15 downto 2) when (muxctrl_reg(s)(c)=X"1F") else 

                      din(4)(0)(15 downto 2) when (muxctrl_reg(s)(c)=X"20") else 
                      din(4)(1)(15 downto 2) when (muxctrl_reg(s)(c)=X"21") else 
                      din(4)(2)(15 downto 2) when (muxctrl_reg(s)(c)=X"22") else 
                      din(4)(3)(15 downto 2) when (muxctrl_reg(s)(c)=X"23") else 
                      din(4)(4)(15 downto 2) when (muxctrl_reg(s)(c)=X"24") else 
                      din(4)(5)(15 downto 2) when (muxctrl_reg(s)(c)=X"25") else 
                      din(4)(6)(15 downto 2) when (muxctrl_reg(s)(c)=X"26") else 
                      din(4)(7)(15 downto 2) when (muxctrl_reg(s)(c)=X"27") else -- 39 decimal

                      -- virtual "sixth AFE" chip for making diagnostic patterns:

                      "11111111111111" when (muxctrl_reg(s)(c)=X"50") else -- test mode: fixed pattern = all 1s
                      "00000011111111" when (muxctrl_reg(s)(c)=X"51") else -- test mode: fixed pattern = lower 8 bits set
                      "11111100000000" when (muxctrl_reg(s)(c)=X"52") else -- test mode: fixed pattern = upper 6 bits set
                      "11000000000011" when (muxctrl_reg(s)(c)=X"53") else -- test mode: fixed pattern = two MSb and two LSb set
                      counter_reg      when (muxctrl_reg(s)(c)=X"54") else -- test mode: incrementing counter
                      rand_reg         when (muxctrl_reg(s)(c)=X"55") else -- test mode: pseudorandom generator

                      (others=>'0'); -- all other values force the associated input to zero

    end generate gen_chan;
end generate gen_send;

-- AXI-LITE slave interface logic

--reset <= not AXI_IN.ARESETN;

AXI_OUT.AWREADY <= axi_awready;
AXI_OUT.WREADY <= axi_wready;
AXI_OUT.BRESP <= axi_bresp;
AXI_OUT.BVALID <= axi_bvalid;
AXI_OUT.ARREADY <= axi_arready;
AXI_OUT.RDATA <= axi_rdata;
AXI_OUT.RRESP <= axi_rresp;
AXI_OUT.RVALID <= axi_rvalid;

-- Implement axi_awready generation
-- axi_awready is asserted for one S_AXI_ACLK clock cycle when both
-- S_AXI_AWVALID and S_AXI_WVALID are asserted. axi_awready is
-- de-asserted when reset is low.

process (AXI_IN.ACLK)
begin
  if rising_edge(AXI_IN.ACLK) then 
    if (AXI_IN.ARESETN = '0') then
      axi_awready <= '0';
      aw_en <= '1';
    else
      if (axi_awready = '0' and AXI_IN.AWVALID = '1' and AXI_IN.WVALID = '1' and aw_en = '1') then
        -- slave is ready to accept write address when
        -- there is a valid write address and write data
        -- on the write address and data bus. This design 
        -- expects no outstanding transactions. 
           axi_awready <= '1';
           aw_en <= '0';
        elsif (AXI_IN.BREADY = '1' and axi_bvalid = '1') then
           aw_en <= '1';
           axi_awready <= '0';
      else
        axi_awready <= '0';
      end if;
    end if;
  end if;
end process;

-- Implement axi_awaddr latching
-- This process is used to latch the address when both 
-- S_AXI_AWVALID and S_AXI_WVALID are valid. 

process (AXI_IN.ACLK)
begin
  if rising_edge(AXI_IN.ACLK) then 
    if (AXI_IN.ARESETN = '0') then
      axi_awaddr <= (others => '0');
    else
      if (axi_awready = '0' and AXI_IN.AWVALID = '1' and AXI_IN.WVALID = '1' and aw_en = '1') then
        -- Write Address latching
        axi_awaddr <= AXI_IN.AWADDR;
      end if;
    end if;
  end if;                   
end process; 

-- Implement axi_wready generation
-- axi_wready is asserted for one S_AXI_ACLK clock cycle when both
-- S_AXI_AWVALID and S_AXI_WVALID are asserted. axi_wready is 
-- de-asserted when reset is low. 

process (AXI_IN.ACLK)
begin
  if rising_edge(AXI_IN.ACLK) then 
    if (AXI_IN.ARESETN = '0') then
      axi_wready <= '0';
    else
      if (axi_wready = '0' and AXI_IN.WVALID = '1' and AXI_IN.AWVALID = '1' and aw_en = '1') then
          -- slave is ready to accept write data when 
          -- there is a valid write address and write data
          -- on the write address and data bus. This design 
          -- expects no outstanding transactions.           
          axi_wready <= '1';
      else
        axi_wready <= '0';
      end if;
    end if;
  end if;
end process; 

-- Implement memory mapped register select and write logic generation
-- The write data is accepted and written to memory mapped registers when
-- axi_awready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted. Write strobes are used to
-- select byte enables of slave registers while writing.
-- These registers are cleared when reset (active low) is applied.
-- Slave register write enable is asserted when valid address and data are available
-- and the slave is ready to accept the write address and write data.

reg_wren <= axi_wready and AXI_IN.WVALID and axi_awready and AXI_IN.AWVALID ;

process (AXI_IN.ACLK)
begin
  if rising_edge(AXI_IN.ACLK) then 
    if (AXI_IN.ARESETN = '0') then 

        -- here are the default muxctrl values
        muxctrl_reg(0)(0) <= X"00";  -- decimal 0 = AFE 0, ch 0
        muxctrl_reg(0)(1) <= X"01";  -- decimal 1 = AFE 0, ch 1
        muxctrl_reg(0)(2) <= X"02";
        muxctrl_reg(0)(3) <= X"03";

        muxctrl_reg(1)(0) <= X"04";
        muxctrl_reg(1)(1) <= X"05";
        muxctrl_reg(1)(2) <= X"06";
        muxctrl_reg(1)(3) <= X"07";

        muxctrl_reg(2)(0) <= X"08";
        muxctrl_reg(2)(1) <= X"09";
        muxctrl_reg(2)(2) <= X"0A";
        muxctrl_reg(2)(3) <= X"0B";

        muxctrl_reg(3)(0) <= X"0C";
        muxctrl_reg(3)(1) <= X"0D";
        muxctrl_reg(3)(2) <= X"0E";
        muxctrl_reg(3)(3) <= X"0F";

        muxctrl_reg(4)(0) <= X"10";
        muxctrl_reg(4)(1) <= X"11";
        muxctrl_reg(4)(2) <= X"12";
        muxctrl_reg(4)(3) <= X"13";

        muxctrl_reg(5)(0) <= X"14";
        muxctrl_reg(5)(1) <= X"15";
        muxctrl_reg(5)(2) <= X"16";
        muxctrl_reg(5)(3) <= X"17";

        muxctrl_reg(6)(0) <= X"18";
        muxctrl_reg(6)(1) <= X"19";
        muxctrl_reg(6)(2) <= X"1A";
        muxctrl_reg(6)(3) <= X"1B";

        muxctrl_reg(7)(0) <= X"1C";
        muxctrl_reg(7)(1) <= X"1D";
        muxctrl_reg(7)(2) <= X"1E";
        muxctrl_reg(7)(3) <= X"1F"; -- decimal 31 = afe 3, ch 7

        threshold_reg(0)(0) <= (others=>'1');  -- default threshold value is maximum
        threshold_reg(0)(1) <= (others=>'1'); 
        threshold_reg(0)(2) <= (others=>'1'); 
        threshold_reg(0)(3) <= (others=>'1'); 

        threshold_reg(1)(0) <= (others=>'1'); 
        threshold_reg(1)(1) <= (others=>'1'); 
        threshold_reg(1)(2) <= (others=>'1'); 
        threshold_reg(1)(3) <= (others=>'1'); 

        threshold_reg(2)(0) <= (others=>'1'); 
        threshold_reg(2)(1) <= (others=>'1'); 
        threshold_reg(2)(2) <= (others=>'1'); 
        threshold_reg(2)(3) <= (others=>'1'); 

        threshold_reg(3)(0) <= (others=>'1'); 
        threshold_reg(3)(1) <= (others=>'1'); 
        threshold_reg(3)(2) <= (others=>'1'); 
        threshold_reg(3)(3) <= (others=>'1'); 

        threshold_reg(4)(0) <= (others=>'1'); 
        threshold_reg(4)(1) <= (others=>'1'); 
        threshold_reg(4)(2) <= (others=>'1'); 
        threshold_reg(4)(3) <= (others=>'1'); 

        threshold_reg(5)(0) <= (others=>'1'); 
        threshold_reg(5)(1) <= (others=>'1'); 
        threshold_reg(5)(2) <= (others=>'1'); 
        threshold_reg(5)(3) <= (others=>'1'); 

        threshold_reg(6)(0) <= (others=>'1'); 
        threshold_reg(6)(1) <= (others=>'1'); 
        threshold_reg(6)(2) <= (others=>'1'); 
        threshold_reg(6)(3) <= (others=>'1'); 

        threshold_reg(7)(0) <= (others=>'1'); 
        threshold_reg(7)(1) <= (others=>'1'); 
        threshold_reg(7)(2) <= (others=>'1'); 
        threshold_reg(7)(3) <= (others=>'1'); 

    else
      if (reg_wren = '1' and AXI_IN.WSTRB = "1111") then

        -- treat all of these register WRITES as if they are full 32 bits
        -- e.g. the four write strobe bits should be high

        case ( axi_awaddr(7 downto 0) ) is

          when X"00" => muxctrl_reg(0)(0) <= AXI_IN.WDATA(7 downto 0);
          when X"04" => muxctrl_reg(0)(1) <= AXI_IN.WDATA(7 downto 0);
          when X"08" => muxctrl_reg(0)(2) <= AXI_IN.WDATA(7 downto 0);
          when X"0C" => muxctrl_reg(0)(3) <= AXI_IN.WDATA(7 downto 0);

          when X"10" => muxctrl_reg(1)(0) <= AXI_IN.WDATA(7 downto 0);
          when X"14" => muxctrl_reg(1)(1) <= AXI_IN.WDATA(7 downto 0);
          when X"18" => muxctrl_reg(1)(2) <= AXI_IN.WDATA(7 downto 0);
          when X"1C" => muxctrl_reg(1)(3) <= AXI_IN.WDATA(7 downto 0);

          when X"20" => muxctrl_reg(2)(0) <= AXI_IN.WDATA(7 downto 0);
          when X"24" => muxctrl_reg(2)(1) <= AXI_IN.WDATA(7 downto 0);
          when X"28" => muxctrl_reg(2)(2) <= AXI_IN.WDATA(7 downto 0);
          when X"2C" => muxctrl_reg(2)(3) <= AXI_IN.WDATA(7 downto 0);

          when X"30" => muxctrl_reg(3)(0) <= AXI_IN.WDATA(7 downto 0);
          when X"34" => muxctrl_reg(3)(1) <= AXI_IN.WDATA(7 downto 0);
          when X"38" => muxctrl_reg(3)(2) <= AXI_IN.WDATA(7 downto 0);
          when X"3C" => muxctrl_reg(3)(3) <= AXI_IN.WDATA(7 downto 0);

          when X"40" => muxctrl_reg(4)(0) <= AXI_IN.WDATA(7 downto 0);
          when X"44" => muxctrl_reg(4)(1) <= AXI_IN.WDATA(7 downto 0);
          when X"48" => muxctrl_reg(4)(2) <= AXI_IN.WDATA(7 downto 0);
          when X"4C" => muxctrl_reg(4)(3) <= AXI_IN.WDATA(7 downto 0);

          when X"50" => muxctrl_reg(5)(0) <= AXI_IN.WDATA(7 downto 0);
          when X"54" => muxctrl_reg(5)(1) <= AXI_IN.WDATA(7 downto 0);
          when X"58" => muxctrl_reg(5)(2) <= AXI_IN.WDATA(7 downto 0);
          when X"5C" => muxctrl_reg(5)(3) <= AXI_IN.WDATA(7 downto 0);

          when X"60" => muxctrl_reg(6)(0) <= AXI_IN.WDATA(7 downto 0);
          when X"64" => muxctrl_reg(6)(1) <= AXI_IN.WDATA(7 downto 0);
          when X"68" => muxctrl_reg(6)(2) <= AXI_IN.WDATA(7 downto 0);
          when X"6C" => muxctrl_reg(6)(3) <= AXI_IN.WDATA(7 downto 0);

          when X"70" => muxctrl_reg(7)(0) <= AXI_IN.WDATA(7 downto 0);
          when X"74" => muxctrl_reg(7)(1) <= AXI_IN.WDATA(7 downto 0);
          when X"78" => muxctrl_reg(7)(2) <= AXI_IN.WDATA(7 downto 0);
          when X"7C" => muxctrl_reg(7)(3) <= AXI_IN.WDATA(7 downto 0);

          when X"80" => threshold_reg(0)(0) <= AXI_IN.WDATA(13 downto 0);
          when X"84" => threshold_reg(0)(1) <= AXI_IN.WDATA(13 downto 0);
          when X"88" => threshold_reg(0)(2) <= AXI_IN.WDATA(13 downto 0);
          when X"8C" => threshold_reg(0)(3) <= AXI_IN.WDATA(13 downto 0);

          when X"90" => threshold_reg(1)(0) <= AXI_IN.WDATA(13 downto 0);
          when X"94" => threshold_reg(1)(1) <= AXI_IN.WDATA(13 downto 0);
          when X"98" => threshold_reg(1)(2) <= AXI_IN.WDATA(13 downto 0);
          when X"9C" => threshold_reg(1)(3) <= AXI_IN.WDATA(13 downto 0);

          when X"A0" => threshold_reg(2)(0) <= AXI_IN.WDATA(13 downto 0);
          when X"A4" => threshold_reg(2)(1) <= AXI_IN.WDATA(13 downto 0);
          when X"A8" => threshold_reg(2)(2) <= AXI_IN.WDATA(13 downto 0);
          when X"AC" => threshold_reg(2)(3) <= AXI_IN.WDATA(13 downto 0);

          when X"B0" => threshold_reg(3)(0) <= AXI_IN.WDATA(13 downto 0);
          when X"B4" => threshold_reg(3)(1) <= AXI_IN.WDATA(13 downto 0);
          when X"B8" => threshold_reg(3)(2) <= AXI_IN.WDATA(13 downto 0);
          when X"BC" => threshold_reg(3)(3) <= AXI_IN.WDATA(13 downto 0);

          when X"C0" => threshold_reg(4)(0) <= AXI_IN.WDATA(13 downto 0);
          when X"C4" => threshold_reg(4)(1) <= AXI_IN.WDATA(13 downto 0);
          when X"C8" => threshold_reg(4)(2) <= AXI_IN.WDATA(13 downto 0);
          when X"CC" => threshold_reg(4)(3) <= AXI_IN.WDATA(13 downto 0);

          when X"D0" => threshold_reg(5)(0) <= AXI_IN.WDATA(13 downto 0);
          when X"D4" => threshold_reg(5)(1) <= AXI_IN.WDATA(13 downto 0);
          when X"D8" => threshold_reg(5)(2) <= AXI_IN.WDATA(13 downto 0);
          when X"DC" => threshold_reg(5)(3) <= AXI_IN.WDATA(13 downto 0);

          when X"E0" => threshold_reg(6)(0) <= AXI_IN.WDATA(13 downto 0);
          when X"E4" => threshold_reg(6)(1) <= AXI_IN.WDATA(13 downto 0);
          when X"E8" => threshold_reg(6)(2) <= AXI_IN.WDATA(13 downto 0);
          when X"EC" => threshold_reg(6)(3) <= AXI_IN.WDATA(13 downto 0);

          when X"F0" => threshold_reg(7)(0) <= AXI_IN.WDATA(13 downto 0);
          when X"F4" => threshold_reg(7)(1) <= AXI_IN.WDATA(13 downto 0);
          when X"F8" => threshold_reg(7)(2) <= AXI_IN.WDATA(13 downto 0);
          when X"FC" => threshold_reg(7)(3) <= AXI_IN.WDATA(13 downto 0);

          when others =>
            null;
             
        end case;

      end if;
    end if;
  end if;                   
end process; 

-- Implement write response logic generation
-- The write response and response valid signals are asserted by the slave 
-- when axi_wready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted.  
-- This marks the acceptance of address and indicates the status of 
-- write transaction.

process (AXI_IN.ACLK)
begin
  if rising_edge(AXI_IN.ACLK) then 
    if AXI_IN.ARESETN = '0' then
      axi_bvalid  <= '0';
      axi_bresp   <= "00"; --need to work more on the responses
    else
      if (axi_awready = '1' and AXI_IN.AWVALID = '1' and axi_wready = '1' and AXI_IN.WVALID = '1' and axi_bvalid = '0'  ) then
        axi_bvalid <= '1';
        axi_bresp  <= "00"; 
      elsif (AXI_IN.BREADY = '1' and axi_bvalid = '1') then   --check if bready is asserted while bvalid is high)
        axi_bvalid <= '0';                                   -- (there is a possibility that bready is always asserted high)
      end if;
    end if;
  end if;                   
end process; 

-- Implement axi_arready generation
-- axi_arready is asserted for one S_AXI_ACLK clock cycle when
-- S_AXI_ARVALID is asserted. axi_awready is 
-- de-asserted when reset (active low) is asserted. 
-- The read address is also latched when S_AXI_ARVALID is 
-- asserted. axi_araddr is reset to zero on reset assertion.

process (AXI_IN.ACLK)
begin
  if rising_edge(AXI_IN.ACLK) then 
    if (AXI_IN.ARESETN) = '0' then
      axi_arready <= '0';
      axi_araddr  <= (others => '1');
    else
      if (axi_arready = '0' and AXI_IN.ARVALID = '1') then
        -- indicates that the slave has acceped the valid read address
        axi_arready <= '1';
        -- Read Address latching 
        axi_araddr  <= AXI_IN.ARADDR;           
      else
        axi_arready <= '0';
      end if;
    end if;
  end if;                   
end process; 

-- Implement axi_arvalid generation
-- axi_rvalid is asserted for one S_AXI_ACLK clock cycle when both 
-- S_AXI_ARVALID and axi_arready are asserted. The slave registers 
-- data are available on the axi_rdata bus at this instance. The 
-- assertion of axi_rvalid marks the validity of read data on the 
-- bus and axi_rresp indicates the status of read transaction.axi_rvalid 
-- is deasserted on reset (active low). axi_rresp and axi_rdata are 
-- cleared to zero on reset (active low). 

process (AXI_IN.ACLK)
begin
  if rising_edge(AXI_IN.ACLK) then
    if (AXI_IN.ARESETN = '0') then
      axi_rvalid <= '0';
      axi_rresp  <= "00";
    else
      if (axi_arready = '1' and AXI_IN.ARVALID = '1' and axi_rvalid = '0') then
        -- Valid read data is available at the read data bus
        axi_rvalid <= '1';
        axi_rresp  <= "00"; -- 'OKAY' response
      elsif (axi_rvalid = '1' and AXI_IN.RREADY = '1') then
        -- Read data is accepted by the master
        axi_rvalid <= '0';
      end if;            
    end if;
  end if;
end process;

-- Implement memory mapped register select and read logic generation
-- Slave register read enable is asserted when valid address is available
-- and the slave is ready to accept the read address.
-- reg_data_out is 32 bits

reg_rden <= axi_arready and AXI_IN.ARVALID and (not axi_rvalid) ;

reg_data_out <= (X"000000" & muxctrl_reg(0)(0)) when (axi_araddr(7 downto 0)=X"00") else
                (X"000000" & muxctrl_reg(0)(1)) when (axi_araddr(7 downto 0)=X"04") else
                (X"000000" & muxctrl_reg(0)(2)) when (axi_araddr(7 downto 0)=X"08") else
                (X"000000" & muxctrl_reg(0)(3)) when (axi_araddr(7 downto 0)=X"0C") else

                (X"000000" & muxctrl_reg(1)(0)) when (axi_araddr(7 downto 0)=X"10") else
                (X"000000" & muxctrl_reg(1)(1)) when (axi_araddr(7 downto 0)=X"14") else
                (X"000000" & muxctrl_reg(1)(2)) when (axi_araddr(7 downto 0)=X"18") else
                (X"000000" & muxctrl_reg(1)(3)) when (axi_araddr(7 downto 0)=X"1C") else

                (X"000000" & muxctrl_reg(2)(0)) when (axi_araddr(7 downto 0)=X"20") else
                (X"000000" & muxctrl_reg(2)(1)) when (axi_araddr(7 downto 0)=X"24") else
                (X"000000" & muxctrl_reg(2)(2)) when (axi_araddr(7 downto 0)=X"28") else
                (X"000000" & muxctrl_reg(2)(3)) when (axi_araddr(7 downto 0)=X"2C") else

                (X"000000" & muxctrl_reg(3)(0)) when (axi_araddr(7 downto 0)=X"30") else
                (X"000000" & muxctrl_reg(3)(1)) when (axi_araddr(7 downto 0)=X"34") else
                (X"000000" & muxctrl_reg(3)(2)) when (axi_araddr(7 downto 0)=X"38") else
                (X"000000" & muxctrl_reg(3)(3)) when (axi_araddr(7 downto 0)=X"3C") else

                (X"000000" & muxctrl_reg(4)(0)) when (axi_araddr(7 downto 0)=X"40") else
                (X"000000" & muxctrl_reg(4)(1)) when (axi_araddr(7 downto 0)=X"44") else
                (X"000000" & muxctrl_reg(4)(2)) when (axi_araddr(7 downto 0)=X"48") else
                (X"000000" & muxctrl_reg(4)(3)) when (axi_araddr(7 downto 0)=X"4C") else

                (X"000000" & muxctrl_reg(5)(0)) when (axi_araddr(7 downto 0)=X"50") else
                (X"000000" & muxctrl_reg(5)(1)) when (axi_araddr(7 downto 0)=X"54") else
                (X"000000" & muxctrl_reg(5)(2)) when (axi_araddr(7 downto 0)=X"58") else
                (X"000000" & muxctrl_reg(5)(3)) when (axi_araddr(7 downto 0)=X"5C") else

                (X"000000" & muxctrl_reg(6)(0)) when (axi_araddr(7 downto 0)=X"60") else
                (X"000000" & muxctrl_reg(6)(1)) when (axi_araddr(7 downto 0)=X"64") else
                (X"000000" & muxctrl_reg(6)(2)) when (axi_araddr(7 downto 0)=X"68") else
                (X"000000" & muxctrl_reg(6)(3)) when (axi_araddr(7 downto 0)=X"6C") else

                (X"000000" & muxctrl_reg(7)(0)) when (axi_araddr(7 downto 0)=X"70") else
                (X"000000" & muxctrl_reg(7)(1)) when (axi_araddr(7 downto 0)=X"74") else
                (X"000000" & muxctrl_reg(7)(2)) when (axi_araddr(7 downto 0)=X"78") else
                (X"000000" & muxctrl_reg(7)(3)) when (axi_araddr(7 downto 0)=X"7C") else

                (X"0000" & "00" & threshold_reg(0)(0)) when (axi_araddr(7 downto 0)=X"80") else
                (X"0000" & "00" & threshold_reg(0)(1)) when (axi_araddr(7 downto 0)=X"84") else
                (X"0000" & "00" & threshold_reg(0)(2)) when (axi_araddr(7 downto 0)=X"88") else
                (X"0000" & "00" & threshold_reg(0)(3)) when (axi_araddr(7 downto 0)=X"8C") else

                (X"0000" & "00" & threshold_reg(1)(0)) when (axi_araddr(7 downto 0)=X"90") else
                (X"0000" & "00" & threshold_reg(1)(1)) when (axi_araddr(7 downto 0)=X"94") else
                (X"0000" & "00" & threshold_reg(1)(2)) when (axi_araddr(7 downto 0)=X"98") else
                (X"0000" & "00" & threshold_reg(1)(3)) when (axi_araddr(7 downto 0)=X"9C") else

                (X"0000" & "00" & threshold_reg(2)(0)) when (axi_araddr(7 downto 0)=X"A0") else
                (X"0000" & "00" & threshold_reg(2)(1)) when (axi_araddr(7 downto 0)=X"A4") else
                (X"0000" & "00" & threshold_reg(2)(2)) when (axi_araddr(7 downto 0)=X"A8") else
                (X"0000" & "00" & threshold_reg(2)(3)) when (axi_araddr(7 downto 0)=X"AC") else

                (X"0000" & "00" & threshold_reg(3)(0)) when (axi_araddr(7 downto 0)=X"B0") else
                (X"0000" & "00" & threshold_reg(3)(1)) when (axi_araddr(7 downto 0)=X"B4") else
                (X"0000" & "00" & threshold_reg(3)(2)) when (axi_araddr(7 downto 0)=X"B8") else
                (X"0000" & "00" & threshold_reg(3)(3)) when (axi_araddr(7 downto 0)=X"BC") else

                (X"0000" & "00" & threshold_reg(4)(0)) when (axi_araddr(7 downto 0)=X"C0") else
                (X"0000" & "00" & threshold_reg(4)(1)) when (axi_araddr(7 downto 0)=X"C4") else
                (X"0000" & "00" & threshold_reg(4)(2)) when (axi_araddr(7 downto 0)=X"C8") else
                (X"0000" & "00" & threshold_reg(4)(3)) when (axi_araddr(7 downto 0)=X"CC") else

                (X"0000" & "00" & threshold_reg(5)(0)) when (axi_araddr(7 downto 0)=X"D0") else
                (X"0000" & "00" & threshold_reg(5)(1)) when (axi_araddr(7 downto 0)=X"D4") else
                (X"0000" & "00" & threshold_reg(5)(2)) when (axi_araddr(7 downto 0)=X"D8") else
                (X"0000" & "00" & threshold_reg(5)(3)) when (axi_araddr(7 downto 0)=X"DC") else

                (X"0000" & "00" & threshold_reg(6)(0)) when (axi_araddr(7 downto 0)=X"E0") else
                (X"0000" & "00" & threshold_reg(6)(1)) when (axi_araddr(7 downto 0)=X"E4") else
                (X"0000" & "00" & threshold_reg(6)(2)) when (axi_araddr(7 downto 0)=X"E8") else
                (X"0000" & "00" & threshold_reg(6)(3)) when (axi_araddr(7 downto 0)=X"EC") else

                (X"0000" & "00" & threshold_reg(7)(0)) when (axi_araddr(7 downto 0)=X"F0") else
                (X"0000" & "00" & threshold_reg(7)(1)) when (axi_araddr(7 downto 0)=X"F4") else
                (X"0000" & "00" & threshold_reg(7)(2)) when (axi_araddr(7 downto 0)=X"F8") else
                (X"0000" & "00" & threshold_reg(7)(3)) when (axi_araddr(7 downto 0)=X"FC") else

                X"00000000";

-- Output register or memory read data
process( AXI_IN.ACLK ) is
begin
  if (rising_edge (AXI_IN.ACLK)) then
    if ( AXI_IN.ARESETN = '0' ) then
      axi_rdata  <= (others => '0');
    else
      if (reg_rden = '1') then
        -- When there is a valid read address (S_AXI_ARVALID) with 
        -- acceptance of read address by the slave (axi_arready), 
        -- output the read dada 
        -- Read address mux
          axi_rdata <= reg_data_out; -- register read data
      end if;   
    end if;
  end if;
end process;

-- the streaming mode senders need to know what inputs they are connected to
-- so export this block of registers

muxctrl <= muxctrl_reg;

-- output thresholds

threshold <= threshold_reg;

end stream_input_mux_arch;
