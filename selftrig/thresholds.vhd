-- thresholds.vhd
-- For DAPHNE self triggered sender
-- 40-10 bit registers for storing threshold values 
-- these registers are R/W from AXI-LITE 
-- Jamieson Olsen <jamieson@fnal.gov>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.daphne3_package.all;

entity thresholds is
port(
    AXI_IN: in AXILITE_INREC;
    AXI_OUT: out AXILITE_OUTREC;
    dout: out array_40x10_type
  );
end thresholds;

architecture thresholds_arch of thresholds is

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

signal threshold_reg: array_40x10_type;

begin

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

        for i in 0 to 39 loop
            threshold_reg(i) <= (others=>'1');   -- here is the default value!
        end loop;

    else
      if (reg_wren = '1' and AXI_IN.WSTRB = "1111") then

        -- treat all of these register WRITES as if they are full 32 bits
        -- e.g. the four write strobe bits should be high

        case ( axi_awaddr(7 downto 0) ) is

          when X"00" => threshold_reg(0) <= AXI_IN.WDATA(9 downto 0);
          when X"04" => threshold_reg(1) <= AXI_IN.WDATA(9 downto 0);
          when X"08" => threshold_reg(2) <= AXI_IN.WDATA(9 downto 0);
          when X"0C" => threshold_reg(3) <= AXI_IN.WDATA(9 downto 0);
          when X"10" => threshold_reg(4) <= AXI_IN.WDATA(9 downto 0);
          when X"14" => threshold_reg(5) <= AXI_IN.WDATA(9 downto 0);
          when X"18" => threshold_reg(6) <= AXI_IN.WDATA(9 downto 0);
          when X"1C" => threshold_reg(7) <= AXI_IN.WDATA(9 downto 0);
          when X"20" => threshold_reg(8) <= AXI_IN.WDATA(9 downto 0);
          when X"24" => threshold_reg(9) <= AXI_IN.WDATA(9 downto 0);
          when X"28" => threshold_reg(10) <= AXI_IN.WDATA(9 downto 0);
          when X"2C" => threshold_reg(11) <= AXI_IN.WDATA(9 downto 0);
          when X"30" => threshold_reg(12) <= AXI_IN.WDATA(9 downto 0);
          when X"34" => threshold_reg(13) <= AXI_IN.WDATA(9 downto 0);
          when X"38" => threshold_reg(14) <= AXI_IN.WDATA(9 downto 0);
          when X"3C" => threshold_reg(15) <= AXI_IN.WDATA(9 downto 0);
          when X"40" => threshold_reg(16) <= AXI_IN.WDATA(9 downto 0);
          when X"44" => threshold_reg(17) <= AXI_IN.WDATA(9 downto 0);
          when X"48" => threshold_reg(18) <= AXI_IN.WDATA(9 downto 0);
          when X"4C" => threshold_reg(19) <= AXI_IN.WDATA(9 downto 0);

          when X"50" => threshold_reg(20) <= AXI_IN.WDATA(9 downto 0);
          when X"54" => threshold_reg(21) <= AXI_IN.WDATA(9 downto 0);
          when X"58" => threshold_reg(22) <= AXI_IN.WDATA(9 downto 0);
          when X"5C" => threshold_reg(23) <= AXI_IN.WDATA(9 downto 0);
          when X"60" => threshold_reg(24) <= AXI_IN.WDATA(9 downto 0);
          when X"64" => threshold_reg(25) <= AXI_IN.WDATA(9 downto 0);
          when X"68" => threshold_reg(26) <= AXI_IN.WDATA(9 downto 0);
          when X"6C" => threshold_reg(27) <= AXI_IN.WDATA(9 downto 0);
          when X"70" => threshold_reg(28) <= AXI_IN.WDATA(9 downto 0);
          when X"74" => threshold_reg(29) <= AXI_IN.WDATA(9 downto 0);
          when X"78" => threshold_reg(30) <= AXI_IN.WDATA(9 downto 0);
          when X"7C" => threshold_reg(31) <= AXI_IN.WDATA(9 downto 0);
          when X"80" => threshold_reg(32) <= AXI_IN.WDATA(9 downto 0);
          when X"84" => threshold_reg(33) <= AXI_IN.WDATA(9 downto 0);
          when X"88" => threshold_reg(34) <= AXI_IN.WDATA(9 downto 0);
          when X"8C" => threshold_reg(35) <= AXI_IN.WDATA(9 downto 0);
          when X"90" => threshold_reg(36) <= AXI_IN.WDATA(9 downto 0);
          when X"94" => threshold_reg(37) <= AXI_IN.WDATA(9 downto 0);
          when X"98" => threshold_reg(38) <= AXI_IN.WDATA(9 downto 0);
          when X"9C" => threshold_reg(39) <= AXI_IN.WDATA(9 downto 0);

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

reg_rden <= axi_arready and AXI_IN.ARVALID and (not axi_rvalid);

reg_data_out <= ( X"00000" & "00" & threshold_reg( 0) ) when (axi_araddr(7 downto 0)=X"00") else
                ( X"00000" & "00" & threshold_reg( 1) ) when (axi_araddr(7 downto 0)=X"04") else
                ( X"00000" & "00" & threshold_reg( 2) ) when (axi_araddr(7 downto 0)=X"08") else
                ( X"00000" & "00" & threshold_reg( 3) ) when (axi_araddr(7 downto 0)=X"0C") else

                ( X"00000" & "00" & threshold_reg( 4) ) when (axi_araddr(7 downto 0)=X"10") else
                ( X"00000" & "00" & threshold_reg( 5) ) when (axi_araddr(7 downto 0)=X"14") else
                ( X"00000" & "00" & threshold_reg( 6) ) when (axi_araddr(7 downto 0)=X"18") else
                ( X"00000" & "00" & threshold_reg( 7) ) when (axi_araddr(7 downto 0)=X"1C") else

                ( X"00000" & "00" & threshold_reg( 8) ) when (axi_araddr(7 downto 0)=X"20") else
                ( X"00000" & "00" & threshold_reg( 9) ) when (axi_araddr(7 downto 0)=X"24") else
                ( X"00000" & "00" & threshold_reg(10) ) when (axi_araddr(7 downto 0)=X"28") else
                ( X"00000" & "00" & threshold_reg(11) ) when (axi_araddr(7 downto 0)=X"2C") else

                ( X"00000" & "00" & threshold_reg(12) ) when (axi_araddr(7 downto 0)=X"30") else
                ( X"00000" & "00" & threshold_reg(13) ) when (axi_araddr(7 downto 0)=X"34") else
                ( X"00000" & "00" & threshold_reg(14) ) when (axi_araddr(7 downto 0)=X"38") else
                ( X"00000" & "00" & threshold_reg(15) ) when (axi_araddr(7 downto 0)=X"3C") else

                ( X"00000" & "00" & threshold_reg(16) ) when (axi_araddr(7 downto 0)=X"40") else
                ( X"00000" & "00" & threshold_reg(17) ) when (axi_araddr(7 downto 0)=X"44") else
                ( X"00000" & "00" & threshold_reg(18) ) when (axi_araddr(7 downto 0)=X"48") else
                ( X"00000" & "00" & threshold_reg(19) ) when (axi_araddr(7 downto 0)=X"4C") else

                ( X"00000" & "00" & threshold_reg(20) ) when (axi_araddr(7 downto 0)=X"50") else
                ( X"00000" & "00" & threshold_reg(21) ) when (axi_araddr(7 downto 0)=X"54") else
                ( X"00000" & "00" & threshold_reg(22) ) when (axi_araddr(7 downto 0)=X"58") else
                ( X"00000" & "00" & threshold_reg(23) ) when (axi_araddr(7 downto 0)=X"5C") else

                ( X"00000" & "00" & threshold_reg(24) ) when (axi_araddr(7 downto 0)=X"60") else
                ( X"00000" & "00" & threshold_reg(25) ) when (axi_araddr(7 downto 0)=X"64") else
                ( X"00000" & "00" & threshold_reg(26) ) when (axi_araddr(7 downto 0)=X"68") else
                ( X"00000" & "00" & threshold_reg(27) ) when (axi_araddr(7 downto 0)=X"6C") else

                ( X"00000" & "00" & threshold_reg(28) ) when (axi_araddr(7 downto 0)=X"70") else
                ( X"00000" & "00" & threshold_reg(29) ) when (axi_araddr(7 downto 0)=X"74") else
                ( X"00000" & "00" & threshold_reg(30) ) when (axi_araddr(7 downto 0)=X"78") else
                ( X"00000" & "00" & threshold_reg(31) ) when (axi_araddr(7 downto 0)=X"7C") else

                ( X"00000" & "00" & threshold_reg(32) ) when (axi_araddr(7 downto 0)=X"80") else
                ( X"00000" & "00" & threshold_reg(33) ) when (axi_araddr(7 downto 0)=X"84") else
                ( X"00000" & "00" & threshold_reg(34) ) when (axi_araddr(7 downto 0)=X"88") else
                ( X"00000" & "00" & threshold_reg(35) ) when (axi_araddr(7 downto 0)=X"8C") else

                ( X"00000" & "00" & threshold_reg(36) ) when (axi_araddr(7 downto 0)=X"90") else
                ( X"00000" & "00" & threshold_reg(37) ) when (axi_araddr(7 downto 0)=X"94") else
                ( X"00000" & "00" & threshold_reg(38) ) when (axi_araddr(7 downto 0)=X"98") else
                ( X"00000" & "00" & threshold_reg(39) ) when (axi_araddr(7 downto 0)=X"9C") else

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

dout <= threshold_reg;

end thresholds_arch;
