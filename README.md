# daphne3
Kria Zynq UltraScale+ firmware for the PL 

This is not the complete firmware design for the Kria PL side, but rather some of the major components that will need to be instantiated at the top level.

## DAPHNE3 Entity

Currently the Kria top level entity is a graphical schematic which has blocks for the PS, AXI interconnects, various IP blocks, and custom blocks. This entity, DAPHNE3 will become another block in this top level schematic. There are two AXI-LITE slave interfaces exposed: one for the Front End control register and another AXI-LITE slave interface for the spy buffers. Each of these interfaces will need to be connected to the AXI interconnects and assigned a base address. 

## Front End 

The front end de-serialization and alignment logic has changed significantly since DAPHNEv2. In that version I had complex state machines to do the "automatic" alignment. These state machines have been removed and replaced with an AXI-LITE interface which provides access to 13 registers that control the front end logic. The idea here is that we will write a program (or script) that runs in Linux user space and this program controls the alignment process. This program will work closely with the spy buffers to capture, readout, and evaluate the alignment.

### Front End Registers

There are 13 32-bit registers that control the front end. Most registers are read-write and only a few of the 32 bits in each register are used. The address of these registers is relative to the base address assigned to the front end AXI-LITE instance.

	base+0 = Control Register is R/W
		bits 31..3 = don't care
		bit 2 = idelay_en_vtc 
		bit 1 = iserdes_reset
		bit 0 = idelayctrl_reset

	base+4 = Status Register is R/O
		bits 31..1 = zero
		bit 0 = idelayctrl_ready

	base+8 = Trigger Register W/O 
		Write anything to the Trigger Register to force a momentary pulse 
		on the TRIG output. This will force the SPY BUFFERS to capture the
		raw input data. This register is write only and the data you write 
		here doesn't matter.

	base+12 = AFE0 Delay Tap Register all are R/W
	base+16 = AFE1 Delay Tap Register
	base+20 = AFE2 Delay Tap Register
	base+24 = AFE3 Delay Tap Register
	base+28 = AFE4 Delay Tap Register
		bits 31..9 = don't care
		bits 8..0 = IDELAY delay tap value, range 0-511, used for "fine" bit alignment

	base+32 = AFE0 Bitslip Register all are R/W
	base+36 = AFE1 Bitslip Register
	base+40 = AFE2 Bitslip Register
	base+44 = AFE3 Bitslip Register
	base+48 = AFE4 Bitslip Register
		bits 31..4 = don't care
		bits 3..0 = ISERDES "bitslip" value, used for "coarse" word alignment

## Spy Buffers

The input spy buffers are deep enough to store 4k samples. The memory interface has changed from the custom GbE/Captan style to AXI-LITE. 

The spy buffer AXI-LITE interface will need to be configured for a base address (use anything that lines up with a 512k byte boundary), and how big the memory window should be (401408 bytes actual, use 512k bytes). See the file spybuffers.vhd for the complete memory map of the various spy buffers. All spy buffers are 32 bits wide, which means that two 16 bit samples are packed into each 32 bit word. Spy buffer memory blocks are read write. Normally one would not write anything into these buffers, as it would be instantly over-written when a trigger occurs. But writing something to these memory locations and reading it back can be a useful debug feature.

## Timing Endpoint

The timing endpoint firmware is largely unchanged since DAPHNEv2. The output clocks have changed to include 125MHz and the high speed clock changes from 437.5MHz to 500MHz. Endpoint registers are now accessed through an AXI-LITE interface. Note that the AXI registers have changed, there are now fewer registers: clock control register, clock status register, endpoint control register, and endpoint status register. The address of these registers is relative to the base address of the AXI-LITE instance in the timing endpoint module.

### Timing Endpoint Registers

	base+0 = clock control register R/W
		bits 31..3: don't care
		bit 2: clock source (0=local, 1=use endpoint)
		bit 1: MMCM1 reset
		bit 0: general "soft" reset from user

	base+4 = clock status register R/O
		bits 31..2: zero
		bit 1: MMCM1 locked
		bit 0: MMCM0 locked

	base+8 = endpoint control register R/W
		bits 31..17: don't care
		bit 16: endpoint reset
		bits 15..0: endpoint address

	base+12 = endpoint status register R/O
		bits 31..5: zero
		bit 4: endpoint timestamp ok
		bits 3..0: endpoint state machine status "good to go!"

### Timing Endpoint Initialization

Procedure TBD...

## VHDL Package

This package file contains some constants and user defined data types.

## Constraints

Constraints and other build related files will go in the xilinx directory.

## Front End Alignment 

The front end alignment primitives have changed quite a bit since the DAPHNEv2 (Artix 7) firmware was designed. But fundamentally the logic works the same way. Each AFE device has 8 data outputs and one "frame" marker output. The frame marker has the same timing as the data outputs, but it always outputs a fixed pattern "1111111100000000". The frame marker is considered to be a 9th data bit for each AFE. This frame pattern is the key for making the front end alignment work: whatever delays and bitslips are done to make the frame pattern look correct are automatically applied to the other 8 data bits from the same AFE chip. Since the routing delays on all 9 LVDS pairs (within an AFE) are tightly controlled on the layout, the data will then be properly aligned as well.

### First, A Word on Register Bit Twiddling

Many of these registers are tightly packed with control bits, which means that oftentimes one will need to set or clear a bit in these registers without disturbing any other bits in the register. To make this work, you'll need to read-modify-write and use AND and OR operations with bit masks to do what you want.

For example, suppose you need to SET bit 2 in a particular register. Do it like this:

	x = peek(my_reg)
	x = x | 0x00000004
	poke(my_reg,x)

Now suppose you need to CLEAR bit 3 in a particular register. Do it like this:

	x = peek(my_reg)
	x = x & 0xFFFFFFF7
	poke(my_reg,x)

This is how one would do it in an OLD SCHOOL language like C. There is probably some very fancy simpler and much less error prone way to do it in more modern languages!

## Front End Alignment Procedure

1. Configure the timing endpoint and verify that is in a good state. Whenever the timing endpoint or timing master is reset, reconfigured, etc. this procedure will need to be repeated.

2. Initialize the IDELAYCONTROL module. This module is responsible for making sure that the IDELAY delay tap values are calibrated in very small steps (a few picoseconds) and that these delays are constant over chip voltage and temperature changes. First set the "idelayctrl_reset" bit, then clear it. Now read the "idelayctrl_ready" status bit; it should be 1. That means that the IDELAY delay tap values are now calibrated.

3. Configure all AFE chips using the SPI interface. There are several control bits that will need to be changed from the power on default values. From the AFE5808A datasheet:

	* write 0xE000 to address 2, TEST_PATTERN_MODES=111(RAMP)
	* write 0x2000 to address 3, SERIALIZED_DATA_RATE=10(16X)
	* write 0x0008 to address 4, ADC_RESOLUTION_SELECT=14 bit, ADC_OUTPUT_FORMAT=offset binary, LSB_MSB_FIRST=LSB first
	* write 0x0100 to address 10, SYNC_PATTERN=YES

4a. Clear the "idelay_en_vtc" bit. This temporarily disables the circuitry that enables the IDELAY delay tap values to track changes in chip temperature and voltage. 

4b. At this time it's a good idea to reset the ISERDES as well. Set and then clear iserdes_reset control bit.

5. Now sweep the IDELAY tap values and look for the bit edges. There are 512 IDELAY tap values in 7ps steps. The AFE is operating at 62.5MHz and transmitting serial data at 16x, so the data rate is 1Gbps per LVDS pair, or a bit period of 1.0ns. Therefore the width of each data bit is equal to about 142 IDELAY taps.

To do this delay sweep, run this loop:

	for (i=0; i<512; i++)
	{
	  write i to AFE0 Delay Tap Register
	  trigger spy buffers
	  x = the first sample of spybuffer AFE0 channel 8 (frame marker)
	  print i, x
	}

Now you don't really care WHAT raw value is that was captured by the spy buffer. That's not the point. You're looking for the IDELAY tap value that causes it to CHANGE or JUMP. That's the important information. That's how we locate the bit "edges". And you don't need to read out the WHOLE spy buffer for AFE0 channel 8, just the first sample of that spy buffer. That's all we need to see. So the output of that software loop above might look something like this:

	0x000 0xFF00
	0x001 0xFF00
	0x002 0xFF00
	0x003 0xFF00
	0x004 0xFF00
	0x005 0xFE01  ah, starting to change!
	0x006 0xFF00  some "dithering" going on as we're right on the edge
	0x007 0xFE01  now we've changed! ok this is one edge of the bit!
	0x008 0xFE01
	0x009 0xFE01
	0x00A 0xFE01
	0x00B 0xFE01
	...
	0x092 0xFE01
	0x093 0xFE01
	0x094 0xFE01
	0x095 0xFC03  another change, this is the other edge of the bit!
	0x096 0xFC03
	0x097 0xFC03
	0x098 0xFC03
	0x099 0xFC03
	...

What we're looking for here is to find pair of bit edges. The first edge in this example happens around tap value 0x007 and the other edge happens around tap value 0x095. Note that these edges are separated by about 142 taps, just like we would expect. Good, now let's pick the ideal tap value by selecting something smack dab in the middle of the bit, say, tap value 78 or 0x04E. Write this value to the AFE Delay Tap register. OK now we're done with the fine adjustment for AFE0.

6. After completing the prior step we know that we are sampling the high speed data serial right in the center of the data bit, at the most reliable point. But we're not done yet. Now we will need to do the word alignment of the serial data. A high speed shift register is used for this operation. The high speed serial bits are flying down this shift register and we must grab 16 bits at just the right time to form the 16 bit parallel word properly. If we grab the bits one bit too early or one bit too late we'll accidentally grab a bit that belongs to a previous or next AFE sample. 

This is where the BITSLIP operation comes in. We know that the frame maker always sends the same pattern "1111111100000000". So that's what we're looking for, using this simple loop:

	for(b=0;b<15;b++)
	{
	  write b to AFE0 bitslip control register
	  trigger spy buffers
	  x = the first sample of spybuffer AFE0 channel 8 (frame marker)
	  print b, x 
	}

And the output of this loop might look something like this:

	0 0x1FE0
	1 0x3FC0
	2 0x7F80
	3 0xFF00 this is it!!!
	4 0xFE01
	5 0xFC03
	6 0xF807
	7 0xF00F
	8 0xE01F
	9 0xC03F
	A 0x807F
	B 0x00FF
	C 0x01FE
	D 0x03FC
	E 0x07F8
	F 0x0FF0

3 is the correct BITSLIP value, write 3 to the AFE0 bitslip control register. 

So for this AFE0 example the ideal tap value is 0x04E and the bitslip value is 3. These settings will be automatically applied to all data channels for AFE0.

7. Repeat steps 5 and 6 for the remaining AFE four chips.

8. Set the "idelay_en_vtc" control bit. This will ensure that the IDELAY calibrated tap values stay in calibration over voltage and temperature changes. 

9. Now the AFEs are still in "count up" test pattern mode. Let's check it all. Trigger the spy buffers, and dump them all out. AFE channels 0 to 7 should show values counting up by one, and AFE channel 8 should always be 0xFF00 for every sample. Remember, when you read a spy buffer you're reading 32 bits and there are two samples contained in each 32 bit word. The lower 16 bits is the older sample and the upper 16 bits is the newer sample.

10. If everything looks good, let's put the AFEs into normal data taking mode by writing to the SPI interface. From the AFE5808A datasheet:

	* write 0x0000 to address 2, TEST_PATTERN_MODES=000(normal data)
	* write 0x2000 to address 3, SERIALIZED_DATA_RATE=10(16X)
	* write 0x0008 to address 4, ADC_RESOLUTION_SELECT=14 bit, ADC_OUTPUT_FORMAT=offset binary, LSB_MSB_FIRST=LSB first
	* write 0x0100 to address 10, SYNC_PATTERN=YES

11. At any time you can trigger the spy buffers and read them out without impacting any physics operations on DAPHNE. Looking at AFE channel 8 frame marker is a good periodic check to verify that the front end alignment is working properly. 

If there is down time and DAPHNE is not taking physics data, it should be possible to put the AFEs into one of the test modes (writing to AFE SPI address 2) and triggering the spy buffers to verify all data channels are properly aligned. Switching the AFE chips into and out of test pattern modes should not impact any timing so it is not likely this alignment procedure would need to be repeated each time the test pattern modes change in the AFE chips.

