#!/usr/bin/env python
# %%
import random
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ClockCycles

# Should match info.yaml (note )
CLOCK_HZ = 50000000
HALF_CLOCK_PERIOD_NS = 1e9 / (2 * CLOCK_HZ)
EPSILON_NS = HALF_CLOCK_PERIOD_NS / 10


def valid_hex(s, l=1):
    return isinstance(s, str) and len(s) == l and 0 <= int(s, 16) < 2 ** (4 * l)

def valid_bin(s, l=1):
    return isinstance(s, str) and len(s) == l and 0 <= int(s, 2) < 2 ** l


# Handle clocking as well as input/output mapping for test
async def test_clock(dut, *, col_in, col_ctrl_in, row_in, row_ctrl_in, col_out, col_ctrl_out, row_out, row_ctrl_out):
    # Validate arguments
    assert valid_hex(col_in), f"col_in={repr(col_in)}"
    assert valid_bin(col_ctrl_in), f"col_ctrl_in={repr(col_ctrl_in)}"
    assert valid_hex(row_in), f"row_in={repr(row_in)}"
    assert valid_bin(row_ctrl_in), f"row_ctrl_in={repr(row_ctrl_in)}"
    assert valid_hex(col_out), f"col_out={repr(col_out)}"
    assert valid_bin(col_ctrl_out), f"col_ctrl_out={repr(col_ctrl_out)}"
    assert valid_hex(row_out), f"row_out={repr(row_out)}"
    assert valid_bin(row_ctrl_out), f"row_ctrl_out={repr(row_ctrl_out)}"
    # Map inputs/outputs to DUT
    ui_in = col_in + row_in
    uio_in = col_ctrl_in + row_ctrl_in + '00'
    uo_out = f"{int(col_out + row_out, 16):08b}"
    uio_out = '000000' + col_ctrl_out + row_ctrl_out

    # Assume that the clock could have been 0 for a while
    await Timer(HALF_CLOCK_PERIOD_NS - (2 * EPSILON_NS), units="ns")
    # Read and assert our outputs
    assert dut.uo_out.value.binstr == uo_out, f"dut.uo_out={dut.uo_out.value.binstr} != {uo_out}"
    assert dut.uio_out.value.binstr == uio_out, f"dut.uio_out={dut.uio_out.value.binstr} != {uio_out}"
    # Wait a small amount before setting inputs
    await Timer(EPSILON_NS, units="ns")
    # Set inputs
    dut.ui_in.value = int(ui_in, 16)
    dut.uio_in.value = int(uio_in, 2)
    # Wait a small amount before sending positive clock edge
    await Timer(EPSILON_NS, units="ns")
    # Send positive clock edge
    dut.clk.value = 1
    # Wait half a clock period
    await Timer(HALF_CLOCK_PERIOD_NS, units="ns")
    # Send negative clock edge
    dut.clk.value = 0
    # Done, next test_clock can start immediately


async def test_block(dut, *, col_in, col_ctrl_in, row_in, row_ctrl_in, col_out, col_ctrl_out, row_out, row_ctrl_out):
    # Validate arguments, this time all strings of hex digits or binary digits
    assert valid_hex(col_in, 4), f"col_in={repr(col_in)}"
    assert valid_bin(col_ctrl_in, 4), f"col_ctrl_in={repr(col_ctrl_in)}"
    assert valid_hex(row_in, 4), f"row_in={repr(row_in)}"
    assert valid_bin(row_ctrl_in, 4), f"row_ctrl_in={repr(row_ctrl_in)}"
    assert valid_hex(col_out, 4), f"col_out={repr(col_out)}"
    assert valid_bin(col_ctrl_out, 4), f"col_ctrl_out={repr(col_ctrl_out)}"
    assert valid_hex(row_out, 4), f"row_out={repr(row_out)}"
    assert valid_bin(row_ctrl_out, 4), f"row_ctrl_out={repr(row_ctrl_out)}"
    # Test clock the block
    for i in range(4):
        await test_clock(dut,
            col_in=col_in[i], col_ctrl_in=col_ctrl_in[i],
            row_in=row_in[i], row_ctrl_in=row_ctrl_in[i],
            col_out=col_out[i], col_ctrl_out=col_ctrl_out[i],
            row_out=row_out[i], row_ctrl_out=row_ctrl_out[i])


async def reset(dut):
    dut._log.info("reset")
    dut.rst_n.value = 0
    dut.clk.value = 0
    await Timer(HALF_CLOCK_PERIOD_NS, units="ns")
    dut.clk.value = 1
    await Timer(HALF_CLOCK_PERIOD_NS, units="ns")
    dut.clk.value = 0
    await Timer(HALF_CLOCK_PERIOD_NS, units="ns")
    dut.rst_n.value = 1


@cocotb.test()
async def test_zero(dut):
    dut._log.info("start test_zero")
    await cocotb.start_soon(reset(dut))
    # Go through one zero block
    await test_block(dut,
        col_in="0000",  col_ctrl_in="0000",
        row_in="0000",  row_ctrl_in="0000",
        col_out="0000", col_ctrl_out="0000",
        row_out="0000", row_ctrl_out="0000")


@cocotb.test()
async def test_pass(dut):
    dut._log.info("start test_pass")
    await cocotb.start_soon(reset(dut))

    # Go through one block
    await test_block(dut,
        col_in="1234",  col_ctrl_in="0010",
        row_in="5678",  row_ctrl_in="0001",
        col_out="0000", col_ctrl_out="0000",
        row_out="0000", row_ctrl_out="0000")
    # Go through second block
    await test_block(dut,
        col_in="abcd",  col_ctrl_in="0000",
        row_in="ef01",  row_ctrl_in="0011",
        col_out="1234", col_ctrl_out="0010",
        row_out="5678", row_ctrl_out="0001")
    # Send zero block
    await test_block(dut,
        col_in="0000",  col_ctrl_in="0000",
        row_in="0000",  row_ctrl_in="0000",
        col_out="abcd", col_ctrl_out="0000",
        row_out="ef01", row_ctrl_out="0011")
    # Check zero block
    await test_block(dut,
        col_in="0000",  col_ctrl_in="0000",
        row_in="0000",  row_ctrl_in="0000",
        col_out="0000", col_ctrl_out="0000",
        row_out="0000", row_ctrl_out="0000")


@cocotb.test()
async def test_shift(dut):
    dut._log.info("start test_shift")
    await cocotb.start_soon(reset(dut))

    # Set C0/C1
    await test_block(dut,
        col_out="0000", row_out="0000", col_ctrl_out="0000", row_ctrl_out="0000",
        col_in="1234",  row_in="5678",  col_ctrl_in="1010",  row_ctrl_in="1001",
    )
    # Pass block - shifted out old (0) C values, and just passing through data
    await test_block(dut,
        col_out="0000", row_out="0000", col_ctrl_out="1010", row_ctrl_out="1001",
        col_in="aaaa",  row_in="bbbb",  col_ctrl_in="0010",  row_ctrl_in="0001",
    )
    # Read/Set C0/C1
    await test_block(dut,
        col_out="aaaa", row_out="bbbb", col_ctrl_out="0010", row_ctrl_out="0001",
        col_in="babe",  row_in="face",  col_ctrl_in="1011",  row_ctrl_in="1000",
    )
    # Two pass blocks
    await test_block(dut,
        col_out="1234", row_out="5678", col_ctrl_out="1011", row_ctrl_out="1000",
        col_in="cccc",  row_in="dddd",  col_ctrl_in="0000",  row_ctrl_in="0011",
    )
    await test_block(dut,
        col_out="cccc", row_out="dddd", col_ctrl_out="0000", row_ctrl_out="0011",
        col_in="eeee",  row_in="ffff",  col_ctrl_in="0010",  row_ctrl_in="0010",
    )
    # Read/Set C0/C1
    await test_block(dut,
        col_out="eeee", row_out="ffff", col_ctrl_out="0010", row_ctrl_out="0010",
        col_in="f00d",  row_in="c0a7",  col_ctrl_in="1011",  row_ctrl_in="1000",
    )
    # Read/Clear C0/C1
    await test_block(dut,
        col_out="babe", row_out="face", col_ctrl_out="1011", row_ctrl_out="1000",
        col_in="0000",  row_in="0000",  col_ctrl_in="1000",  row_ctrl_in="1000",
    )
    await test_block(dut,
        col_out="f00d", row_out="c0a7", col_ctrl_out="1000", row_ctrl_out="1000",
        col_in="0000",  row_in="0000",  col_ctrl_in="1000",  row_ctrl_in="1000",
    )
    await test_block(dut,
        col_out="0000", row_out="0000", col_ctrl_out="1000", row_ctrl_out="1000",
        col_in="0000",  row_in="0000",  col_ctrl_in="0000",  row_ctrl_in="0000",
    )

@cocotb.test()
async def test_shift2(dut):
    dut._log.info("start test_shift2")
    await cocotb.start_soon(reset(dut))

    # Set C2/C3
    await test_block(dut,
        col_out="0000", row_out="0000", col_ctrl_out="0000", row_ctrl_out="0000",
        col_in="1234",  row_in="5678",  col_ctrl_in="1100",  row_ctrl_in="1100",
    )
    # Pass block - shifted out old (0) C values, and just passing through data
    await test_block(dut,
        col_out="0000", row_out="0000", col_ctrl_out="1100", row_ctrl_out="1100",
        col_in="aaaa",  row_in="bbbb",  col_ctrl_in="0000",  row_ctrl_in="0000",
    )
    # Read/Set C0/C1
    await test_block(dut,
        col_out="aaaa", row_out="bbbb", col_ctrl_out="0000", row_ctrl_out="0000",
        col_in="babe",  row_in="face",  col_ctrl_in="1100",  row_ctrl_in="1100",
    )
    await test_block(dut,
        col_out="1234", row_out="5678", col_ctrl_out="1100", row_ctrl_out="1100",
        col_in="0000",  row_in="0000",  col_ctrl_in="1100",  row_ctrl_in="1100",
    )
    await test_block(dut,
        col_out="babe", row_out="face", col_ctrl_out="1100", row_ctrl_out="1100",
        col_in="0000",  row_in="0000",  col_ctrl_in="0000",  row_ctrl_in="0000",
    )
    await test_block(dut,
        col_out="0000", row_out="0000", col_ctrl_out="0000", row_ctrl_out="0000",
        col_in="0000",  row_in="0000",  col_ctrl_in="0000",  row_ctrl_in="0000",
    )

@cocotb.test()
async def test_C(dut):
    dut._log.info("start test_C")
    await cocotb.start_soon(reset(dut))

    # Set C0/C1
    await test_block(dut,
        col_out="0000", row_out="0000", col_ctrl_out="0000", row_ctrl_out="0000",
        col_in="c0c0",  row_in="c1c1",  col_ctrl_in="1000",  row_ctrl_in="1000",
    )
    # Set C2/C3
    await test_block(dut,
        col_out="0000", row_out="0000", col_ctrl_out="1000", row_ctrl_out="1000",
        col_in="c2c2",  row_in="c3c3",  col_ctrl_in="1100",  row_ctrl_in="1100",
    )
    # Set C0/C1
    await test_block(dut,
        col_out="0000", row_out="0000", col_ctrl_out="1100", row_ctrl_out="1100",
        col_in="3213",  row_in="7654",  col_ctrl_in="1000",  row_ctrl_in="1000",
    )
    # Set C2/C3
    await test_block(dut,
        col_out="c0c0", row_out="c1c1", col_ctrl_out="1000", row_ctrl_out="1000",
        col_in="cbac",  row_in="fede",  col_ctrl_in="1100",  row_ctrl_in="1100",
    )
    # Pass 1
    await test_block(dut,
        col_out="c2c2", row_out="c3c3", col_ctrl_out="1100", row_ctrl_out="1100",
        col_in="eeee",  row_in="ffff",  col_ctrl_in="0000",  row_ctrl_in="0000",
    )
    # Pass 2
    await test_block(dut,
        col_out="eeee", row_out="ffff", col_ctrl_out="0000", row_ctrl_out="0000",
        col_in="aaaa",  row_in="bbbb",  col_ctrl_in="0000",  row_ctrl_in="0000",
    )
    # Pass 3
    await test_block(dut,
        col_out="aaaa", row_out="bbbb", col_ctrl_out="0000", row_ctrl_out="0000",
        col_in="dddd",  row_in="cccc",  col_ctrl_in="0000",  row_ctrl_in="0000",
    )
    # Clear C0/C1
    await test_block(dut,
        col_out="dddd", row_out="cccc", col_ctrl_out="0000", row_ctrl_out="0000",
        col_in="0000",  row_in="0000",  col_ctrl_in="1000",  row_ctrl_in="1000",
    )
    # Clear C2/C3
    await test_block(dut,
        col_out="3213", row_out="7654", col_ctrl_out="1000", row_ctrl_out="1000",
        col_in="0000",  row_in="0000",  col_ctrl_in="1100",  row_ctrl_in="1100",
    )
    # Cleared
    await test_block(dut,
        col_out="cbac", row_out="fede", col_ctrl_out="1100", row_ctrl_out="1100",
        col_in="0000",  row_in="0000",  col_ctrl_in="0000",  row_ctrl_in="0000",
    )
    # Zero
    await test_block(dut,
        col_out="0000", row_out="0000", col_ctrl_out="0000", row_ctrl_out="0000",
        col_in="0000",  row_in="0000",  col_ctrl_in="0000",  row_ctrl_in="0000",
    )