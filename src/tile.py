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
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 2, rising=False)
    await Timer(1, units="us")
    dut.rst_n.value = 1
    # Go through one blocks
    col_ctl = bin(0xcafe)[2:]
    row_ctl = bin(0xbabe)[2:]
    for i in range(16):
        await Timer(3, units="us")
        dut.col_in.value = 0x12 + i
        dut.row_in.value = 0x34 + i
        dut.col_ctrl_in.value = int(col_ctl[i]*2, 2)
        dut.row_ctrl_in.value = int(row_ctl[i]*2, 2)
        await ClockCycles(dut.clk, 1, rising=False)
    # Go through second block
    for i in range(16):
        await Timer(3, units="us")
        dut.col_in.value = 0x56 + i
        dut.row_in.value = 0x78 + i
        dut.col_ctrl_in.value = 0
        dut.row_ctrl_in.value = 0
        await ClockCycles(dut.clk, 1, rising=False)
    # Go through third block
    for i in range(16):
        await Timer(3, units="us")
        dut.col_in.value = 0x9a + i
        dut.row_in.value = 0xbc + i
        await ClockCycles(dut.clk, 1, rising=False)

    # Reset again
    dut._log.info("reset")
    await Timer(1, units="us")
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 1, rising=False)
    dut.rst_n.value = 1

