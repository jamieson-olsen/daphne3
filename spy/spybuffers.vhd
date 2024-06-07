-- spybuffers.vhd
--
-- 45 spy buffers for AFE data + 4 spy buffers for the 64 bit timestamp
-- each spy buffer stores 4k 16-bit samples which includes 64 pre-trig samples
-- each spy buffer appears as a 2k x 32 memory block which is R/W from the AXI bus
--
-- Now normally one would not write anything to a spy buffer from AXI 
-- but it might be useful for debugging. All AXI-LITE transactions must be 32 bits.
--
-- memory map: 
--
--  start_AXI_addr	  end_AXI_addr	    Buffer Description
--  BASE+00000        BASE+01FFC        AFE0 channel 0
--  BASE+02000        BASE+03FFC        AFE0 channel 1
--  BASE+04000        BASE+05FFC        AFE0 channel 2
--  BASE+06000        BASE+07FFC        AFE0 channel 3
--  BASE+08000        BASE+09FFC        AFE0 channel 4
--  BASE+0A000        BASE+0BFFC        AFE0 channel 5
--  BASE+0C000        BASE+0DFFC        AFE0 channel 6
--  BASE+0E000        BASE+0FFFC        AFE0 channel 7
--  BASE+10000        BASE+11FFC        AFE0 channel 8
--  BASE+12000        BASE+13FFC        AFE1 channel 0
--  BASE+14000        BASE+15FFC        AFE1 channel 1
--  BASE+16000        BASE+17FFC        AFE1 channel 2
--  BASE+18000        BASE+19FFC        AFE1 channel 3
--  BASE+1A000        BASE+1BFFC        AFE1 channel 4
--  BASE+1C000        BASE+1DFFC        AFE1 channel 5
--  BASE+1E000        BASE+1FFFC        AFE1 channel 6
--  BASE+20000        BASE+21FFC        AFE1 channel 7
--  BASE+22000        BASE+23FFC        AFE1 channel 8
--  BASE+24000        BASE+25FFC        AFE2 channel 0
--  BASE+26000        BASE+27FFC        AFE2 channel 1
--  BASE+28000        BASE+29FFC        AFE2 channel 2
--  BASE+2A000        BASE+2BFFC        AFE2 channel 3
--  BASE+2C000        BASE+2DFFC        AFE2 channel 4
--  BASE+2E000        BASE+2FFFC        AFE2 channel 5
--  BASE+30000        BASE+31FFC        AFE2 channel 6
--  BASE+32000        BASE+33FFC        AFE2 channel 7
--  BASE+34000        BASE+35FFC        AFE2 channel 8
--  BASE+36000        BASE+37FFC        AFE3 channel 0
--  BASE+38000        BASE+39FFC        AFE3 channel 1
--  BASE+3A000        BASE+3BFFC        AFE3 channel 2
--  BASE+3C000        BASE+3DFFC        AFE3 channel 3
--  BASE+3E000        BASE+3FFFC        AFE3 channel 4
--  BASE+40000        BASE+41FFC        AFE3 channel 5
--  BASE+42000        BASE+43FFC        AFE3 channel 6
--  BASE+44000        BASE+45FFC        AFE3 channel 7
--  BASE+46000        BASE+47FFC        AFE3 channel 8
--  BASE+48000        BASE+49FFC        AFE4 channel 0
--  BASE+4A000        BASE+4BFFC        AFE4 channel 1
--  BASE+4C000        BASE+4DFFC        AFE4 channel 2
--  BASE+4E000        BASE+4FFFC        AFE4 channel 3
--  BASE+50000        BASE+51FFC        AFE4 channel 4
--  BASE+52000        BASE+53FFC        AFE4 channel 5
--  BASE+54000        BASE+55FFC        AFE4 channel 6
--  BASE+56000        BASE+57FFC        AFE4 channel 7
--  BASE+58000        BASE+59FFC        AFE4 channel 8
--  BASE+5A000        BASE+5BFFC        TimeStamp(15..0)
--  BASE+5C000        BASE+5DFFC        TimeStamp(31..16)
--  BASE+5E000        BASE+5FFFC        TimeStamp(47..32)
--  BASE+60000        BASE+61FFC        TimeStamp(63..48)

-- the first AXI address of this module is at BASE + 0
-- the last AXI address of this module is at BASE + 0x61FFC
-- total memory size of this AXI-LITE slave is 401408 (0x62000) bytes
-- it uses 2(5*9+4) = 98 36kbit BlockRAMs 

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.daphne3_package.all;

entity spybuffers is
port(
    clock: in std_logic; -- master clock
    trig:  in std_logic; -- trigger pulse sync to clock
    din:   in array_5x9x16_type; -- AFE data sync to clock
    timestamp: in std_logic_vector(63 downto 0); -- timestamp sync to clock
    
    -- AXI-LITE interface

	S_AXI_ACLK	    : in std_logic;
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
end spybuffers;

architecture spybuffers_arch of spybuffers is

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

    signal reset: std_logic;
    signal ena, wea: array_5x9_type;
    signal douta: array_5x9x32_type;
    signal ts_ena, ts_wea: std_logic_vector(3 downto 0);
    signal ts_douta: array_4x32_type;

    component spybuff is
    port(
        clock: in std_logic; -- master clock
        reset: in std_logic; -- active high reset async
        trig:  in std_logic; -- trigger pulse sync to clock
        data:  in std_logic_vector(15 downto 0); -- afe data sync to clock
        clka:  in  std_logic; -- RAM interface is 2k x 32 and is R/W
        addra: in  std_logic_vector(10 downto 0);
    	ena:   in  std_logic;
    	wea:   in  std_logic;
    	dina:  in  std_logic_vector(31 downto 0);
        douta: out std_logic_vector(31 downto 0)  
      );
    end component;

begin

    reset <= not S_AXI_ARESETN;

    -- 45 spy buffers (5 AFEs x 9 channels/AFE)
    -- channels 0-7 are AFE data 
    -- channel 8 is the frame marker pattern
    
    gen_afe: for a in 4 downto 0 generate
    gen_ch: for c in 8 downto 0 generate
    
        spybuffer_inst: spybuff
        port map(
            clock => clock,
            reset => reset,
            trig  => trig,
            data  => din(a)(c),
    
            clka => S_AXI_ACLK,
            addra => addra,
        	ena => ena(a)(c),
        	wea => wea(a)(c),
        	dina => S_AXI_WDATA, 
            douta => douta(a)(c)
          );
    
    end generate gen_ch;
    end generate gen_afe;
    
    -- 4 more spy buffers to store the 64 bit timestamp
    -- the 64 bit timestamp is "striped" across four spy buffers
    -- e.g. the first spy buffer stores timestamp bits(15..0)
    -- the next spy buffer stores timestamp bits(32..16) and so on
    
    gen_ts: for t in 3 downto 0 generate
    
        spybuffer_inst: spybuff
        port map(
            clock => clock,
            reset => reset,
            trig  => trig,
            data  => timestamp( 16*t+15 downto 16*t ),
    
            clka => S_AXI_ACLK,
            addra => addra,
        	ena => ts_ena(t),
        	wea => ts_wea(t), 
        	dina => S_AXI_WDATA,
            douta => ts_douta(t)
          );
    
    end generate gen_ts;

    -- following code derived from Xilinx AXI-LITE slave example design
    -- modified to add one clock cycle read latency on the axi_arready signal
    
	S_AXI_AWREADY	<= axi_awready;
	S_AXI_WREADY	<= axi_wready;
	S_AXI_BRESP	    <= axi_bresp;
	S_AXI_BVALID	<= axi_bvalid;
    S_AXI_ARREADY	<= axi_arready_reg;
	S_AXI_RDATA	    <= axi_rdata;
	S_AXI_RRESP	    <= axi_rresp;
	S_AXI_RVALID	<= axi_rvalid;

	-- Implement axi_awready generation
	-- axi_awready is asserted for one S_AXI_ACLK clock cycle when both
	-- S_AXI_AWVALID and S_AXI_WVALID are asserted. axi_awready is
	-- de-asserted when reset is low.

	process (S_AXI_ACLK)
	begin
	  if rising_edge(S_AXI_ACLK) then 
	    if S_AXI_ARESETN = '0' then
	      axi_awready <= '0';
	      aw_en <= '1';
	    else
	      if (axi_awready = '0' and S_AXI_AWVALID = '1' and S_AXI_WVALID = '1' and aw_en = '1') then

	        -- slave is ready to accept write address when
	        -- there is a valid write address and write data
	        -- on the write address and data bus. This design 
	        -- expects no outstanding transactions. 

	           axi_awready <= '1';
	           aw_en <= '0';
	        elsif (S_AXI_BREADY = '1' and axi_bvalid = '1') then
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

	process (S_AXI_ACLK)
	begin
	  if rising_edge(S_AXI_ACLK) then 
	    if S_AXI_ARESETN = '0' then
	      axi_awaddr <= (others => '0');
	    else
	      if (axi_awready = '0' and S_AXI_AWVALID = '1' and S_AXI_WVALID = '1' and aw_en = '1') then
	        -- Write Address latching
	        axi_awaddr <= S_AXI_AWADDR;
	      end if;
	    end if;
	  end if;                   
	end process; 

	-- Implement axi_wready generation
	-- axi_wready is asserted for one S_AXI_ACLK clock cycle when both
	-- S_AXI_AWVALID and S_AXI_WVALID are asserted. axi_wready is 
	-- de-asserted when reset is low. 

	process (S_AXI_ACLK)
	begin
	  if rising_edge(S_AXI_ACLK) then 
	    if S_AXI_ARESETN = '0' then
	      axi_wready <= '0';
	    else
	      if (axi_wready = '0' and S_AXI_WVALID = '1' and S_AXI_AWVALID = '1' and aw_en = '1') then

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

	wren <= axi_wready and S_AXI_WVALID and axi_awready and S_AXI_AWVALID ;

	-- Implement write response logic generation
	-- The write response and response valid signals are asserted by the slave 
	-- when axi_wready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted.  
	-- This marks the acceptance of address and indicates the status of 
	-- write transaction.

	process (S_AXI_ACLK)
	begin
	  if rising_edge(S_AXI_ACLK) then 
	    if S_AXI_ARESETN = '0' then
	      axi_bvalid  <= '0';
	      axi_bresp   <= "00"; --need to work more on the responses
	    else
	      if (axi_awready = '1' and S_AXI_AWVALID = '1' and axi_wready = '1' and S_AXI_WVALID = '1' and axi_bvalid = '0'  ) then
	        axi_bvalid <= '1';
	        axi_bresp  <= "00"; 
	      elsif (S_AXI_BREADY = '1' and axi_bvalid = '1') then -- check if bready is asserted while bvalid is high)
	        axi_bvalid <= '0';                                 -- (there is a possibility that bready is always asserted high)
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

	process (S_AXI_ACLK)
	begin
	  if rising_edge(S_AXI_ACLK) then 
	    if S_AXI_ARESETN = '0' then
	      axi_arready <= '0';
          axi_arready_reg <= '0';
	      axi_araddr  <= (others => '1');
	      axi_arvalid <= '0';
	    else
		  axi_arvalid <= S_AXI_ARVALID;
          if (axi_arready='0' and axi_arready_reg='0' and S_AXI_ARVALID='1') then
	        -- indicates that the slave has acceped the valid read address
	        axi_arready <= '1';
			axi_arready_reg <= axi_arready;
	        -- Read Address latching 
	        axi_araddr  <= S_AXI_ARADDR;           
	      else
	        axi_arready <= '0';
            axi_arready_reg <= axi_arready;
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
  
	process (S_AXI_ACLK)
	begin
	  if rising_edge(S_AXI_ACLK) then
	    if S_AXI_ARESETN = '0' then
	      axi_rvalid <= '0';
	      axi_rresp  <= "00";
	    else
          if (axi_arready_reg = '1' and S_AXI_ARVALID = '1' and axi_rvalid = '0') then
	        -- Valid read data is available at the read data bus
	        axi_rvalid <= '1';
	        axi_rresp  <= "00"; -- 'OKAY' response
	      elsif (axi_rvalid = '1' and S_AXI_RREADY = '1') then
	        -- Read data is accepted by the master
	        axi_rvalid <= '0';
	      end if;            
	    end if;
	  end if;
	end process;

	-- Implement memory mapped register select and read logic generation
	-- Slave register read enable is asserted when valid address is available
	-- and the slave is ready to accept the read address.

	rden <= axi_arready_reg and S_AXI_ARVALID and (not axi_rvalid) ;

	-- Output register or memory read data
    -- When there is a valid read address (S_AXI_ARVALID) with 
    -- acceptance of read address by the slave (axi_arready), 
    -- output the read data, read address mux

	process( S_AXI_ACLK ) is
	begin
	  if (rising_edge (S_AXI_ACLK)) then
	    if ( S_AXI_ARESETN = '0' ) then
	      axi_rdata  <= (others => '0');
	    else
	      if ( rden='1' ) then
	          axi_rdata <= ram_dout;
	      end if;   
	    end if;
	  end if;
	end process;

    -- create the necessary enables and muxes to connect 45 + 4 spy buffers
    -- to the AXI bus 

    -- AXI address bus refers to byte locations
    -- Spybuffer address bus refers to 32-bit word locations
    --
    -- AXI address base+0 = AFE 0 channel 0 (sample1(15..0) & sample0(15..0))
    -- AXI address base+4 = AFE 0 channel 0 (sample3(15..0) & sample2(15..0))
    -- AXI address base+8 = AFE 0 channel 0 (sample5(15..0) & sample4(15..0))
    --
    -- address decoding use axi address bits (18 downto 13)
    -- 0x00000-0x01FFC = 0000 000X XXXX XXXX XX00
    -- 0x02000-0x03FFC = 0000 001X XXXX XXXX XX00
    -- ...
    -- 0x60000-0x61FFC = 0110 000X XXXX XXXX XX00 
    --
    -- SpyBuffer address is 2k (11 bits, 10..0), maps into axi address bits (12 downto 2)

    addra <= axi_awaddr(12 downto 2) when (wren='1') else 
    	     axi_araddr(12 downto 2);

    -- enable and write enable generation for AFE spybuffers, 45 blocks 0-44
    
    gen_afe_enables: for a in 4 downto 0 generate
    gen_ch_enables: for c in 8 downto 0 generate
    
        ena(a)(c) <= '1' when ( axi_arvalid='1' and axi_araddr(18 downto 13)=std_logic_vector(to_unsigned(9*a+c,6)) ) else 
                     '1' when ( wren='1'        and axi_awaddr(18 downto 13)=std_logic_vector(to_unsigned(9*a+c,6)) ) else 
                     '0';
        
        wea(a)(c) <= '1' when ( wren='1' and axi_awaddr(18 downto 13)=std_logic_vector(to_unsigned(9*a+c,6)) ) else '0';
    
    end generate gen_ch_enables;
    end generate gen_afe_enables;

    -- enable and write enable generation for TS spybuffers, 4 blocks 45-48

    gen_ts_enables: for t in 3 downto 0 generate

        ts_ena(t) <= '1' when ( axi_arvalid='1' and axi_araddr(18 downto 13)=std_logic_vector(to_unsigned(45+t,6)) ) else 
                     '1' when ( wren='1'        and axi_awaddr(18 downto 13)=std_logic_vector(to_unsigned(45+t,6)) ) else 
                     '0';
        
        ts_wea(t) <= '1' when ( wren='1' and axi_awaddr(18 downto 13)=std_logic_vector(to_unsigned(45+t,6)) ) else '0';

    end generate gen_ts_enables;
	
    -- big mux for AXI reads from 45 AFE spybuffers and 4 TS spybuffers
    
    gen_afe_doutmux: for a in 4 downto 0 generate
    gen_ch_doutmux: for c in 8 downto 0 generate

        ram_dout <= douta(a)(c) when ( axi_araddr(18 downto 13)=std_logic_vector(to_unsigned(9*a+c,6)) ) else (others=>'Z');

    end generate gen_ch_doutmux;
    end generate gen_afe_doutmux;

    gen_ts_doutmux: for t in 3 downto 0 generate

        ram_dout <= ts_douta(t) when ( axi_araddr(18 downto 13)=std_logic_vector(to_unsigned(45+t,6)) ) else (others=>'Z');

    end generate gen_ts_doutmux;

end spybuffers_arch;
