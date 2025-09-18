-- stream_input_mux.vhd
-- For DAPHNE_MEZZ streaming sender
-- 40 input buses -> 8x4 output buses 
-- 32 8-bit registers for control, these are R/W
-- Jamieson Olsen <jamieson@fnal.gov>
--
-- base +  0 = select register for dout(0)(0)
-- base +  4 = select register for dout(0)(1)
-- base +  8 = select register for dout(0)(2)
-- base + 12 = select register for dout(0)(3)
-- base + 16 = select register for dout(1)(0)
-- base + 20 = select register for dout(1)(1)
-- ...
-- base + 124 = select register for dout(7)(3)
--
-- the streaming senders need to know what channels they are 
-- connected to, so this module also outputs the muxctrl_reg
--
-- some examples:
--   connect output(0)(3) to input(27) --> write 0x1B to address base+12
--   connect output(4)(2) to input(4) --> write 0x04 to address base+72
--   generate random pattern on output(7)(1) --> write 0x2D to address base+116
--   generate counter on output(5)(3) --> write 0x2C to address base+92
--   turn off output(3)(2) --> write 0xFF to address base+56
--
-- (scroll down in this file to see what special test modes are supported)
--
-- remember: in the streaming mode sender this module determines what data is sent
-- to the core. it does not control what the input spy buffers see!

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.daphne3_package.all;

entity stream_input_mux is
port(
    clock: in std_logic; -- 62.5MHz master clock
    din: in array_40x14_type;
    dout: out array_8x4x14_type;
    muxctrl: out array_8x4x8_type;
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

signal muxctrl_reg: array_8x4x8_type;

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

-- big old programmable mux: 40 inputs ---> 8x4 outputs
-- this is controlled by mux_ctrl, a block of 8x4 8-bit registers
-- these registers are R/W from AXI LITE interface
--
-- some examples:
-- if mux_ctrl(2)(3)=X"07" then dout(2)(3) is connected to din(7)
-- if mux_ctrl(4)(1)=X"3B" then dout(4)(1) is forced to all zeros
-- if mux_ctrl(5)(1)=X"2D" then dout(5)(1) is a pseudorandom pattern


gen_send: for s in 7 downto 0 generate
    gen_chan: for c in 3 downto 0 generate

        dout(s)(c) <= din( 0) when (muxctrl_reg(s)(c)=X"00") else -- reg values 0-39 select the input
                      din( 1) when (muxctrl_reg(s)(c)=X"01") else
                      din( 2) when (muxctrl_reg(s)(c)=X"02") else
                      din( 3) when (muxctrl_reg(s)(c)=X"03") else
                      din( 4) when (muxctrl_reg(s)(c)=X"04") else
                      din( 5) when (muxctrl_reg(s)(c)=X"05") else
                      din( 6) when (muxctrl_reg(s)(c)=X"06") else
                      din( 7) when (muxctrl_reg(s)(c)=X"07") else
                      din( 8) when (muxctrl_reg(s)(c)=X"08") else
                      din( 9) when (muxctrl_reg(s)(c)=X"09") else
                      din(10) when (muxctrl_reg(s)(c)=X"0A") else
                      din(11) when (muxctrl_reg(s)(c)=X"0B") else
                      din(12) when (muxctrl_reg(s)(c)=X"0C") else
                      din(13) when (muxctrl_reg(s)(c)=X"0D") else
                      din(14) when (muxctrl_reg(s)(c)=X"0E") else
                      din(15) when (muxctrl_reg(s)(c)=X"0F") else

                      din(16) when (muxctrl_reg(s)(c)=X"10") else
                      din(17) when (muxctrl_reg(s)(c)=X"11") else
                      din(18) when (muxctrl_reg(s)(c)=X"12") else
                      din(19) when (muxctrl_reg(s)(c)=X"13") else
                      din(20) when (muxctrl_reg(s)(c)=X"14") else
                      din(21) when (muxctrl_reg(s)(c)=X"15") else
                      din(22) when (muxctrl_reg(s)(c)=X"16") else
                      din(23) when (muxctrl_reg(s)(c)=X"17") else
                      din(24) when (muxctrl_reg(s)(c)=X"18") else
                      din(25) when (muxctrl_reg(s)(c)=X"19") else
                      din(26) when (muxctrl_reg(s)(c)=X"1A") else
                      din(27) when (muxctrl_reg(s)(c)=X"1B") else
                      din(28) when (muxctrl_reg(s)(c)=X"1C") else
                      din(29) when (muxctrl_reg(s)(c)=X"1D") else
                      din(30) when (muxctrl_reg(s)(c)=X"1E") else
                      din(31) when (muxctrl_reg(s)(c)=X"1F") else

                      din(32) when (muxctrl_reg(s)(c)=X"20") else
                      din(33) when (muxctrl_reg(s)(c)=X"21") else
                      din(34) when (muxctrl_reg(s)(c)=X"22") else
                      din(35) when (muxctrl_reg(s)(c)=X"23") else
                      din(36) when (muxctrl_reg(s)(c)=X"24") else
                      din(37) when (muxctrl_reg(s)(c)=X"25") else
                      din(38) when (muxctrl_reg(s)(c)=X"26") else
                      din(39) when (muxctrl_reg(s)(c)=X"27") else

                      "11111111111111" when (muxctrl_reg(s)(c)=X"28") else -- test mode: fixed pattern = all 1s
                      "00000011111111" when (muxctrl_reg(s)(c)=X"29") else -- test mode: fixed pattern = lower 8 bits set
                      "11111100000000" when (muxctrl_reg(s)(c)=X"2A") else -- test mode: fixed pattern = upper 6 bits set
                      "11000000000011" when (muxctrl_reg(s)(c)=X"2B") else -- test mode: fixed pattern = two MSb and two LSb set
                      counter_reg      when (muxctrl_reg(s)(c)=X"2C") else -- test mode: incrementing counter
                      rand_reg         when (muxctrl_reg(s)(c)=X"2D") else -- test mode: pseudorandom generator

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
        -- din(0) ---> dout(0)(0) 
        -- din(1) ---> dout(0)(1)
        -- din(2) ---> dout(0)(2)
        -- din(3) ---> dout(0)(3)
        -- din(4) ---> dout(1)(0)
        -- etc.

        sloop: for s in 0 to 7 loop
            cloop: for c in 0 to 3 loop
                muxctrl_reg(s)(c) <= std_logic_vector( to_unsigned(((s*4)+c),8) );
            end loop cloop;
        end loop sloop;

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

end stream_input_mux_arch;
