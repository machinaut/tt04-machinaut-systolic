#!/usr/bin/env python
# %%
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge, Timer

from fp import E4M3, E5M2, FP16, fma, is_bin, is_hex

# Should match info.yaml
CLOCK_HZ = 50000000
HALF_CLOCK_PERIOD_NS = 1e9 / (2 * CLOCK_HZ)
EPSILON_NS = HALF_CLOCK_PERIOD_NS / 10


# Reset before every test
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


# Test a single clock cycle
async def test_clock(
    dut,
    *,
    col_in="0",
    col_ctrl_in="0",
    row_in="0",
    row_ctrl_in="0",
    col_out="0",
    col_ctrl_out="0",
    row_out="0",
    row_ctrl_out="0",
):
    # Validate arguments
    assert is_hex(col_in), f"col_in={repr(col_in)}"
    assert is_bin(col_ctrl_in), f"col_ctrl_in={repr(col_ctrl_in)}"
    assert is_hex(row_in), f"row_in={repr(row_in)}"
    assert is_bin(row_ctrl_in), f"row_ctrl_in={repr(row_ctrl_in)}"
    assert is_hex(col_out), f"col_out={repr(col_out)}"
    assert is_bin(col_ctrl_out), f"col_ctrl_out={repr(col_ctrl_out)}"
    assert is_hex(row_out), f"row_out={repr(row_out)}"
    assert is_bin(row_ctrl_out), f"row_ctrl_out={repr(row_ctrl_out)}"
    # Map inputs/outputs to DUT
    ui_in = col_in + row_in
    uio_in = col_ctrl_in + row_ctrl_in + "00"
    uo_out = f"{int(col_out + row_out, 16):08b}"
    uio_out = "000000" + col_ctrl_out + row_ctrl_out

    # Assume that the clock could have been 0 for a while
    await Timer(HALF_CLOCK_PERIOD_NS - (2 * EPSILON_NS), units="ns")
    # Read and assert our outputs
    assert (
        dut.uo_out.value.binstr == uo_out
    ), f"dut.uo_out={dut.uo_out.value.binstr} != {uo_out}"
    assert (
        dut.uio_out.value.binstr == uio_out
    ), f"dut.uio_out={dut.uio_out.value.binstr} != {uio_out}"
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


# Test a block (4 clock cycles)
async def test_block(
    dut,
    *,
    col_in="0000",
    col_ctrl_in="0000",
    row_in="0000",
    row_ctrl_in="0000",
    col_out="0000",
    col_ctrl_out="0000",
    row_out="0000",
    row_ctrl_out="0000",
):
    # Validate arguments, this time all strings of hex digits or binary digits
    assert is_hex(col_in, 4), f"col_in={repr(col_in)}"
    assert is_bin(col_ctrl_in, 4), f"col_ctrl_in={repr(col_ctrl_in)}"
    assert is_hex(row_in, 4), f"row_in={repr(row_in)}"
    assert is_bin(row_ctrl_in, 4), f"row_ctrl_in={repr(row_ctrl_in)}"
    assert is_hex(col_out, 4), f"col_out={repr(col_out)}"
    assert is_bin(col_ctrl_out, 4), f"col_ctrl_out={repr(col_ctrl_out)}"
    assert is_hex(row_out, 4), f"row_out={repr(row_out)}"
    assert is_bin(row_ctrl_out, 4), f"row_ctrl_out={repr(row_ctrl_out)}"
    # Test clock the block
    for i in range(4):
        await test_clock(
            dut,
            col_in=col_in[i],
            col_ctrl_in=col_ctrl_in[i],
            row_in=row_in[i],
            row_ctrl_in=row_ctrl_in[i],
            col_out=col_out[i],
            col_ctrl_out=col_ctrl_out[i],
            row_out=row_out[i],
            row_ctrl_out=row_ctrl_out[i],
        )


# Address for blocks
ADDR = {
    0: {'col_ctrl': '00', 'row_ctrl': '00'},  # passthrough
    1: {'col_ctrl': '00', 'row_ctrl': '10'},  # A-E5 B-E5
    2: {'col_ctrl': '01', 'row_ctrl': '10'},  # A-E4 B-E5
    3: {'col_ctrl': '00', 'row_ctrl': '11'},  # A-E5 B-E4
    4: {'col_ctrl': '01', 'row_ctrl': '11'},  # A-E4 B-E4
    5: {'col_ctrl': '10', 'row_ctrl': '00'},  # C-E5
    6: {'col_ctrl': '10', 'row_ctrl': '01'},  # C-Low
    7: {'col_ctrl': '11', 'row_ctrl': '00'},  # C-High
}
ADDR_IN = {a: {f"{k}_in": f"{v}00" for k, v in v.items()} for a, v in ADDR.items()}
ADDR_OUT = {a: {f"{k}_out": f"{v}00" for k, v in v.items()} for a, v in ADDR.items()}


# Test a sequence of blocks
async def test_sequence(dut, *, blocks):
    for i in range(len(blocks)):
        prev = blocks[i - 1] if i > 0 else {}
        block = blocks[i]
        params = {}
        params.update(ADDR_IN[block.get('a', 0)])
        params.update(ADDR_OUT[prev.get('a', 0)])
        params['col_in'] = block.get('ci', '0000')
        params['row_in'] = block.get('ri', '0000')
        params['col_out'] = block.get('co', prev.get('ci', '0000'))
        params['row_out'] = block.get('ro', prev.get('ri', '0000'))
        await test_block(dut, **params)


# Test that we get zeroes post-reset
@cocotb.test()
async def test_zero(dut):
    dut._log.info("start test_zero")
    await cocotb.start_soon(reset(dut))
    # Go through one zero block
    await test_sequence(dut, blocks=[{}])


# Test passing through random data
@cocotb.test()
async def test_pass(dut):
    dut._log.info("start test_pass")
    await cocotb.start_soon(reset(dut))

    blocks = []
    for _ in range(30):
        ci = f"{random.randint(0, 0xffff):04x}"
        ri = f"{random.randint(0, 0xffff):04x}"
        blocks.append({'ci': ci, 'ri': ri})
    blocks.append({})

    await test_sequence(dut, blocks=blocks)


@cocotb.test()
async def test_AB(dut):
    dut._log.info("start test_AB")
    await cocotb.start_soon(reset(dut))

    await test_block(
        dut,
        col_in="1234",
        row_in="5678",
        col_ctrl_in="0100",
        row_ctrl_in="0100",
    )
    await test_block(
        dut,
        col_out="1234",
        row_out="5678",
        col_ctrl_out="0100",
        row_ctrl_out="0100",
        col_in="abef",
        row_in="face",
        col_ctrl_in="0100",
        row_ctrl_in="0100",
    )
    await test_block(
        dut,
        col_out="abef",
        row_out="face",
        col_ctrl_out="0100",
        row_ctrl_out="0100",
    )
    await test_block(dut)


@cocotb.test()
async def test_shift(dut):
    dut._log.info("start test_shift")
    await cocotb.start_soon(reset(dut))

    # Set C0/C1
    await test_block(
        dut,
        col_in="1234",
        row_in="5678",
        col_ctrl_in="1010",
        row_ctrl_in="1001",
    )
    # Pass block - shifted out old (0) C values, and just passing through data
    await test_block(
        dut,
        col_ctrl_out="1010",
        row_ctrl_out="1001",
        col_in="aaaa",
        row_in="bbbb",
    )
    # Read/Set C0/C1
    await test_block(
        dut,
        col_out="aaaa",
        row_out="bbbb",
        col_in="babe",
        row_in="face",
        col_ctrl_in="1011",
        row_ctrl_in="1000",
    )
    # Two pass blocks
    await test_block(
        dut,
        col_out="1234",
        row_out="5678",
        col_ctrl_out="1011",
        row_ctrl_out="1000",
        col_in="cccc",
        row_in="dddd",
    )
    await test_block(
        dut,
        col_out="cccc",
        row_out="dddd",
        col_in="eeee",
        row_in="ffff",
    )
    # Read/Set C0/C1
    await test_block(
        dut,
        col_out="eeee",
        row_out="ffff",
        col_in="f00d",
        row_in="c0a7",
        col_ctrl_in="1011",
        row_ctrl_in="1000",
    )
    # Read/Clear C0/C1
    await test_block(
        dut,
        col_out="babe",
        row_out="face",
        col_ctrl_out="1011",
        row_ctrl_out="1000",
        col_ctrl_in="1000",
        row_ctrl_in="1000",
    )
    await test_block(
        dut,
        col_out="f00d",
        row_out="c0a7",
        col_ctrl_out="1000",
        row_ctrl_out="1000",
        col_ctrl_in="1000",
        row_ctrl_in="1000",
    )
    await test_block(
        dut,
        col_ctrl_out="1000",
        row_ctrl_out="1000",
    )


@cocotb.test()
async def test_shift2(dut):
    dut._log.info("start test_shift2")
    await cocotb.start_soon(reset(dut))

    # Set C2/C3
    await test_block(
        dut,
        col_in="1234",
        row_in="5678",
        col_ctrl_in="1100",
        row_ctrl_in="1100",
    )
    # Pass block - shifted out old (0) C values, and just passing through data
    await test_block(
        dut,
        col_ctrl_out="1100",
        row_ctrl_out="1100",
        col_in="aaaa",
        row_in="bbbb",
    )
    # Read/Set C0/C1
    await test_block(
        dut,
        col_out="aaaa",
        row_out="bbbb",
        col_in="babe",
        row_in="face",
        col_ctrl_in="1100",
        row_ctrl_in="1100",
    )
    await test_block(
        dut,
        col_out="1234",
        row_out="5678",
        col_ctrl_out="1100",
        row_ctrl_out="1100",
        col_ctrl_in="1100",
        row_ctrl_in="1100",
    )
    await test_block(
        dut,
        col_out="babe",
        row_out="face",
        col_ctrl_out="1100",
        row_ctrl_out="1100",
    )
    await test_block(dut)


@cocotb.test()
async def test_C(dut):
    dut._log.info("start test_C")
    await cocotb.start_soon(reset(dut))

    # Set C0/C1
    await test_block(
        dut,
        col_in="c0c0",
        row_in="c1c1",
        col_ctrl_in="1000",
        row_ctrl_in="1000",
    )
    # Set C2/C3
    await test_block(
        dut,
        col_ctrl_out="1000",
        row_ctrl_out="1000",
        col_in="c2c2",
        row_in="c3c3",
        col_ctrl_in="1100",
        row_ctrl_in="1100",
    )
    # Set C0/C1
    await test_block(
        dut,
        col_ctrl_out="1100",
        row_ctrl_out="1100",
        col_in="3213",
        row_in="7654",
        col_ctrl_in="1000",
        row_ctrl_in="1000",
    )
    # Set C2/C3
    await test_block(
        dut,
        col_out="c0c0",
        row_out="c1c1",
        col_ctrl_out="1000",
        row_ctrl_out="1000",
        col_in="cbac",
        row_in="fede",
        col_ctrl_in="1100",
        row_ctrl_in="1100",
    )
    # Pass 1
    await test_block(
        dut,
        col_out="c2c2",
        row_out="c3c3",
        col_ctrl_out="1100",
        row_ctrl_out="1100",
        col_in="eeee",
        row_in="ffff",
    )
    # Pass 2
    await test_block(
        dut,
        col_out="eeee",
        row_out="ffff",
        col_in="aaaa",
        row_in="bbbb",
    )
    # Pass 3
    await test_block(
        dut,
        col_out="aaaa",
        row_out="bbbb",
        col_in="dddd",
        row_in="cccc",
    )
    # Clear C0/C1
    await test_block(
        dut,
        col_out="dddd",
        row_out="cccc",
        col_ctrl_in="1000",
        row_ctrl_in="1000",
    )
    # Clear C2/C3
    await test_block(
        dut,
        col_out="3213",
        row_out="7654",
        col_ctrl_out="1000",
        row_ctrl_out="1000",
        col_ctrl_in="1100",
        row_ctrl_in="1100",
    )
    # Cleared
    await test_block(
        dut,
        col_out="cbac",
        row_out="fede",
        col_ctrl_out="1100",
        row_ctrl_out="1100",
    )
    # Zero
    await test_block(dut)


def e5mul(A, B):
    assert is_hex(A, 4), f"A={repr(A)}"
    assert is_hex(B, 4), f"B={repr(B)}"
    Ab = f"{int(A, 16):016b}"
    Bb = f"{int(B, 16):016b}"
    assert is_bin(Ab, 16), f"Ab={repr(Ab)}"
    assert is_bin(Bb, 16), f"Bb={repr(Bb)}"
    A0, A1 = Ab[0:8], Ab[8:16]
    B0, B1 = Bb[0:8], Bb[8:16]
    assert is_bin(A0, 8), f"A0={repr(A0)}"
    assert is_bin(A1, 8), f"A1={repr(A1)}"
    assert is_bin(B0, 8), f"B0={repr(B0)}"
    assert is_bin(B1, 8), f"B1={repr(B1)}"
    C0 = ftofp16(e5tof(A0) * e5tof(B0))
    C1 = ftofp16(e5tof(A1) * e5tof(B0))
    C2 = ftofp16(e5tof(A0) * e5tof(B1))
    C3 = ftofp16(e5tof(A1) * e5tof(B1))
    assert is_bin(C0, 16), f"C0={repr(C0)}"
    assert is_bin(C1, 16), f"C1={repr(C1)}"
    assert is_bin(C2, 16), f"C2={repr(C2)}"
    assert is_bin(C3, 16), f"C3={repr(C3)}"
    Cb = C0 + C1 + C2 + C3
    assert is_bin(Cb, 64), f"Cb={repr(Cb)}"
    C = f"{int(Cb, 2):016x}"
    assert is_hex(C, 16), f"C={repr(C)}"
    return C


@cocotb.test()
async def test_1x1_exhaust(dut):
    dut._log.info("start test_1x1_exhaust")
    await cocotb.start_soon(reset(dut))

    for i in range(256):
        A = f"{i:04x}"
        for j in range(256):
            B = f"{j:04x}"
            C = e5mul(A, B)
            dut._log.info(f"   test_1x1_exhaust({i}, {j}) A={A} B={B} C={C}")
            af, bf = e5tof(f"{i:08b}"), e5tof(f"{j:08b}")
            cf = af * bf
            c = f"{int(ftofp16(cf), 2):04x}"
            dut._log.info(f"    af={af} bf={bf} cf={cf} c={c}")
            C0, C1, C2, C3 = C[0:4], C[4:8], C[8:12], C[12:16]

            await test_block(
                dut,
                col_out="0000",
                row_out="0000",
                col_ctrl_out="0000",
                row_ctrl_out="0000",
                col_in=A,
                row_in=B,
                col_ctrl_in="0100",
                row_ctrl_in="0100",
            )
            await test_block(
                dut,
                col_out=A,
                row_out=B,
                col_ctrl_out="0100",
                row_ctrl_out="0100",
                col_in="0000",
                row_in="0000",
                col_ctrl_in="1000",
                row_ctrl_in="1000",
            )
            await test_block(
                dut,
                col_out=C0,
                row_out=C1,
                col_ctrl_out="1000",
                row_ctrl_out="1000",
                col_in="0000",
                row_in="0000",
                col_ctrl_in="1100",
                row_ctrl_in="1100",
            )
            await test_block(
                dut,
                col_out=C2,
                row_out=C3,
                col_ctrl_out="1100",
                row_ctrl_out="1100",
                col_in="0000",
                row_in="0000",
                col_ctrl_in="0000",
                row_ctrl_in="0000",
            )


@cocotb.test()
async def test_mul(dut):
    dut._log.info("start test_mul")
    await cocotb.start_soon(reset(dut))

    rs = random.Random(198)
    A = f"{rs.randint(0, 0xffff):04x}"
    B = f"{rs.randint(0, 0xffff):04x}"
    C = e5mul(A, B)
    C0, C1, C2, C3 = C[0:4], C[4:8], C[8:12], C[12:16]

    await test_block(
        dut,
        col_out="0000",
        row_out="0000",
        col_ctrl_out="0000",
        row_ctrl_out="0000",
        col_in=A,
        row_in=B,
        col_ctrl_in="0100",
        row_ctrl_in="0100",
    )
    await test_block(
        dut,
        col_out=A,
        row_out=B,
        col_ctrl_out="0100",
        row_ctrl_out="0100",
        col_in="c0c0",
        row_in="c1c1",
        col_ctrl_in="1000",
        row_ctrl_in="1000",
    )
    await test_block(
        dut,
        col_out=C0,
        row_out=C1,
        col_ctrl_out="1000",
        row_ctrl_out="1000",
        col_in="c2c2",
        row_in="c3c3",
        col_ctrl_in="1100",
        row_ctrl_in="1100",
    )
    await test_block(
        dut,
        col_out=C2,
        row_out=C3,
        col_ctrl_out="1100",
        row_ctrl_out="1100",
        col_in="0000",
        row_in="0000",
        col_ctrl_in="1000",
        row_ctrl_in="1000",
    )
    await test_block(
        dut,
        col_out="c0c0",
        row_out="c1c1",
        col_ctrl_out="1000",
        row_ctrl_out="1000",
        col_in="0000",
        row_in="0000",
        col_ctrl_in="1100",
        row_ctrl_in="1100",
    )
    await test_block(
        dut,
        col_out="c2c2",
        row_out="c3c3",
        col_ctrl_out="1100",
        row_ctrl_out="1100",
        col_in="0000",
        row_in="0000",
        col_ctrl_in="0000",
        row_ctrl_in="0000",
    )


@cocotb.test()
async def test_spaced_XOR(dut):
    dut._log.info("start test_spaced_XOR")
    await cocotb.start_soon(reset(dut))

    await test_block(
        dut,
        col_out="0000",
        row_out="0000",
        col_ctrl_out="0000",
        row_ctrl_out="0000",
        col_in="1234",
        row_in="5678",
        col_ctrl_in="0100",
        row_ctrl_in="0100",
    )
    await test_block(
        dut,
        col_out="1234",
        row_out="5678",
        col_ctrl_out="0100",
        row_ctrl_out="0100",
        col_in="0000",
        row_in="0000",
        col_ctrl_in="0000",
        row_ctrl_in="0000",
    )
    await test_block(
        dut,
        col_out="0000",
        row_out="0000",
        col_ctrl_out="0000",
        row_ctrl_out="0000",
        col_in="0000",
        row_in="0000",
        col_ctrl_in="0000",
        row_ctrl_in="0000",
    )
    await test_block(
        dut,
        col_out="0000",
        row_out="0000",
        col_ctrl_out="0000",
        row_ctrl_out="0000",
        col_in="c0c0",
        row_in="c1c1",
        col_ctrl_in="1000",
        row_ctrl_in="1000",
    )
    await test_block(
        dut,
        col_out="1256",
        row_out="3456",
        col_ctrl_out="1000",
        row_ctrl_out="1000",
        col_in="c2c2",
        row_in="c3c3",
        col_ctrl_in="1100",
        row_ctrl_in="1100",
    )
    await test_block(
        dut,
        col_out="1278",
        row_out="3478",
        col_ctrl_out="1100",
        row_ctrl_out="1100",
        col_in="0000",
        row_in="0000",
        col_ctrl_in="1000",
        row_ctrl_in="1000",
    )
    await test_block(
        dut,
        col_out="c0c0",
        row_out="c1c1",
        col_ctrl_out="1000",
        row_ctrl_out="1000",
        col_in="0000",
        row_in="0000",
        col_ctrl_in="1100",
        row_ctrl_in="1100",
    )
    await test_block(
        dut,
        col_out="c2c2",
        row_out="c3c3",
        col_ctrl_out="1100",
        row_ctrl_out="1100",
        col_in="0000",
        row_in="0000",
        col_ctrl_in="0000",
        row_ctrl_in="0000",
    )
