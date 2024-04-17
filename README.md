# daphne3
Kria Zynq UltraScale+ firmware for the PL 

This is not the complete firmware design for the Kria PL side, but rather some of the major components that will need to be instantiated at the top level.

## DAPHNE3 Entity

Currently the Kria top level entity is a graphical schematic which has blocks for the PS, AXI interconnects, various IP blocks, and custom blocks. This entity, DAPHNE3 will become another block in this top level schematic. There are two AXI-LITE slave interfaces exposed: one for the Front End control register and another AXI-LITE slave interface for the spy buffers. Each of these interfaces will need to be connected to the AXI interconnects and assigned a base address. 

## Front End 

The front end de-serialization and alignment logic has changed significantly since DAPHNEv2. In that version I had complex state machines to do the "automatic" alignment. These state machines have been removed and replaced with an AXI-LITE interface which provides access to 13 registers that control the front end logic. The idea here is that we will write a program (or script) that runs in Linux user space and this program controls the alignment process. This program will work closely with the spy buffers to capture, readout, and evaluate the alignment.

The front end alignment primitives have changed quite a bit since the DAPHNEv2 (Artix 7) firmware was designed. But fundamentally the logic works the same way. First, the IDELAY delay elements are swept to determine where the bit edges are located, then a safe center operating delay value is selected. Next, the ISERDES element is reset and the parallel word is evaluated by triggering and reading out the spy buffers. If the alignment/framing is not correct, the "bitslip" value is changed and the process is repeated until the frame marker is correct. The assumption here is that whatever manipulations are done to the frame marker channel are also applied to all other channels FROM THAT AFE.

There are 13 registers that control the front end. Most registers are read-write. The status register is read only. The trigger register is write only. The location of these 13 registers is relative to the base address specified for the front end AXI-LITE slave interface. Details on these registers and what the bits mean is described in frontend/fe_axi.vhd

## Spy Buffers

The input spy buffers are deep enough to store 4k samples. The memory interface has changed from the custom GbE/Captan style to AXI-LITE. 

The spy buffer AXI-LITE interface will need to be configured for a base address (use anything that lines up with a 512k byte boundary), and how big the memory window should be (401408 bytes actual, use 512k bytes). See the file spybuffers.vhd for the complete memory map of the various spy buffers. All spy buffers are 32 bits wide, which means that two 16 bit samples are packed into each 32 bit word. Spy buffer memory blocks are read write. Normally one would not write anything into these buffers, as it would be instantly over-written when a trigger occurs. But writing something to these memory locations and reading it back can be a useful debug feature.

## Timing Endpoint

The timing endpoint firmware is largely unchanged since DAPHNEv2. The output clocks have changed to include 125MHz and the high speed clock changes from 437.5MHz to 500MHz. Endpoint registers are now accessed through an AXI-LITE interface.

## VHDL Package

This package file contains some constants and user defined data types.

## Constraints

Constraints and other build related files will go in the xilinx directory.



