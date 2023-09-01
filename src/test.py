#!/usr/bin/env python
# %%
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ClockCycles


@cocotb.test()
async def test_block(dut):
    dut._log.info("start")
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())

    # Start with a reset
    dut._log.info("reset")
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 2, rising=False)
    await Timer(1, units="us")
    dut.rst_n.value = 1
    # Go through one blocks
    for i in range(16):
        await Timer(3, units="us")
        dut.ui_in.value = 0x11 # (i << 4) + ((15 - i) % 16)
        await ClockCycles(dut.clk, 1, rising=False)
    # Go through second block
    for i in range(16):
        await Timer(3, units="us")
        dut.ui_in.value = 0x22 # ((15 - i) << 4) + (i % 16)
        await ClockCycles(dut.clk, 1, rising=False)
    # Go through third block
    for i in range(16):
        await Timer(3, units="us")
        dut.ui_in.value = 0x33
        await ClockCycles(dut.clk, 1, rising=False)

    # Reset again
    dut._log.info("reset")
    await Timer(1, units="us")
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 1, rising=False)
    dut.rst_n.value = 1

