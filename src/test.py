#!/usr/bin/env python
# %%
import random
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ClockCycles


def zero_block():
    return {'col_in': 0, 'row_in': 0, 'col_out': 0, 'row_out': 0, 'col_ctrl_in': 0, 'row_ctrl_in': 0, 'col_ctrl_out': 0, 'row_ctrl_out': 0}


def random_sequence(seed, N=10):
    assert isinstance(seed, int), f"seed={repr(seed)} must be int"
    rs = random.Random(seed)
    return {
        'cols': [rs.randint(0, 2**16-1) for _ in range(N)],
        'rows': [rs.randint(0, 2**16-1) for _ in range(N)],
        'col_ctrls': [rs.randint(0, 7) for _ in range(N)],
        'row_ctrls': [rs.randint(0, 7) for _ in range(N)],
    }


async def check_block(dut, col_in, row_in, col_ctrl_in, row_ctrl_in, col_out=None, row_out=None, col_ctrl_out=None, row_ctrl_out=None):
    assert isinstance(col_in, int) and 0 <= col_in < (2**16), f"col_in={col_in}"
    assert isinstance(row_in, int) and 0 <= row_in < (2**16), f"row_in={row_in}"
    assert isinstance(col_ctrl_in, int) and 0 <= col_ctrl_in < (2**4), f"col_ctrl_in={col_ctrl_in}"
    assert isinstance(row_ctrl_in, int) and 0 <= row_ctrl_in < (2**4), f"row_ctrl_in={row_ctrl_in}"
    check_out = col_out is not None

    if check_out:
        assert isinstance(col_out, int) and 0 <= col_out < (2**16), f"col_out={col_out}"
        assert isinstance(row_out, int) and 0 <= row_out < (2**16), f"row_out={row_out}"
        assert isinstance(col_ctrl_out, int) and 0 <= col_ctrl_out < (2**4), f"col_ctrl_out={col_ctrl_out}"
        assert isinstance(row_ctrl_out, int) and 0 <= row_ctrl_out < (2**4), f"row_ctrl_out={row_ctrl_out}"
    else:
        assert col_out is None, f"col_out={col_out}"
        assert row_out is None, f"row_out={row_out}"
        assert col_ctrl_out is None, f"col_ctrl_out={col_ctrl_out}"
        assert row_ctrl_out is None, f"row_ctrl_out={row_ctrl_out}"

    col_in_h = f"{col_in:04x}"
    row_in_h = f"{row_in:04x}"
    col_ctrl_in_b = f"{col_ctrl_in:04b}"
    row_ctrl_in_b = f"{row_ctrl_in:04b}"
    if check_out:
        col_out_h = f"{col_out:04x}"
        row_out_h = f"{row_out:04x}"
        col_ctrl_out_b = f"{col_ctrl_out:04b}"
        row_ctrl_out_b = f"{row_ctrl_out:04b}"
    for i in range(4):
        await Timer(3, units="us")
        ui_in = int(col_in_h[i] + row_in_h[i], 16)
        dut.ui_in.value = ui_in
        uio_in = int(col_ctrl_in_b[i] + row_ctrl_in_b[i] + '00', 2)
        dut.uio_in.value = uio_in
        if check_out:
            uo_out = int(col_out_h[i] + row_out_h[i], 16)
            assert dut.uo_out.value == uo_out, f"i={i}, dut.uo_out={dut.uo_out.value} != {uo_out}"
            uio_out = int(col_ctrl_out_b[i] + row_ctrl_out_b[i], 2)
            assert dut.uio_out.value == uio_out, f"i={i}, dut.uio_out={dut.uio_out.value} != {uio_out}"
        await ClockCycles(dut.clk, 1, rising=False)


async def check_sequence(dut, cols, rows, col_ctrls, row_ctrls):
    dut._log.info("check_sequence")
    N = len(cols)
    assert len(rows) == N, f"{len(rows)} != {N}"
    assert len(col_ctrls) == N, f"{len(col_ctrls)} != {N}"
    assert len(row_ctrls) == N, f"{len(row_ctrls)} != {N}"
    for i in range(N):
        col_in = cols[i]
        row_in = rows[i]
        col_ctrl_in = col_ctrls[i]
        row_ctrl_in = row_ctrls[i]
        if i:
            col_out = cols[i-1]
            row_out = rows[i-1]
            col_ctrl_out = col_ctrls[i-1]
            row_ctrl_out = row_ctrls[i-1]
            await check_block(dut, col_in, row_in, col_ctrl_in, row_ctrl_in, col_out, row_out, col_ctrl_out, row_ctrl_out)
        else:
            await check_block(dut, col_in, row_in, col_ctrl_in, row_ctrl_in)


async def check_random_sequence(dut, seed, N=10):
    await check_sequence(dut, **random_sequence(seed, N=N))


async def reset(dut):
    dut._log.info("reset")
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 2, rising=False)
    await Timer(1, units="us")
    dut.rst_n.value = 1


@cocotb.test()
async def test_block(dut):
    dut._log.info("start")
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())

    # Start with a reset
    await reset(dut)
    # Go through one blocks
    for i in range(4):
        await Timer(3, units="us")
        dut.ui_in.value = (0x0f - i + (i << 4)) % 256
        await ClockCycles(dut.clk, 1, rising=False)
    # Go through second block
    for i in range(4):
        await Timer(3, units="us")
        dut.ui_in.value = (0x34 + i + (i << 4)) % 256
        await ClockCycles(dut.clk, 1, rising=False)
    # Go through third block
    for i in range(4):
        await Timer(3, units="us")
        dut.ui_in.value = (0x56 + i + (i << 4)) % 256
        await ClockCycles(dut.clk, 1, rising=False)

    # Settle
    await reset(dut)
    await Timer(20, units="us")



@cocotb.test()
async def test_check_random_sequence(dut):
    dut._log.info("start")
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())

    # Start with a reset
    await reset(dut)
    # Block sequence
    await check_random_sequence(dut, seed=0)
    # Reset again
    await reset(dut)
    # Block sequence again
    await check_random_sequence(dut, seed=1)
    # Settle
    await reset(dut)
    await Timer(20, units="us")


@cocotb.test()
async def test_check_xor_sequence(dut):
    dut._log.info("start")
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())

    # Start with a reset
    await reset(dut)

    # Make sequence
    dut._log.info("xor sequence")
    for i in range(16):
        await check_block(dut, col_in=1 << i, row_in=0, col_ctrl_in=0, row_ctrl_in=0)
    # Flush sequence
    dut._log.info("flush")
    await check_block(dut, col_in=0, row_in=0, col_ctrl_in=0, row_ctrl_in=0)
    # Read out accumulated xor
    dut._log.info("read xor")
    await check_block(dut, col_in=0, row_in=0, col_ctrl_in=0b1000, row_ctrl_in=0b1000,
                        col_out=0, row_out=0, col_ctrl_out=0, row_ctrl_out=0)
    await check_block(dut, col_in=0xFF00, row_in=0xFF00, col_ctrl_in=0b1100, row_ctrl_in=0b1100,
                        col_out=0xFF00, row_out=0xFF00, col_ctrl_out=0b1000, row_ctrl_out=0b1000)
    await check_block(dut, col_in=0xFF00, row_in=0xFF00, col_ctrl_in=0, row_ctrl_in=0,
                        col_out=0xFF00, row_out=0xFF00, col_ctrl_out=0b1100, row_ctrl_out=0b1100)

    # Settle
    await reset(dut)
    await Timer(20, units="us")
