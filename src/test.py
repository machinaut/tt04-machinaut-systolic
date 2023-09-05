#!/usr/bin/env python
# %%
import random
import bisect
import cocotb
from functools import lru_cache
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ClockCycles


def is_bits(s, l=None):
    return isinstance(s, str) and len(s) and all(c in '01' for c in s) and (l is None or len(s) == l)

def is_hexs(s, l=None):
    return isinstance(s, str) and len(s) and all(c in '0123456789abcdef' for c in s.lower()) and (l is None or len(s) == l)



@lru_cache(maxsize=None)
def tof(sig, exp, man):
    assert is_bits(sig, 1), f"sig={repr(sig)}"
    assert is_bits(exp, 5), f"exp={repr(exp)}"
    assert is_bits(man), f"man={repr(man)}"

    sign = -1 if sig == '1' else 1

    if exp == '11111':
        if int(man) == 0:
            return sign * float('inf')
        return float('nan')
    
    if exp == '00000':
        frac = int(man, 2) / (1 << len(man))
        pow = 2 ** -14
    else:
        frac = 1.0 + int(man, 2) / (1 << len(man))
        pow = 2 ** (int(exp, 2) - 15)
    return sign * frac * pow


@lru_cache(maxsize=None)
def e5tof(s):
    assert is_bits(s, 8), f"s={repr(s)}"
    sig, exp, man = s[0], s[1:6], s[6:]
    assert is_bits(man, 2), f"man={repr(man)}"
    return tof(sig, exp, man)


@lru_cache(maxsize=None)
def fp16tof(s):
    assert is_bits(s, 16), f"s={repr(s)}"
    sig, exp, man = s[0], s[1:6], s[6:]
    assert is_bits(man, 10), f"man={repr(man)}"
    return tof(sig, exp, man)

E5MAX = e5tof('01111011')
E5MIN = e5tof('00000001')
FP16MAX = fp16tof('0111101111111111')
FP16MIN = fp16tof('0000000000000001')

# Use binary search to find the nearest e5 value
def ftoe5(f):
    assert isinstance(f, float), f"f={repr(f)}"
    sig = '1' if f < 0 else '0'
    if f != f:
        return '01111101'
    if abs(f) > E5MAX:
        return sig + '1111100'
    if abs(f) <= E5MIN / 2:
        return '00000000'
    if abs(f) <= E5MIN:
        return sig + '0000001'

    val = sig
    for i in range(1, 8):
        assert len(val) == i
        low = val + '0' + '1' * (7 - i)
        high = val + '1' + '0' * (7 - i)
        if abs(f - e5tof(low)) < abs(f - e5tof(high)):
            val = val + '0'
        else:
            val = val + '1'

    return val

# Same but for fp16
def ftofp16(f):
    assert isinstance(f, float), f"f={repr(f)}"
    sig = '1' if f < 0 else '0'
    if f != f:
        return '0111110000000001'
    if abs(f) > FP16MAX:
        return sig + '111110000000000'
    if abs(f) <= FP16MIN / 2:
        return '0000000000000000'
    if abs(f) <= FP16MIN:
        return sig + '000000000000001'

    val = sig
    for i in range(1, 16):
        assert len(val) == i
        low = val + '0' + '1' * (15 - i)
        high = val + '1' + '0' * (15 - i)
        if abs(f - fp16tof(low)) < abs(f - fp16tof(high)):
            val = val + '0'
        else:
            val = val + '1'

    return val


# Should match info.yaml
CLOCK_HZ = 50000000
HALF_CLOCK_PERIOD_NS = 1e9 / (2 * CLOCK_HZ)
EPSILON_NS = HALF_CLOCK_PERIOD_NS / 10


# Handle clocking as well as input/output mapping for test
async def test_clock(dut, *, col_in, col_ctrl_in, row_in, row_ctrl_in, col_out, col_ctrl_out, row_out, row_ctrl_out):
    # Validate arguments
    assert is_hexs(col_in), f"col_in={repr(col_in)}"
    assert is_bits(col_ctrl_in), f"col_ctrl_in={repr(col_ctrl_in)}"
    assert is_hexs(row_in), f"row_in={repr(row_in)}"
    assert is_bits(row_ctrl_in), f"row_ctrl_in={repr(row_ctrl_in)}"
    assert is_hexs(col_out), f"col_out={repr(col_out)}"
    assert is_bits(col_ctrl_out), f"col_ctrl_out={repr(col_ctrl_out)}"
    assert is_hexs(row_out), f"row_out={repr(row_out)}"
    assert is_bits(row_ctrl_out), f"row_ctrl_out={repr(row_ctrl_out)}"
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
    assert is_hexs(col_in, 4), f"col_in={repr(col_in)}"
    assert is_bits(col_ctrl_in, 4), f"col_ctrl_in={repr(col_ctrl_in)}"
    assert is_hexs(row_in, 4), f"row_in={repr(row_in)}"
    assert is_bits(row_ctrl_in, 4), f"row_ctrl_in={repr(row_ctrl_in)}"
    assert is_hexs(col_out, 4), f"col_out={repr(col_out)}"
    assert is_bits(col_ctrl_out, 4), f"col_ctrl_out={repr(col_ctrl_out)}"
    assert is_hexs(row_out, 4), f"row_out={repr(row_out)}"
    assert is_bits(row_ctrl_out, 4), f"row_ctrl_out={repr(row_ctrl_out)}"
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
async def test_AB(dut):
    dut._log.info("start test_AB")
    await cocotb.start_soon(reset(dut))

    await test_block(dut,
        col_out="0000", row_out="0000", col_ctrl_out="0000", row_ctrl_out="0000",
        col_in="1234",  row_in="5678",  col_ctrl_in="0100",  row_ctrl_in="0100",
    )
    await test_block(dut,
        col_out="1234", row_out="5678", col_ctrl_out="0100", row_ctrl_out="0100",
        col_in="abef",  row_in="face",  col_ctrl_in="0100",  row_ctrl_in="0100",
    )
    await test_block(dut,
        col_out="abef", row_out="face", col_ctrl_out="0100", row_ctrl_out="0100",
        col_in="0000",  row_in="0000",  col_ctrl_in="0000",  row_ctrl_in="0000",
    )
    await test_block(dut,
        col_out="0000", row_out="0000", col_ctrl_out="0000", row_ctrl_out="0000",
        col_in="0000",  row_in="0000",  col_ctrl_in="0000",  row_ctrl_in="0000",
    )


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


def e5mul(A, B):
    assert is_hexs(A, 4), f"A={repr(A)}"
    assert is_hexs(B, 4), f"B={repr(B)}"
    Ab = f"{int(A, 16):016b}"
    Bb = f"{int(B, 16):016b}"
    assert is_bits(Ab, 16), f"Ab={repr(Ab)}"
    assert is_bits(Bb, 16), f"Bb={repr(Bb)}"
    A0, A1 = Ab[0:8], Ab[8:16]
    B0, B1 = Bb[0:8], Bb[8:16]
    assert is_bits(A0, 8), f"A0={repr(A0)}"
    assert is_bits(A1, 8), f"A1={repr(A1)}"
    assert is_bits(B0, 8), f"B0={repr(B0)}"
    assert is_bits(B1, 8), f"B1={repr(B1)}"
    C0 = ftofp16(e5tof(A0) * e5tof(B0))
    C1 = ftofp16(e5tof(A1) * e5tof(B0))
    C2 = ftofp16(e5tof(A0) * e5tof(B1))
    C3 = ftofp16(e5tof(A1) * e5tof(B1))
    assert is_bits(C0, 16), f"C0={repr(C0)}"
    assert is_bits(C1, 16), f"C1={repr(C1)}"
    assert is_bits(C2, 16), f"C2={repr(C2)}"
    assert is_bits(C3, 16), f"C3={repr(C3)}"
    Cb = C0 + C1 + C2 + C3
    assert is_bits(Cb, 64), f"Cb={repr(Cb)}"
    C = f"{int(Cb, 2):016x}"
    assert is_hexs(C, 16), f"C={repr(C)}"
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

            await test_block(dut,
                col_out="0000", row_out="0000", col_ctrl_out="0000", row_ctrl_out="0000",
                col_in=A,       row_in=B,       col_ctrl_in="0100",  row_ctrl_in="0100",
            )
            await test_block(dut,
                col_out=A,      row_out=B,      col_ctrl_out="0100", row_ctrl_out="0100",
                col_in="0000",  row_in="0000",  col_ctrl_in="1000",  row_ctrl_in="1000",
            )
            await test_block(dut,
                col_out=C0,     row_out=C1,     col_ctrl_out="1000", row_ctrl_out="1000",
                col_in="0000",  row_in="0000",  col_ctrl_in="1100",  row_ctrl_in="1100",
            )
            await test_block(dut,
                col_out=C2,     row_out=C3,     col_ctrl_out="1100", row_ctrl_out="1100",
                col_in="0000",  row_in="0000",  col_ctrl_in="0000",  row_ctrl_in="0000",
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

    await test_block(dut,
        col_out="0000", row_out="0000", col_ctrl_out="0000", row_ctrl_out="0000",
        col_in=A,  row_in=B,  col_ctrl_in="0100",  row_ctrl_in="0100",
    )
    await test_block(dut,
        col_out=A, row_out=B, col_ctrl_out="0100", row_ctrl_out="0100",
        col_in="c0c0",  row_in="c1c1",  col_ctrl_in="1000",  row_ctrl_in="1000",
    )
    await test_block(dut,
        col_out=C0, row_out=C1, col_ctrl_out="1000", row_ctrl_out="1000",
        col_in="c2c2",  row_in="c3c3",  col_ctrl_in="1100",  row_ctrl_in="1100",
    )
    await test_block(dut,
        col_out=C2, row_out=C3, col_ctrl_out="1100", row_ctrl_out="1100",
        col_in="0000",  row_in="0000",  col_ctrl_in="1000",  row_ctrl_in="1000",
    )
    await test_block(dut,
        col_out="c0c0", row_out="c1c1", col_ctrl_out="1000", row_ctrl_out="1000",
        col_in="0000",  row_in="0000",  col_ctrl_in="1100",  row_ctrl_in="1100",
    )
    await test_block(dut,
        col_out="c2c2", row_out="c3c3", col_ctrl_out="1100", row_ctrl_out="1100",
        col_in="0000",  row_in="0000",  col_ctrl_in="0000",  row_ctrl_in="0000",
    )


@cocotb.test()
async def test_spaced_XOR(dut):
    dut._log.info("start test_spaced_XOR")
    await cocotb.start_soon(reset(dut))

    await test_block(dut,
        col_out="0000", row_out="0000", col_ctrl_out="0000", row_ctrl_out="0000",
        col_in="1234",  row_in="5678",  col_ctrl_in="0100",  row_ctrl_in="0100",
    )
    await test_block(dut,
        col_out="1234", row_out="5678", col_ctrl_out="0100", row_ctrl_out="0100",
        col_in="0000",  row_in="0000",  col_ctrl_in="0000",  row_ctrl_in="0000",
    )
    await test_block(dut,
        col_out="0000", row_out="0000", col_ctrl_out="0000", row_ctrl_out="0000",
        col_in="0000",  row_in="0000",  col_ctrl_in="0000",  row_ctrl_in="0000",
    )
    await test_block(dut,
        col_out="0000", row_out="0000", col_ctrl_out="0000", row_ctrl_out="0000",
        col_in="c0c0",  row_in="c1c1",  col_ctrl_in="1000",  row_ctrl_in="1000",
    )
    await test_block(dut,
        col_out="1256", row_out="3456", col_ctrl_out="1000", row_ctrl_out="1000",
        col_in="c2c2",  row_in="c3c3",  col_ctrl_in="1100",  row_ctrl_in="1100",
    )
    await test_block(dut,
        col_out="1278", row_out="3478", col_ctrl_out="1100", row_ctrl_out="1100",
        col_in="0000",  row_in="0000",  col_ctrl_in="1000",  row_ctrl_in="1000",
    )
    await test_block(dut,
        col_out="c0c0", row_out="c1c1", col_ctrl_out="1000", row_ctrl_out="1000",
        col_in="0000",  row_in="0000",  col_ctrl_in="1100",  row_ctrl_in="1100",
    )
    await test_block(dut,
        col_out="c2c2", row_out="c3c3", col_ctrl_out="1100", row_ctrl_out="1100",
        col_in="0000",  row_in="0000",  col_ctrl_in="0000",  row_ctrl_in="0000",
    )
