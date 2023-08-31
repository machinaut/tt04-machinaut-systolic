#!/usr/bin/env python
# %%
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ClockCycles


@cocotb.test()
async def test_basic(dut):
    dut._log.info("start")
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())

    # reset
    dut._log.info("reset")
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 1)
    dut.rst_n.value = 1
    # Read in values
    dut.uio_in.value = 0
    # Go through two blocks
    for i in range(16):
        dut.ui_in.value = 64 + i
        await ClockCycles(dut.clk, 1)
        assert dut.uo_out.value == 0, f"i={i}, dut.uo_out.value={dut.uo_out.value}"
    # Go through second block
    for i in range(16):
        dut.ui_in.value = 96 + i
        await ClockCycles(dut.clk, 1)
        assert dut.uo_out.value == 64 + i, f"i={i}, dut.uo_out.value={dut.uo_out.value}"

    # Reset again
    dut._log.info("reset")
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rst_n.value = 1
    assert dut.uo_out.value == 0

