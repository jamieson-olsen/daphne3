-- spyram
-- true dual port RAM, independent clocks
-- two 36kbit BlockRAMs, each is 2k x 16
-- port a = 2k x 32 is read/write (for axi access)
-- port b = 4k x 16 is write only (for spybuff writing)
--
-- Jamieson Olsen <jamieson@fnal.gov>
-- 
-- Example Mapping: 
--
-- SpyBuff writes 0xAAAA to addrb 0 (write ram0 addr 0)
-- SpyBuff writes 0xBBBB to addrb 1 (write ram1 addr 0)
-- SpyBuff writes 0xCCCC to addrb 2 (write ram0 addr 1)
-- SpyBuff writes 0xDDDD to addrb 3 (write ram1 addr 1)
-- AXI reads 0xBBBBAAAA from addra 0 
-- AXI reads 0xDDDDCCCC from addra 1

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

entity spyram is
port (
		clka:  in  std_logic;
		addra: in  std_logic_vector(10 downto 0); -- 2k x 32 R/W axi
        dina:  in  std_logic_vector(31 downto 0);
        ena:   in  std_logic;
        wea:   in  std_logic;
        douta: out std_logic_vector(31 downto 0);

        clkb:  in  std_logic;
        addrb: in  std_logic_vector(11 downto 0); -- 4k x 16 writeonly spybuff
        dinb:  in  std_logic_vector(15 downto 0);
        web:   in  std_logic
	);
end spyram;

architecture spyram_2k32_4k16_arch of spyram is

    signal addra_i: std_logic_vector(14 downto 0);
	signal wea_i: std_logic_vector(3 downto 0);
    signal ram0_dina, ram1_dina, ram0_douta, ram1_douta: std_logic_vector(31 downto 0);

    signal addrb_i: std_logic_vector(14 downto 0);
	signal ram0_enb, ram1_enb: std_logic;
    signal dinb_i: std_logic_vector(31 downto 0);

begin

-- Port A: AXI-LITE R/W access, 2k x 32
-- BlockRAMs are each 2k x 16
-- BlockRAM1 is high word (31..16), BlockRAM0 is low word(15..0)

addra_i <= addra(10 downto 0) & "0000";
wea_i <= "1111" when ( wea='1' ) else "0000";
ram0_dina <= X"0000" & dina(15 downto 0);
ram1_dina <= X"0000" & dina(31 downto 16);
douta <= ram1_douta(15 downto 0) & ram0_douta(15 downto 0);

-- Port B: Spy Buffer logic access, write only, 4k x 16
-- BlockRAMs are each 2k x 16
-- if addrb(0)=0 write to BlockRAM0
-- if addrb(0)=1 write to BlockRAM1

addrb_i <= addrb(11 downto 1) & "0000";
dinb_i <= X"0000" & dinb;
ram0_enb <= '1' when ( addrb(0)='0' and web='1' ) else '0';
ram1_enb <= '1' when ( addrb(0)='1' and web='1' ) else '0';

RAMB36E2_0_inst : RAMB36E2
generic map (
   -- CASCADE_ORDER_A, CASCADE_ORDER_B: "FIRST", "MIDDLE", "LAST", "NONE"
   CASCADE_ORDER_A => "NONE",
   CASCADE_ORDER_B => "NONE",
   -- CLOCK_DOMAINS: "COMMON", "INDEPENDENT"
   CLOCK_DOMAINS => "INDEPENDENT",
   -- Collision check: "ALL", "GENERATE_X_ONLY", "NONE", "WARNING_ONLY"
   SIM_COLLISION_CHECK => "ALL",
   -- DOA_REG, DOB_REG: Optional output register (0, 1)
   DOA_REG => 0,
   DOB_REG => 0,
   -- ENADDRENA/ENADDRENB: Address enable pin enable, "TRUE", "FALSE"
   ENADDRENA => "FALSE",
   ENADDRENB => "FALSE",
   -- EN_ECC_PIPE: ECC pipeline register, "TRUE"/"FALSE"
   EN_ECC_PIPE => "FALSE",
   -- EN_ECC_READ: Enable ECC decoder, "TRUE"/"FALSE"
   EN_ECC_READ => "FALSE",
   -- EN_ECC_WRITE: Enable ECC encoder, "TRUE"/"FALSE"
   EN_ECC_WRITE => "FALSE",
   -- INIT_A, INIT_B: Initial values on output ports
   INIT_A => X"000000000",
   INIT_B => X"000000000",
   -- Initialization File: RAM initialization file
   INIT_FILE => "NONE",
   -- Programmable Inversion Attributes: Specifies the use of the built-in programmable inversion
   IS_CLKARDCLK_INVERTED => '0',
   IS_CLKBWRCLK_INVERTED => '0',
   IS_ENARDEN_INVERTED => '0',
   IS_ENBWREN_INVERTED => '0',
   IS_RSTRAMARSTRAM_INVERTED => '0',
   IS_RSTRAMB_INVERTED => '0',
   IS_RSTREGARSTREG_INVERTED => '0',
   IS_RSTREGB_INVERTED => '0',
   -- RDADDRCHANGE: Disable memory access when output value does not change ("TRUE", "FALSE")
   RDADDRCHANGEA => "FALSE",
   RDADDRCHANGEB => "FALSE",
   -- READ_WIDTH_A/B, WRITE_WIDTH_A/B: Read/write width per port
   READ_WIDTH_A => 18,
   READ_WIDTH_B => 18,
   WRITE_WIDTH_A => 18,
   WRITE_WIDTH_B => 18,
   -- RSTREG_PRIORITY_A, RSTREG_PRIORITY_B: Reset or enable priority ("RSTREG", "REGCE")
   RSTREG_PRIORITY_A => "RSTREG",
   RSTREG_PRIORITY_B => "RSTREG",
   -- SRVAL_A, SRVAL_B: Set/reset value for output
   SRVAL_A => X"000000000",
   SRVAL_B => X"000000000",
   -- Sleep Async: Sleep function asynchronous or synchronous ("TRUE", "FALSE")
   SLEEP_ASYNC => "FALSE",
   -- WriteMode: "WRITE_FIRST", "NO_CHANGE", "READ_FIRST"
   WRITE_MODE_A => "NO_CHANGE",
   WRITE_MODE_B => "NO_CHANGE"
)
port map (
   -- no cascade, no parity, no error injection...
   CASDOUTA => open,          -- 32-bit output: Port A cascade output data
   CASDOUTB => open,          -- 32-bit output: Port B cascade output data
   CASDOUTPA => open,         -- 4-bit output: Port A cascade output parity data
   CASDOUTPB => open,         -- 4-bit output: Port B cascade output parity data
   CASOUTDBITERR => open,     -- 1-bit output: DBITERR cascade output
   CASOUTSBITERR => open,     -- 1-bit output: SBITERR cascade output
   DBITERR => open,           -- 1-bit output: Double bit error status
   ECCPARITY => open,         -- 8-bit output: Generated error correction parity
   RDADDRECC => open,         -- 9-bit output: ECC Read Address
   SBITERR => open,           -- 1-bit output: Single bit error status
   CASDIMUXA => '0',          -- 1-bit input: Port A input data (0=DINA, 1=CASDINA)
   CASDIMUXB => '0',          -- 1-bit input: Port B input data (0=DINB, 1=CASDINB)
   CASDINA => X"00000000",    -- 32-bit input: Port A cascade input data
   CASDINB => X"00000000",    -- 32-bit input: Port B cascade input data
   CASDINPA => "0000",        -- 4-bit input: Port A cascade input parity data
   CASDINPB => "0000",        -- 4-bit input: Port B cascade input parity data
   CASDOMUXA => '0',          -- 1-bit input: Port A unregistered data (0=BRAM data, 1=CASDINA)
   CASDOMUXB => '0',          -- 1-bit input: Port B unregistered data (0=BRAM data, 1=CASDINB)
   CASDOMUXEN_A => '0',       -- 1-bit input: Port A unregistered output data enable
   CASDOMUXEN_B => '0',       -- 1-bit input: Port B unregistered output data enable
   CASINDBITERR => '0',       -- 1-bit input: DBITERR cascade input
   CASINSBITERR => '0',       -- 1-bit input: SBITERR cascade input
   CASOREGIMUXA => '0',       -- 1-bit input: Port A registered data (0=BRAM data, 1=CASDINA)
   CASOREGIMUXB => '0',       -- 1-bit input: Port B registered data (0=BRAM data, 1=CASDINB)
   CASOREGIMUXEN_A => '0',    -- 1-bit input: Port A registered output data enable
   CASOREGIMUXEN_B => '0',    -- 1-bit input: Port B registered output data enable
   ECCPIPECE => '0',          -- 1-bit input: ECC Pipeline Register Enable
   INJECTDBITERR => '0',      -- 1-bit input: Inject a double-bit error
   INJECTSBITERR => '0',

	-- Port A: AXI R/W access

   CLKARDCLK => clka,                  -- 1-bit input: A/Read port clock
   ADDRARDADDR => addra_i,             -- 15-bit input: A/Read port address
   ADDRENA => '0',                     -- 1-bit input: Active-High A/Read port address enable
   ENARDEN => ena,                     -- 1-bit input: Port A enable/Read enable
   REGCEAREGCE => '1',                 -- 1-bit input: Port A register enable/Register enable
   RSTRAMARSTRAM => '0',               -- 1-bit input: Port A set/reset
   RSTREGARSTREG => '0',               -- 1-bit input: Port A register set/reset
   SLEEP => '0',                       -- 1-bit input: Sleep Mode
   WEA => wea_i,                       -- 4-bit input: Port A write enable
   DINADIN => ram0_dina,               -- 32-bit input: Port A data/LSB data
   DINPADINP => "0000",                -- 4-bit input: Port A parity/LSB parity
   DOUTADOUT => ram0_douta,            -- 32-bit output: Port A Data/LSB data
   DOUTPADOUTP => open,                -- 4-bit output: Port A parity/LSB parity

	-- Port B: spy buffer logic, write only

   CLKBWRCLK => clkb,              -- 1-bit input: B/Write port clock
   ADDRBWRADDR => addrb_i,         -- 15-bit input: B/Write port address
   ADDRENB => '0',                 -- 1-bit input: Active-High B/Write port address enable
   ENBWREN => ram0_enb,            -- 1-bit input: Port B enable/Write enable
   REGCEB => '0',                  -- 1-bit input: Port B register enable
   RSTRAMB => '0',                 -- 1-bit input: Port B set/reset
   RSTREGB => '0',                 -- 1-bit input: Port B register set/reset
   WEBWE => "11111111",            -- 8-bit input: Port B write enable/Write enable
   DINBDIN => dinb_i,              -- 32-bit input: Port B data/MSB data
   DINPBDINP => "0000",            -- 4-bit input: Port B parity/MSB parity
   DOUTBDOUT => open,              -- 32-bit output: Port B data/MSB data
   DOUTPBDOUTP => open             -- 4-bit output: Port B parity/MSB parity

);

RAMB36E2_1_inst : RAMB36E2
generic map (
   -- CASCADE_ORDER_A, CASCADE_ORDER_B: "FIRST", "MIDDLE", "LAST", "NONE"
   CASCADE_ORDER_A => "NONE",
   CASCADE_ORDER_B => "NONE",
   -- CLOCK_DOMAINS: "COMMON", "INDEPENDENT"
   CLOCK_DOMAINS => "INDEPENDENT",
   -- Collision check: "ALL", "GENERATE_X_ONLY", "NONE", "WARNING_ONLY"
   SIM_COLLISION_CHECK => "ALL",
   -- DOA_REG, DOB_REG: Optional output register (0, 1)
   DOA_REG => 0,
   DOB_REG => 0,
   -- ENADDRENA/ENADDRENB: Address enable pin enable, "TRUE", "FALSE"
   ENADDRENA => "FALSE",
   ENADDRENB => "FALSE",
   -- EN_ECC_PIPE: ECC pipeline register, "TRUE"/"FALSE"
   EN_ECC_PIPE => "FALSE",
   -- EN_ECC_READ: Enable ECC decoder, "TRUE"/"FALSE"
   EN_ECC_READ => "FALSE",
   -- EN_ECC_WRITE: Enable ECC encoder, "TRUE"/"FALSE"
   EN_ECC_WRITE => "FALSE",
   -- INIT_A, INIT_B: Initial values on output ports
   INIT_A => X"000000000",
   INIT_B => X"000000000",
   -- Initialization File: RAM initialization file
   INIT_FILE => "NONE",
   -- Programmable Inversion Attributes: Specifies the use of the built-in programmable inversion
   IS_CLKARDCLK_INVERTED => '0',
   IS_CLKBWRCLK_INVERTED => '0',
   IS_ENARDEN_INVERTED => '0',
   IS_ENBWREN_INVERTED => '0',
   IS_RSTRAMARSTRAM_INVERTED => '0',
   IS_RSTRAMB_INVERTED => '0',
   IS_RSTREGARSTREG_INVERTED => '0',
   IS_RSTREGB_INVERTED => '0',
   -- RDADDRCHANGE: Disable memory access when output value does not change ("TRUE", "FALSE")
   RDADDRCHANGEA => "FALSE",
   RDADDRCHANGEB => "FALSE",
   -- READ_WIDTH_A/B, WRITE_WIDTH_A/B: Read/write width per port
   READ_WIDTH_A => 18,
   READ_WIDTH_B => 18,
   WRITE_WIDTH_A => 18,
   WRITE_WIDTH_B => 18,
   -- RSTREG_PRIORITY_A, RSTREG_PRIORITY_B: Reset or enable priority ("RSTREG", "REGCE")
   RSTREG_PRIORITY_A => "RSTREG",
   RSTREG_PRIORITY_B => "RSTREG",
   -- SRVAL_A, SRVAL_B: Set/reset value for output
   SRVAL_A => X"000000000",
   SRVAL_B => X"000000000",
   -- Sleep Async: Sleep function asynchronous or synchronous ("TRUE", "FALSE")
   SLEEP_ASYNC => "FALSE",
   -- WriteMode: "WRITE_FIRST", "NO_CHANGE", "READ_FIRST"
   WRITE_MODE_A => "NO_CHANGE",
   WRITE_MODE_B => "NO_CHANGE"
)
port map (
   -- no cascade, no parity, no error injection...
   CASDOUTA => open,          -- 32-bit output: Port A cascade output data
   CASDOUTB => open,          -- 32-bit output: Port B cascade output data
   CASDOUTPA => open,         -- 4-bit output: Port A cascade output parity data
   CASDOUTPB => open,         -- 4-bit output: Port B cascade output parity data
   CASOUTDBITERR => open,     -- 1-bit output: DBITERR cascade output
   CASOUTSBITERR => open,     -- 1-bit output: SBITERR cascade output
   DBITERR => open,           -- 1-bit output: Double bit error status
   ECCPARITY => open,         -- 8-bit output: Generated error correction parity
   RDADDRECC => open,         -- 9-bit output: ECC Read Address
   SBITERR => open,           -- 1-bit output: Single bit error status
   CASDIMUXA => '0',          -- 1-bit input: Port A input data (0=DINA, 1=CASDINA)
   CASDIMUXB => '0',          -- 1-bit input: Port B input data (0=DINB, 1=CASDINB)
   CASDINA => X"00000000",    -- 32-bit input: Port A cascade input data
   CASDINB => X"00000000",    -- 32-bit input: Port B cascade input data
   CASDINPA => "0000",        -- 4-bit input: Port A cascade input parity data
   CASDINPB => "0000",        -- 4-bit input: Port B cascade input parity data
   CASDOMUXA => '0',          -- 1-bit input: Port A unregistered data (0=BRAM data, 1=CASDINA)
   CASDOMUXB => '0',          -- 1-bit input: Port B unregistered data (0=BRAM data, 1=CASDINB)
   CASDOMUXEN_A => '0',       -- 1-bit input: Port A unregistered output data enable
   CASDOMUXEN_B => '0',       -- 1-bit input: Port B unregistered output data enable
   CASINDBITERR => '0',       -- 1-bit input: DBITERR cascade input
   CASINSBITERR => '0',       -- 1-bit input: SBITERR cascade input
   CASOREGIMUXA => '0',       -- 1-bit input: Port A registered data (0=BRAM data, 1=CASDINA)
   CASOREGIMUXB => '0',       -- 1-bit input: Port B registered data (0=BRAM data, 1=CASDINB)
   CASOREGIMUXEN_A => '0',    -- 1-bit input: Port A registered output data enable
   CASOREGIMUXEN_B => '0',    -- 1-bit input: Port B registered output data enable
   ECCPIPECE => '0',          -- 1-bit input: ECC Pipeline Register Enable
   INJECTDBITERR => '0',      -- 1-bit input: Inject a double-bit error
   INJECTSBITERR => '0',

	-- Port A: AXI R/W access

   CLKARDCLK => clka,                  -- 1-bit input: A/Read port clock
   ADDRARDADDR => addra_i,             -- 15-bit input: A/Read port address
   ADDRENA => '0',                     -- 1-bit input: Active-High A/Read port address enable
   ENARDEN => ena,                     -- 1-bit input: Port A enable/Read enable
   REGCEAREGCE => '1',                 -- 1-bit input: Port A register enable/Register enable
   RSTRAMARSTRAM => '0',               -- 1-bit input: Port A set/reset
   RSTREGARSTREG => '0',               -- 1-bit input: Port A register set/reset
   SLEEP => '0',                       -- 1-bit input: Sleep Mode
   WEA => wea_i,                       -- 4-bit input: Port A write enable
   DINADIN => ram1_dina,               -- 32-bit input: Port A data/LSB data
   DINPADINP => "0000",                -- 4-bit input: Port A parity/LSB parity
   DOUTADOUT => ram1_douta,            -- 32-bit output: Port A Data/LSB data
   DOUTPADOUTP => open,                -- 4-bit output: Port A parity/LSB parity

	-- Port B: spy buffer logic, write only

   CLKBWRCLK => clkb,              -- 1-bit input: B/Write port clock
   ADDRBWRADDR => addrb_i,         -- 15-bit input: B/Write port address
   ADDRENB => '0',                 -- 1-bit input: Active-High B/Write port address enable
   ENBWREN => ram1_enb,            -- 1-bit input: Port B enable/Write enable
   REGCEB => '0',                  -- 1-bit input: Port B register enable
   RSTRAMB => '0',                 -- 1-bit input: Port B set/reset
   RSTREGB => '0',                 -- 1-bit input: Port B register set/reset
   WEBWE => "11111111",            -- 8-bit input: Port B write enable/Write enable
   DINBDIN => dinb_i,              -- 32-bit input: Port B data/MSB data
   DINPBDINP => "0000",            -- 4-bit input: Port B parity/MSB parity
   DOUTBDOUT => open,              -- 32-bit output: Port B data/MSB data
   DOUTPBDOUTP => open             -- 4-bit output: Port B parity/MSB parity

);

end spyram_2k32_4k16_arch;
