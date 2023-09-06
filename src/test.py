#!/usr/bin/env python
# %%
import random
from itertools import product

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
        dut._log.info(f"  test_sequence[{i}] {block}")
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
async def test_shift(dut):
    dut._log.info("start test_shift")
    await cocotb.start_soon(reset(dut))
    blocks = [
        {'a': 6, 'ci': '1234', 'ri': '5678',},
        {'a': 0, 'ci': 'aaaa', 'ri': 'bbbb', 'co': '0000', 'ro': '0000',},
        {'a': 6, 'ci': 'babe', 'ri': 'face',},
        {'a': 0, 'ci': 'cccc', 'ri': 'dddd', 'co': '1234', 'ro': '5678',},
        {'a': 0, 'ci': 'eeee', 'ri': 'ffff',},
        {'a': 6, 'ci': 'f00d', 'ri': 'c0a7',},
        {'a': 6, 'co': 'babe', 'ro': 'face',},
        {'a': 6, 'co': 'f00d', 'ro': 'c0a7',},
        {}
    ]
    await test_sequence(dut, blocks=blocks)


@cocotb.test()
async def test_shift2(dut):
    dut._log.info("start test_shift2")
    await cocotb.start_soon(reset(dut))
    blocks = [
        {'a': 7, 'ci': '1234', 'ri': '5678',},
        {'a': 0, 'ci': 'aaaa', 'ri': 'bbbb', 'co': '0000', 'ro': '0000',},
        {'a': 7, 'ci': 'babe', 'ri': 'face',},
        {'a': 7, 'co': '1234', 'ro': '5678',},
        {'a': 0, 'co': 'babe', 'ro': 'face',},
        {}
    ]
    await test_sequence(dut, blocks=blocks)


@cocotb.test()
async def test_C(dut):
    dut._log.info("start test_C")
    await cocotb.start_soon(reset(dut))
    blocks = [
        {'a': 6, 'ci': 'c0c0', 'ri': 'c1c1',},
        {'a': 7, 'ci': 'c2c2', 'ri': 'c3c3', 'co': '0000', 'ro': '0000',},
        {'a': 6, 'ci': '3213', 'ri': '7654', 'co': '0000', 'ro': '0000',},
        {'a': 7, 'ci': 'cbac', 'ri': 'fede', 'co': 'c0c0', 'ro': 'c1c1',},
        {'a': 0, 'ci': 'eeee', 'ri': 'ffff', 'co': 'c2c2', 'ro': 'c3c3',},
        {'a': 0, 'ci': 'aaaa', 'ri': 'bbbb',},
        {'a': 0, 'ci': 'dddd', 'ri': 'cccc',},
        {'a': 6,},
        {'a': 7, 'co': '3213', 'ro': '7654',},
        {'a': 0, 'co': 'cbac', 'ro': 'fede',},
        {}
    ]
    await test_sequence(dut, blocks=blocks)


def mul22(Ah, Bh):
    assert is_hex(Ah, 4), f"Ah={repr(Ah)}"
    assert is_hex(Bh, 4), f"Bh={repr(Bh)}"
    A0, A1 = E5M2.fromh(Ah[0:2]), E5M2.fromh(Ah[2:4])
    B0, B1 = E5M2.fromh(Bh[0:2]), E5M2.fromh(Bh[2:4])
    C0 = fma(A0, B0)
    C1 = fma(A1, B0)
    C2 = fma(A0, B1)
    C3 = fma(A1, B1)
    Ch = C0.h + C1.h + C2.h + C3.h
    assert is_hex(Ch, 16), f"Ch={repr(Ch)}"
    return Ch


@cocotb.test()
async def test_1x1(dut):
    dut._log.info("start test_1x1")
    await cocotb.start_soon(reset(dut))

    # TODO: Do E4M3 format combinations
    # values = list(product(range(256), range(256)))
    values = [(random.randint(0, 255), random.randint(0, 255)) for _ in range(30)]
    for i, j in values:
        Ah = f"{i:02x}00" if random.random() < 0.5 else f"00{i:02x}"
        Bh = f"{j:02x}00" if random.random() < 0.5 else f"00{j:02x}"
        Ch = mul22(Ah, Bh)
        dut._log.info(f"  test_1x1 {Ah} {Bh} {Ch}")
        blocks = [
            {'a': 1, 'ci': Ah, 'ri': Bh,},
            {'a': 6,},
            {'a': 7, 'co': Ch[0:4], 'ro': Ch[4:8],},
            {'a': 0, 'co': Ch[8:12], 'ro': Ch[12:16],},
            {},
        ]
        await test_sequence(dut, blocks=blocks)


@cocotb.test()
async def test_2x2(dut):
    dut._log.info("start test_2x2")
    await cocotb.start_soon(reset(dut))

    # TODO: Do E4M3 format combinations
    values = [(random.randint(0, 0xffff), random.randint(0, 0xffff)) for _ in range(30)]
    for i, j in values:
        Ah = f"{i:04x}"
        Bh = f"{j:04x}"
        Ch = mul22(Ah, Bh)
        dut._log.info(f"  test_2x2 {Ah} {Bh} {Ch}")
        blocks = [
            {'a': 1, 'ci': Ah, 'ri': Bh,},
            {'a': 6,},
            {'a': 7, 'co': Ch[0:4], 'ro': Ch[4:8],},
            {'a': 0, 'co': Ch[8:12], 'ro': Ch[12:16],},
            {},
        ]
        await test_sequence(dut, blocks=blocks)



@cocotb.test()
async def test_Cshort(dut):
    dut._log.info("start test_Cshort")
    await cocotb.start_soon(reset(dut))
    # TODO: do actual numbers instead of NANs
    for _ in range(30):
        Ch = f"{random.randint(0, 2**64-1):016x}"
        assert is_hex(Ch, 16), f"Ch={repr(Ch)}"
        C0 = FP16.fromh(Ch[0:4])
        C1 = FP16.fromh(Ch[4:8])
        C2 = FP16.fromh(Ch[8:12])
        C3 = FP16.fromh(Ch[12:16])
        E0 = E5M2.fromf(C0.f)
        E1 = E5M2.fromf(C1.f)
        E2 = E5M2.fromf(C2.f)
        E3 = E5M2.fromf(C3.f)
        dut._log.info(f"  test_Cshort {Ch} {E0.h} {E1.h} {E2.h} {E3.h}")
        blocks = [
            {'a': 6, 'ci': C0.h, 'ri': C1.h,},
            {'a': 7, 'ci': C2.h, 'ri': C3.h, 'co': '0000', 'ro': '0000',},
            {'a': 5, 'co': '0000', 'ro': '0000',},
            {'a': 0, 'co': E0.h + E2.h, 'ro': E1.h + E3.h,},
            {}
        ]
        await test_sequence(dut, blocks=blocks)
