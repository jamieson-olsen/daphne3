-- selftrig_core.vhd
-- DAPHNE core logic, top level, self triggered mode sender
-- TWO 20:1 self triggered senders
-- AXI-LITE interface for reading diagnostic counters and reading/writing threshold values
-- Jamieson Olsen <jamieson@fnal.gov>

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.daphne3_package.all;

entity selftrig_core is
generic( baseline_runlength: integer := 256 ); -- options 32, 64, 128, or 256
port(
    clock: in std_logic; -- 62.5 MHz
    reset: in std_logic;
    version: in std_logic_vector(3 downto 0);
    timestamp: in std_logic_vector(63 downto 0);
    forcetrig: in std_logic;
	din: in array_5x9x16_type; 
    dout: out array_2x64_type;
    valid: out std_logic_vector(1 downto 0);
    last:  out std_logic_vector(1 downto 0);
    AXI_IN: in AXILITE_INREC;
    AXI_OUT: out AXILITE_OUTREC
);
end selftrig_core;

architecture selftrig_core_arch of selftrig_core is

component st20_top
generic(
    baseline_runlength: integer := 256; -- options 32, 64, 128, or 256
    start_channel_number: integer := 0 -- 0 or 20
); 
port(
    thresholds: in array_20x10_type;
    version: in std_logic_vector(3 downto 0);
    clock: in std_logic;
    reset: in std_logic;
    timestamp: in std_logic_vector(63 downto 0);
    forcetrig: in std_logic;
	din: in array_20x14_type;
    record_count: out array_20x64_type;
    full_count: out array_20x64_type;
    busy_count: out array_20x64_type;
    dout: out std_logic_vector(63 downto 0); -- output to single channel 10G sender
    valid: out std_logic;
    last: out std_logic
);
end component;

signal din_lower, din_upper: array_20x14_type;

signal threshold_lower, threshold_upper: array_20x10_type;
signal threshold: array_40x10_type;

signal record_count_lower, full_count_lower, busy_count_lower: array_20x64_type;
signal record_count_upper, full_count_upper, busy_count_upper: array_20x64_type;
signal record_count, full_count, busy_count: array_40x64_type;

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

begin

-- break up the 5x9x16 array into upper/lower 20x14 arrays
-- note when truncating from 16->14 bits discard the two LSbs
-- do not take afe channel 8 as that is the frame marker

din_lower( 0) <= din(0)(0)(15 downto 2);
din_lower( 1) <= din(0)(1)(15 downto 2);
din_lower( 2) <= din(0)(2)(15 downto 2);
din_lower( 3) <= din(0)(3)(15 downto 2);
din_lower( 4) <= din(0)(4)(15 downto 2);
din_lower( 5) <= din(0)(5)(15 downto 2);
din_lower( 6) <= din(0)(6)(15 downto 2);
din_lower( 7) <= din(0)(7)(15 downto 2);
din_lower( 8) <= din(1)(0)(15 downto 2);
din_lower( 9) <= din(1)(1)(15 downto 2);
din_lower(10) <= din(1)(2)(15 downto 2);
din_lower(11) <= din(1)(3)(15 downto 2);
din_lower(12) <= din(1)(4)(15 downto 2);
din_lower(13) <= din(1)(5)(15 downto 2);
din_lower(14) <= din(1)(6)(15 downto 2);
din_lower(15) <= din(1)(7)(15 downto 2);
din_lower(16) <= din(2)(0)(15 downto 2);
din_lower(17) <= din(2)(1)(15 downto 2);
din_lower(18) <= din(2)(2)(15 downto 2);
din_lower(19) <= din(2)(3)(15 downto 2);

din_upper( 0) <= din(2)(4)(15 downto 2);
din_upper( 1) <= din(2)(5)(15 downto 2);
din_upper( 2) <= din(2)(6)(15 downto 2);
din_upper( 3) <= din(2)(7)(15 downto 2);
din_upper( 4) <= din(3)(0)(15 downto 2);
din_upper( 5) <= din(3)(1)(15 downto 2);
din_upper( 6) <= din(3)(2)(15 downto 2);
din_upper( 7) <= din(3)(3)(15 downto 2);
din_upper( 8) <= din(3)(4)(15 downto 2);
din_upper( 9) <= din(3)(5)(15 downto 2);
din_upper(10) <= din(3)(6)(15 downto 2);
din_upper(11) <= din(3)(7)(15 downto 2);
din_upper(12) <= din(4)(0)(15 downto 2);
din_upper(13) <= din(4)(1)(15 downto 2);
din_upper(14) <= din(4)(2)(15 downto 2);
din_upper(15) <= din(4)(3)(15 downto 2);
din_upper(16) <= din(4)(4)(15 downto 2);
din_upper(17) <= din(4)(5)(15 downto 2);
din_upper(18) <= din(4)(6)(15 downto 2);
din_upper(19) <= din(4)(7)(15 downto 2);

gen20stuff: for i in 19 downto 0 generate
    threshold_lower(i) <= threshold(i);
    threshold_upper(i) <= threshold(i+20);   
    record_count(i) <= record_count_lower(i);
    record_count(i+20) <= record_count_upper(i);
    busy_count(i) <= busy_count_lower(i);
    busy_count(i+20) <= busy_count_upper(i);
    full_count(i) <= full_count_lower(i);
    full_count(i+20) <= full_count_upper(i);
end generate gen20stuff;

-- lower 20 channel sender

st20_lower_inst: st20_top
generic map( baseline_runlength => baseline_runlength, start_channel_number => 0 )
port map(
    thresholds => threshold_lower,
    version => version,
    clock => clock,
    reset => reset,
    timestamp => timestamp,
    forcetrig => forcetrig,
	din => din_lower,
    record_count => record_count_lower,
    full_count => full_count_lower,
    busy_count => busy_count_lower,
    dout => dout(0),
    valid => valid(0),
    last => last(0)
);

-- upper 20 channel sender

st20_upper_inst: st20_top
generic map( baseline_runlength => baseline_runlength, start_channel_number => 20 ) 
port map(
    thresholds => threshold_upper,
    version => version,
    clock => clock,
    reset => reset,
    timestamp => timestamp,
    forcetrig => forcetrig,
	din => din_upper,
    record_count => record_count_upper,
    full_count => full_count_upper,
    busy_count => busy_count_upper,
    dout => dout(1),
    valid => valid(1),
    last => last(1)
);

-- begin AXI-LITE glue logic for diagnostic counters and thresholds

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
            threshold(i) <= (others=>'1');   -- here is the default value!
        end loop;

    else
      if (reg_wren = '1' and AXI_IN.WSTRB = "1111") then

        -- treat all of these register WRITES as if they are full 32 bits
        -- e.g. the four write strobe bits should be high

        case ( axi_awaddr(11 downto 0) ) is

          when X"000" => threshold(0) <= AXI_IN.WDATA(9 downto 0);
          when X"020" => threshold(1) <= AXI_IN.WDATA(9 downto 0);
          when X"040" => threshold(2) <= AXI_IN.WDATA(9 downto 0);
          when X"060" => threshold(3) <= AXI_IN.WDATA(9 downto 0);
          when X"080" => threshold(4) <= AXI_IN.WDATA(9 downto 0);
          when X"0A0" => threshold(5) <= AXI_IN.WDATA(9 downto 0);
          when X"0C0" => threshold(6) <= AXI_IN.WDATA(9 downto 0);
          when X"0E0" => threshold(7) <= AXI_IN.WDATA(9 downto 0);
          when X"100" => threshold(8) <= AXI_IN.WDATA(9 downto 0);
          when X"120" => threshold(9) <= AXI_IN.WDATA(9 downto 0);
          when X"140" => threshold(10) <= AXI_IN.WDATA(9 downto 0);
          when X"160" => threshold(11) <= AXI_IN.WDATA(9 downto 0);
          when X"180" => threshold(12) <= AXI_IN.WDATA(9 downto 0);
          when X"1A0" => threshold(13) <= AXI_IN.WDATA(9 downto 0);
          when X"1C0" => threshold(14) <= AXI_IN.WDATA(9 downto 0);
          when X"1E0" => threshold(15) <= AXI_IN.WDATA(9 downto 0);
          when X"200" => threshold(16) <= AXI_IN.WDATA(9 downto 0);
          when X"220" => threshold(17) <= AXI_IN.WDATA(9 downto 0);
          when X"240" => threshold(18) <= AXI_IN.WDATA(9 downto 0);
          when X"260" => threshold(19) <= AXI_IN.WDATA(9 downto 0);

          when X"280" => threshold(20) <= AXI_IN.WDATA(9 downto 0);
          when X"2A0" => threshold(21) <= AXI_IN.WDATA(9 downto 0);
          when X"2C0" => threshold(22) <= AXI_IN.WDATA(9 downto 0);
          when X"2E0" => threshold(23) <= AXI_IN.WDATA(9 downto 0);
          when X"300" => threshold(24) <= AXI_IN.WDATA(9 downto 0);
          when X"320" => threshold(25) <= AXI_IN.WDATA(9 downto 0);
          when X"340" => threshold(26) <= AXI_IN.WDATA(9 downto 0);
          when X"360" => threshold(27) <= AXI_IN.WDATA(9 downto 0);
          when X"380" => threshold(28) <= AXI_IN.WDATA(9 downto 0);
          when X"3A0" => threshold(29) <= AXI_IN.WDATA(9 downto 0);
          when X"3C0" => threshold(30) <= AXI_IN.WDATA(9 downto 0);
          when X"3E0" => threshold(31) <= AXI_IN.WDATA(9 downto 0);
          when X"400" => threshold(32) <= AXI_IN.WDATA(9 downto 0);
          when X"420" => threshold(33) <= AXI_IN.WDATA(9 downto 0);
          when X"440" => threshold(34) <= AXI_IN.WDATA(9 downto 0);
          when X"460" => threshold(35) <= AXI_IN.WDATA(9 downto 0);
          when X"480" => threshold(36) <= AXI_IN.WDATA(9 downto 0);
          when X"4A0" => threshold(37) <= AXI_IN.WDATA(9 downto 0);
          when X"4C0" => threshold(38) <= AXI_IN.WDATA(9 downto 0);
          when X"4E0" => threshold(39) <= AXI_IN.WDATA(9 downto 0);

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

reg_data_out <= 
                ("0000000000000000000000" & threshold(0)) when (axi_araddr(11 downto 0)=X"000") else
                (record_count(0)(31 downto 0)) when (axi_araddr(11 downto 0)=X"004") else
                (record_count(0)(63 downto 32)) when (axi_araddr(11 downto 0)=X"008") else
                (busy_count(0)(31 downto 0)) when (axi_araddr(11 downto 0)=X"00C") else
                (busy_count(0)(63 downto 32)) when (axi_araddr(11 downto 0)=X"010") else
                (full_count(0)(31 downto 0)) when (axi_araddr(11 downto 0)=X"014") else
                (full_count(0)(63 downto 32)) when (axi_araddr(11 downto 0)=X"018") else
                
                ("0000000000000000000000" & threshold(1)) when (axi_araddr(11 downto 0)=X"020") else
                (record_count(1)(31 downto 0)) when (axi_araddr(11 downto 0)=X"024") else
                (record_count(1)(63 downto 32)) when (axi_araddr(11 downto 0)=X"028") else
                (busy_count(1)(31 downto 0)) when (axi_araddr(11 downto 0)=X"02C") else
                (busy_count(1)(63 downto 32)) when (axi_araddr(11 downto 0)=X"030") else
                (full_count(1)(31 downto 0)) when (axi_araddr(11 downto 0)=X"034") else
                (full_count(1)(63 downto 32)) when (axi_araddr(11 downto 0)=X"038") else
                
                ("0000000000000000000000" & threshold(2)) when (axi_araddr(11 downto 0)=X"040") else
                (record_count(2)(31 downto 0)) when (axi_araddr(11 downto 0)=X"044") else
                (record_count(2)(63 downto 32)) when (axi_araddr(11 downto 0)=X"048") else
                (busy_count(2)(31 downto 0)) when (axi_araddr(11 downto 0)=X"04C") else
                (busy_count(2)(63 downto 32)) when (axi_araddr(11 downto 0)=X"050") else
                (full_count(2)(31 downto 0)) when (axi_araddr(11 downto 0)=X"054") else
                (full_count(2)(63 downto 32)) when (axi_araddr(11 downto 0)=X"058") else
                
                ("0000000000000000000000" & threshold(3)) when (axi_araddr(11 downto 0)=X"060") else
                (record_count(3)(31 downto 0)) when (axi_araddr(11 downto 0)=X"064") else
                (record_count(3)(63 downto 32)) when (axi_araddr(11 downto 0)=X"068") else
                (busy_count(3)(31 downto 0)) when (axi_araddr(11 downto 0)=X"06C") else
                (busy_count(3)(63 downto 32)) when (axi_araddr(11 downto 0)=X"070") else
                (full_count(3)(31 downto 0)) when (axi_araddr(11 downto 0)=X"074") else
                (full_count(3)(63 downto 32)) when (axi_araddr(11 downto 0)=X"078") else
                
                ("0000000000000000000000" & threshold(4)) when (axi_araddr(11 downto 0)=X"080") else
                (record_count(4)(31 downto 0)) when (axi_araddr(11 downto 0)=X"084") else
                (record_count(4)(63 downto 32)) when (axi_araddr(11 downto 0)=X"088") else
                (busy_count(4)(31 downto 0)) when (axi_araddr(11 downto 0)=X"08C") else
                (busy_count(4)(63 downto 32)) when (axi_araddr(11 downto 0)=X"090") else
                (full_count(4)(31 downto 0)) when (axi_araddr(11 downto 0)=X"094") else
                (full_count(4)(63 downto 32)) when (axi_araddr(11 downto 0)=X"098") else
                
                ("0000000000000000000000" & threshold(5)) when (axi_araddr(11 downto 0)=X"0A0") else
                (record_count(5)(31 downto 0)) when (axi_araddr(11 downto 0)=X"0A4") else
                (record_count(5)(63 downto 32)) when (axi_araddr(11 downto 0)=X"0A8") else
                (busy_count(5)(31 downto 0)) when (axi_araddr(11 downto 0)=X"0AC") else
                (busy_count(5)(63 downto 32)) when (axi_araddr(11 downto 0)=X"0B0") else
                (full_count(5)(31 downto 0)) when (axi_araddr(11 downto 0)=X"0B4") else
                (full_count(5)(63 downto 32)) when (axi_araddr(11 downto 0)=X"0B8") else
                
                ("0000000000000000000000" & threshold(6)) when (axi_araddr(11 downto 0)=X"0C0") else
                (record_count(6)(31 downto 0)) when (axi_araddr(11 downto 0)=X"0C4") else
                (record_count(6)(63 downto 32)) when (axi_araddr(11 downto 0)=X"0C8") else
                (busy_count(6)(31 downto 0)) when (axi_araddr(11 downto 0)=X"0CC") else
                (busy_count(6)(63 downto 32)) when (axi_araddr(11 downto 0)=X"0D0") else
                (full_count(6)(31 downto 0)) when (axi_araddr(11 downto 0)=X"0D4") else
                (full_count(6)(63 downto 32)) when (axi_araddr(11 downto 0)=X"0D8") else
                
                ("0000000000000000000000" & threshold(7)) when (axi_araddr(11 downto 0)=X"0E0") else
                (record_count(7)(31 downto 0)) when (axi_araddr(11 downto 0)=X"0E4") else
                (record_count(7)(63 downto 32)) when (axi_araddr(11 downto 0)=X"0E8") else
                (busy_count(7)(31 downto 0)) when (axi_araddr(11 downto 0)=X"0EC") else
                (busy_count(7)(63 downto 32)) when (axi_araddr(11 downto 0)=X"0F0") else
                (full_count(7)(31 downto 0)) when (axi_araddr(11 downto 0)=X"0F4") else
                (full_count(7)(63 downto 32)) when (axi_araddr(11 downto 0)=X"0F8") else
                
                ("0000000000000000000000" & threshold(8)) when (axi_araddr(11 downto 0)=X"100") else
                (record_count(8)(31 downto 0)) when (axi_araddr(11 downto 0)=X"104") else
                (record_count(8)(63 downto 32)) when (axi_araddr(11 downto 0)=X"108") else
                (busy_count(8)(31 downto 0)) when (axi_araddr(11 downto 0)=X"10C") else
                (busy_count(8)(63 downto 32)) when (axi_araddr(11 downto 0)=X"110") else
                (full_count(8)(31 downto 0)) when (axi_araddr(11 downto 0)=X"114") else
                (full_count(8)(63 downto 32)) when (axi_araddr(11 downto 0)=X"118") else
                
                ("0000000000000000000000" & threshold(9)) when (axi_araddr(11 downto 0)=X"120") else
                (record_count(9)(31 downto 0)) when (axi_araddr(11 downto 0)=X"124") else
                (record_count(9)(63 downto 32)) when (axi_araddr(11 downto 0)=X"128") else
                (busy_count(9)(31 downto 0)) when (axi_araddr(11 downto 0)=X"12C") else
                (busy_count(9)(63 downto 32)) when (axi_araddr(11 downto 0)=X"130") else
                (full_count(9)(31 downto 0)) when (axi_araddr(11 downto 0)=X"134") else
                (full_count(9)(63 downto 32)) when (axi_araddr(11 downto 0)=X"138") else
                
                ("0000000000000000000000" & threshold(10)) when (axi_araddr(11 downto 0)=X"140") else
                (record_count(10)(31 downto 0)) when (axi_araddr(11 downto 0)=X"144") else
                (record_count(10)(63 downto 32)) when (axi_araddr(11 downto 0)=X"148") else
                (busy_count(10)(31 downto 0)) when (axi_araddr(11 downto 0)=X"14C") else
                (busy_count(10)(63 downto 32)) when (axi_araddr(11 downto 0)=X"150") else
                (full_count(10)(31 downto 0)) when (axi_araddr(11 downto 0)=X"154") else
                (full_count(10)(63 downto 32)) when (axi_araddr(11 downto 0)=X"158") else
                
                ("0000000000000000000000" & threshold(11)) when (axi_araddr(11 downto 0)=X"160") else
                (record_count(11)(31 downto 0)) when (axi_araddr(11 downto 0)=X"164") else
                (record_count(11)(63 downto 32)) when (axi_araddr(11 downto 0)=X"168") else
                (busy_count(11)(31 downto 0)) when (axi_araddr(11 downto 0)=X"16C") else
                (busy_count(11)(63 downto 32)) when (axi_araddr(11 downto 0)=X"170") else
                (full_count(11)(31 downto 0)) when (axi_araddr(11 downto 0)=X"174") else
                (full_count(11)(63 downto 32)) when (axi_araddr(11 downto 0)=X"178") else
                
                ("0000000000000000000000" & threshold(12)) when (axi_araddr(11 downto 0)=X"180") else
                (record_count(12)(31 downto 0)) when (axi_araddr(11 downto 0)=X"184") else
                (record_count(12)(63 downto 32)) when (axi_araddr(11 downto 0)=X"188") else
                (busy_count(12)(31 downto 0)) when (axi_araddr(11 downto 0)=X"18C") else
                (busy_count(12)(63 downto 32)) when (axi_araddr(11 downto 0)=X"190") else
                (full_count(12)(31 downto 0)) when (axi_araddr(11 downto 0)=X"194") else
                (full_count(12)(63 downto 32)) when (axi_araddr(11 downto 0)=X"198") else
                
                ("0000000000000000000000" & threshold(13)) when (axi_araddr(11 downto 0)=X"1A0") else
                (record_count(13)(31 downto 0)) when (axi_araddr(11 downto 0)=X"1A4") else
                (record_count(13)(63 downto 32)) when (axi_araddr(11 downto 0)=X"1A8") else
                (busy_count(13)(31 downto 0)) when (axi_araddr(11 downto 0)=X"1AC") else
                (busy_count(13)(63 downto 32)) when (axi_araddr(11 downto 0)=X"1B0") else
                (full_count(13)(31 downto 0)) when (axi_araddr(11 downto 0)=X"1B4") else
                (full_count(13)(63 downto 32)) when (axi_araddr(11 downto 0)=X"1B8") else
                
                ("0000000000000000000000" & threshold(14)) when (axi_araddr(11 downto 0)=X"1C0") else
                (record_count(14)(31 downto 0)) when (axi_araddr(11 downto 0)=X"1C4") else
                (record_count(14)(63 downto 32)) when (axi_araddr(11 downto 0)=X"1C8") else
                (busy_count(14)(31 downto 0)) when (axi_araddr(11 downto 0)=X"1CC") else
                (busy_count(14)(63 downto 32)) when (axi_araddr(11 downto 0)=X"1D0") else
                (full_count(14)(31 downto 0)) when (axi_araddr(11 downto 0)=X"1D4") else
                (full_count(14)(63 downto 32)) when (axi_araddr(11 downto 0)=X"1D8") else
                
                ("0000000000000000000000" & threshold(15)) when (axi_araddr(11 downto 0)=X"1E0") else
                (record_count(15)(31 downto 0)) when (axi_araddr(11 downto 0)=X"1E4") else
                (record_count(15)(63 downto 32)) when (axi_araddr(11 downto 0)=X"1E8") else
                (busy_count(15)(31 downto 0)) when (axi_araddr(11 downto 0)=X"1EC") else
                (busy_count(15)(63 downto 32)) when (axi_araddr(11 downto 0)=X"1F0") else
                (full_count(15)(31 downto 0)) when (axi_araddr(11 downto 0)=X"1F4") else
                (full_count(15)(63 downto 32)) when (axi_araddr(11 downto 0)=X"1F8") else
                
                ("0000000000000000000000" & threshold(16)) when (axi_araddr(11 downto 0)=X"200") else
                (record_count(16)(31 downto 0)) when (axi_araddr(11 downto 0)=X"204") else
                (record_count(16)(63 downto 32)) when (axi_araddr(11 downto 0)=X"208") else
                (busy_count(16)(31 downto 0)) when (axi_araddr(11 downto 0)=X"20C") else
                (busy_count(16)(63 downto 32)) when (axi_araddr(11 downto 0)=X"210") else
                (full_count(16)(31 downto 0)) when (axi_araddr(11 downto 0)=X"214") else
                (full_count(16)(63 downto 32)) when (axi_araddr(11 downto 0)=X"218") else
                
                ("0000000000000000000000" & threshold(17)) when (axi_araddr(11 downto 0)=X"220") else
                (record_count(17)(31 downto 0)) when (axi_araddr(11 downto 0)=X"224") else
                (record_count(17)(63 downto 32)) when (axi_araddr(11 downto 0)=X"228") else
                (busy_count(17)(31 downto 0)) when (axi_araddr(11 downto 0)=X"22C") else
                (busy_count(17)(63 downto 32)) when (axi_araddr(11 downto 0)=X"230") else
                (full_count(17)(31 downto 0)) when (axi_araddr(11 downto 0)=X"234") else
                (full_count(17)(63 downto 32)) when (axi_araddr(11 downto 0)=X"238") else
                
                ("0000000000000000000000" & threshold(18)) when (axi_araddr(11 downto 0)=X"240") else
                (record_count(18)(31 downto 0)) when (axi_araddr(11 downto 0)=X"244") else
                (record_count(18)(63 downto 32)) when (axi_araddr(11 downto 0)=X"248") else
                (busy_count(18)(31 downto 0)) when (axi_araddr(11 downto 0)=X"24C") else
                (busy_count(18)(63 downto 32)) when (axi_araddr(11 downto 0)=X"250") else
                (full_count(18)(31 downto 0)) when (axi_araddr(11 downto 0)=X"254") else
                (full_count(18)(63 downto 32)) when (axi_araddr(11 downto 0)=X"258") else
                
                ("0000000000000000000000" & threshold(19)) when (axi_araddr(11 downto 0)=X"260") else
                (record_count(19)(31 downto 0)) when (axi_araddr(11 downto 0)=X"264") else
                (record_count(19)(63 downto 32)) when (axi_araddr(11 downto 0)=X"268") else
                (busy_count(19)(31 downto 0)) when (axi_araddr(11 downto 0)=X"26C") else
                (busy_count(19)(63 downto 32)) when (axi_araddr(11 downto 0)=X"270") else
                (full_count(19)(31 downto 0)) when (axi_araddr(11 downto 0)=X"274") else
                (full_count(19)(63 downto 32)) when (axi_araddr(11 downto 0)=X"278") else
                
                ("0000000000000000000000" & threshold(20)) when (axi_araddr(11 downto 0)=X"280") else
                (record_count(20)(31 downto 0)) when (axi_araddr(11 downto 0)=X"284") else
                (record_count(20)(63 downto 32)) when (axi_araddr(11 downto 0)=X"288") else
                (busy_count(20)(31 downto 0)) when (axi_araddr(11 downto 0)=X"28C") else
                (busy_count(20)(63 downto 32)) when (axi_araddr(11 downto 0)=X"290") else
                (full_count(20)(31 downto 0)) when (axi_araddr(11 downto 0)=X"294") else
                (full_count(20)(63 downto 32)) when (axi_araddr(11 downto 0)=X"298") else
                
                ("0000000000000000000000" & threshold(21)) when (axi_araddr(11 downto 0)=X"2A0") else
                (record_count(21)(31 downto 0)) when (axi_araddr(11 downto 0)=X"2A4") else
                (record_count(21)(63 downto 32)) when (axi_araddr(11 downto 0)=X"2A8") else
                (busy_count(21)(31 downto 0)) when (axi_araddr(11 downto 0)=X"2AC") else
                (busy_count(21)(63 downto 32)) when (axi_araddr(11 downto 0)=X"2B0") else
                (full_count(21)(31 downto 0)) when (axi_araddr(11 downto 0)=X"2B4") else
                (full_count(21)(63 downto 32)) when (axi_araddr(11 downto 0)=X"2B8") else
                
                ("0000000000000000000000" & threshold(22)) when (axi_araddr(11 downto 0)=X"2C0") else
                (record_count(22)(31 downto 0)) when (axi_araddr(11 downto 0)=X"2C4") else
                (record_count(22)(63 downto 32)) when (axi_araddr(11 downto 0)=X"2C8") else
                (busy_count(22)(31 downto 0)) when (axi_araddr(11 downto 0)=X"2CC") else
                (busy_count(22)(63 downto 32)) when (axi_araddr(11 downto 0)=X"2D0") else
                (full_count(22)(31 downto 0)) when (axi_araddr(11 downto 0)=X"2D4") else
                (full_count(22)(63 downto 32)) when (axi_araddr(11 downto 0)=X"2D8") else
                
                ("0000000000000000000000" & threshold(23)) when (axi_araddr(11 downto 0)=X"2E0") else
                (record_count(23)(31 downto 0)) when (axi_araddr(11 downto 0)=X"2E4") else
                (record_count(23)(63 downto 32)) when (axi_araddr(11 downto 0)=X"2E8") else
                (busy_count(23)(31 downto 0)) when (axi_araddr(11 downto 0)=X"2EC") else
                (busy_count(23)(63 downto 32)) when (axi_araddr(11 downto 0)=X"2F0") else
                (full_count(23)(31 downto 0)) when (axi_araddr(11 downto 0)=X"2F4") else
                (full_count(23)(63 downto 32)) when (axi_araddr(11 downto 0)=X"2F8") else
                
                ("0000000000000000000000" & threshold(24)) when (axi_araddr(11 downto 0)=X"300") else
                (record_count(24)(31 downto 0)) when (axi_araddr(11 downto 0)=X"304") else
                (record_count(24)(63 downto 32)) when (axi_araddr(11 downto 0)=X"308") else
                (busy_count(24)(31 downto 0)) when (axi_araddr(11 downto 0)=X"30C") else
                (busy_count(24)(63 downto 32)) when (axi_araddr(11 downto 0)=X"310") else
                (full_count(24)(31 downto 0)) when (axi_araddr(11 downto 0)=X"314") else
                (full_count(24)(63 downto 32)) when (axi_araddr(11 downto 0)=X"318") else
                
                ("0000000000000000000000" & threshold(25)) when (axi_araddr(11 downto 0)=X"320") else
                (record_count(25)(31 downto 0)) when (axi_araddr(11 downto 0)=X"324") else
                (record_count(25)(63 downto 32)) when (axi_araddr(11 downto 0)=X"328") else
                (busy_count(25)(31 downto 0)) when (axi_araddr(11 downto 0)=X"32C") else
                (busy_count(25)(63 downto 32)) when (axi_araddr(11 downto 0)=X"330") else
                (full_count(25)(31 downto 0)) when (axi_araddr(11 downto 0)=X"334") else
                (full_count(25)(63 downto 32)) when (axi_araddr(11 downto 0)=X"338") else
                
                ("0000000000000000000000" & threshold(26)) when (axi_araddr(11 downto 0)=X"340") else
                (record_count(26)(31 downto 0)) when (axi_araddr(11 downto 0)=X"344") else
                (record_count(26)(63 downto 32)) when (axi_araddr(11 downto 0)=X"348") else
                (busy_count(26)(31 downto 0)) when (axi_araddr(11 downto 0)=X"34C") else
                (busy_count(26)(63 downto 32)) when (axi_araddr(11 downto 0)=X"350") else
                (full_count(26)(31 downto 0)) when (axi_araddr(11 downto 0)=X"354") else
                (full_count(26)(63 downto 32)) when (axi_araddr(11 downto 0)=X"358") else
                
                ("0000000000000000000000" & threshold(27)) when (axi_araddr(11 downto 0)=X"360") else
                (record_count(27)(31 downto 0)) when (axi_araddr(11 downto 0)=X"364") else
                (record_count(27)(63 downto 32)) when (axi_araddr(11 downto 0)=X"368") else
                (busy_count(27)(31 downto 0)) when (axi_araddr(11 downto 0)=X"36C") else
                (busy_count(27)(63 downto 32)) when (axi_araddr(11 downto 0)=X"370") else
                (full_count(27)(31 downto 0)) when (axi_araddr(11 downto 0)=X"374") else
                (full_count(27)(63 downto 32)) when (axi_araddr(11 downto 0)=X"378") else
                
                ("0000000000000000000000" & threshold(28)) when (axi_araddr(11 downto 0)=X"380") else
                (record_count(28)(31 downto 0)) when (axi_araddr(11 downto 0)=X"384") else
                (record_count(28)(63 downto 32)) when (axi_araddr(11 downto 0)=X"388") else
                (busy_count(28)(31 downto 0)) when (axi_araddr(11 downto 0)=X"38C") else
                (busy_count(28)(63 downto 32)) when (axi_araddr(11 downto 0)=X"390") else
                (full_count(28)(31 downto 0)) when (axi_araddr(11 downto 0)=X"394") else
                (full_count(28)(63 downto 32)) when (axi_araddr(11 downto 0)=X"398") else
                
                ("0000000000000000000000" & threshold(29)) when (axi_araddr(11 downto 0)=X"3A0") else
                (record_count(29)(31 downto 0)) when (axi_araddr(11 downto 0)=X"3A4") else
                (record_count(29)(63 downto 32)) when (axi_araddr(11 downto 0)=X"3A8") else
                (busy_count(29)(31 downto 0)) when (axi_araddr(11 downto 0)=X"3AC") else
                (busy_count(29)(63 downto 32)) when (axi_araddr(11 downto 0)=X"3B0") else
                (full_count(29)(31 downto 0)) when (axi_araddr(11 downto 0)=X"3B4") else
                (full_count(29)(63 downto 32)) when (axi_araddr(11 downto 0)=X"3B8") else
                
                ("0000000000000000000000" & threshold(30)) when (axi_araddr(11 downto 0)=X"3C0") else
                (record_count(30)(31 downto 0)) when (axi_araddr(11 downto 0)=X"3C4") else
                (record_count(30)(63 downto 32)) when (axi_araddr(11 downto 0)=X"3C8") else
                (busy_count(30)(31 downto 0)) when (axi_araddr(11 downto 0)=X"3CC") else
                (busy_count(30)(63 downto 32)) when (axi_araddr(11 downto 0)=X"3D0") else
                (full_count(30)(31 downto 0)) when (axi_araddr(11 downto 0)=X"3D4") else
                (full_count(30)(63 downto 32)) when (axi_araddr(11 downto 0)=X"3D8") else
                
                ("0000000000000000000000" & threshold(31)) when (axi_araddr(11 downto 0)=X"3E0") else
                (record_count(31)(31 downto 0)) when (axi_araddr(11 downto 0)=X"3E4") else
                (record_count(31)(63 downto 32)) when (axi_araddr(11 downto 0)=X"3E8") else
                (busy_count(31)(31 downto 0)) when (axi_araddr(11 downto 0)=X"3EC") else
                (busy_count(31)(63 downto 32)) when (axi_araddr(11 downto 0)=X"3F0") else
                (full_count(31)(31 downto 0)) when (axi_araddr(11 downto 0)=X"3F4") else
                (full_count(31)(63 downto 32)) when (axi_araddr(11 downto 0)=X"3F8") else
                
                ("0000000000000000000000" & threshold(32)) when (axi_araddr(11 downto 0)=X"400") else
                (record_count(32)(31 downto 0)) when (axi_araddr(11 downto 0)=X"404") else
                (record_count(32)(63 downto 32)) when (axi_araddr(11 downto 0)=X"408") else
                (busy_count(32)(31 downto 0)) when (axi_araddr(11 downto 0)=X"40C") else
                (busy_count(32)(63 downto 32)) when (axi_araddr(11 downto 0)=X"410") else
                (full_count(32)(31 downto 0)) when (axi_araddr(11 downto 0)=X"414") else
                (full_count(32)(63 downto 32)) when (axi_araddr(11 downto 0)=X"418") else
                
                ("0000000000000000000000" & threshold(33)) when (axi_araddr(11 downto 0)=X"420") else
                (record_count(33)(31 downto 0)) when (axi_araddr(11 downto 0)=X"424") else
                (record_count(33)(63 downto 32)) when (axi_araddr(11 downto 0)=X"428") else
                (busy_count(33)(31 downto 0)) when (axi_araddr(11 downto 0)=X"42C") else
                (busy_count(33)(63 downto 32)) when (axi_araddr(11 downto 0)=X"430") else
                (full_count(33)(31 downto 0)) when (axi_araddr(11 downto 0)=X"434") else
                (full_count(33)(63 downto 32)) when (axi_araddr(11 downto 0)=X"438") else
                
                ("0000000000000000000000" & threshold(34)) when (axi_araddr(11 downto 0)=X"440") else
                (record_count(34)(31 downto 0)) when (axi_araddr(11 downto 0)=X"444") else
                (record_count(34)(63 downto 32)) when (axi_araddr(11 downto 0)=X"448") else
                (busy_count(34)(31 downto 0)) when (axi_araddr(11 downto 0)=X"44C") else
                (busy_count(34)(63 downto 32)) when (axi_araddr(11 downto 0)=X"450") else
                (full_count(34)(31 downto 0)) when (axi_araddr(11 downto 0)=X"454") else
                (full_count(34)(63 downto 32)) when (axi_araddr(11 downto 0)=X"458") else
                
                ("0000000000000000000000" & threshold(35)) when (axi_araddr(11 downto 0)=X"460") else
                (record_count(35)(31 downto 0)) when (axi_araddr(11 downto 0)=X"464") else
                (record_count(35)(63 downto 32)) when (axi_araddr(11 downto 0)=X"468") else
                (busy_count(35)(31 downto 0)) when (axi_araddr(11 downto 0)=X"46C") else
                (busy_count(35)(63 downto 32)) when (axi_araddr(11 downto 0)=X"470") else
                (full_count(35)(31 downto 0)) when (axi_araddr(11 downto 0)=X"474") else
                (full_count(35)(63 downto 32)) when (axi_araddr(11 downto 0)=X"478") else
                
                ("0000000000000000000000" & threshold(36)) when (axi_araddr(11 downto 0)=X"480") else
                (record_count(36)(31 downto 0)) when (axi_araddr(11 downto 0)=X"484") else
                (record_count(36)(63 downto 32)) when (axi_araddr(11 downto 0)=X"488") else
                (busy_count(36)(31 downto 0)) when (axi_araddr(11 downto 0)=X"48C") else
                (busy_count(36)(63 downto 32)) when (axi_araddr(11 downto 0)=X"490") else
                (full_count(36)(31 downto 0)) when (axi_araddr(11 downto 0)=X"494") else
                (full_count(36)(63 downto 32)) when (axi_araddr(11 downto 0)=X"498") else
                
                ("0000000000000000000000" & threshold(37)) when (axi_araddr(11 downto 0)=X"4A0") else
                (record_count(37)(31 downto 0)) when (axi_araddr(11 downto 0)=X"4A4") else
                (record_count(37)(63 downto 32)) when (axi_araddr(11 downto 0)=X"4A8") else
                (busy_count(37)(31 downto 0)) when (axi_araddr(11 downto 0)=X"4AC") else
                (busy_count(37)(63 downto 32)) when (axi_araddr(11 downto 0)=X"4B0") else
                (full_count(37)(31 downto 0)) when (axi_araddr(11 downto 0)=X"4B4") else
                (full_count(37)(63 downto 32)) when (axi_araddr(11 downto 0)=X"4B8") else
                
                ("0000000000000000000000" & threshold(38)) when (axi_araddr(11 downto 0)=X"4C0") else
                (record_count(38)(31 downto 0)) when (axi_araddr(11 downto 0)=X"4C4") else
                (record_count(38)(63 downto 32)) when (axi_araddr(11 downto 0)=X"4C8") else
                (busy_count(38)(31 downto 0)) when (axi_araddr(11 downto 0)=X"4CC") else
                (busy_count(38)(63 downto 32)) when (axi_araddr(11 downto 0)=X"4D0") else
                (full_count(38)(31 downto 0)) when (axi_araddr(11 downto 0)=X"4D4") else
                (full_count(38)(63 downto 32)) when (axi_araddr(11 downto 0)=X"4D8") else
                
                ("0000000000000000000000" & threshold(39)) when (axi_araddr(11 downto 0)=X"4E0") else
                (record_count(39)(31 downto 0)) when (axi_araddr(11 downto 0)=X"4E4") else
                (record_count(39)(63 downto 32)) when (axi_araddr(11 downto 0)=X"4E8") else
                (busy_count(39)(31 downto 0)) when (axi_araddr(11 downto 0)=X"4EC") else
                (busy_count(39)(63 downto 32)) when (axi_araddr(11 downto 0)=X"4F0") else
                (full_count(39)(31 downto 0)) when (axi_araddr(11 downto 0)=X"4F4") else
                (full_count(39)(63 downto 32)) when (axi_araddr(11 downto 0)=X"4F8") else

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

end selftrig_core_arch;
