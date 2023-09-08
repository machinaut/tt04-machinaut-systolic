#!/usr/bin/env python
# %%
import random
from itertools import product

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge, Timer

from fp import E4M3, E5M2, FP16, fma, is_bin, is_hex

TEST_N = 1000  # TODO: turn this down to 10 for submission
# random.seed(0)  # TODO: deterministic seed for submission


async def reset(dut):
    # Set all the inputs to zero
    dut.PipeA.value = 0
    dut.PipeB.value = 0
    dut.PipeC.value = 0
    dut.PipeAfmt.value = 0
    dut.PipeBfmt.value = 0
    dut.PipeSave.value = 0
    await Timer(1, units="ns")


# Test that we get zeroes post-reset
@cocotb.test()
async def test_zero(dut):
    await cocotb.start_soon(reset(dut))
    dut._log.info("start test_zero")
    # Check that the outputs are zero
    assert dut.Pipe3w.value.binstr == "0" * 16
    assert dut.Pipe3Save.value.binstr == "0"
    # Same but with saving
    # NOTE: intermediate wires might be nonzero
    dut.PipeSave.value = 1
    await Timer(1, units="ns")
    assert dut.Pipe3w.value.binstr == "0" * 16
    assert dut.Pipe3Save.value.binstr == "1"


# Pass through C and return the result
async def check_pass(dut, Ci):
    await reset(dut)
    dut.PipeC.value = int(Ci, 2)
    dut.PipeSave.value = 1
    await Timer(1, units="ns")
    assert dut.Pipe3Save.value.binstr == "1"
    Co = dut.Pipe3w.value.binstr
    assert FP16.fromb(Ci, norm=True) == FP16.fromb(Co, norm=True), f"{Ci} != {Co}"


# Test that we pass through C
@cocotb.test()
async def test_pass(dut):
    await cocotb.start_soon(reset(dut))
    dut._log.info("start test_pass")
    # Special values
    for Ch in ['0000', '8000', '7fff', '7c00', 'fc00', '7ff0', 'fffe']:
        await check_pass(dut, f"{int(Ch, 16):016b}")
    # Random value tests
    for _ in range(TEST_N):
        Ci = f"{random.randint(0, 2**16 - 1):016b}"
        await check_pass(dut, Ci)


# Check A * B
async def check_ab(dut, A, B, C=None):
    # TODO: make this a standalone function
    await reset(dut)
    C = FP16.fromf(0.0) if C is None else C
    assert isinstance(A, (E5M2, E4M3)), f"{A} is not an FP8"
    assert isinstance(B, (E5M2, E4M3)), f"{B} is not an FP8"
    assert C is None or isinstance(C, FP16), f"{C} is not an FP16"
    dut.PipeA.value = int(A.b, 2)
    dut.PipeB.value = int(B.b, 2)
    dut.PipeC.value = int(C.b, 2)
    dut.PipeAfmt.value = 1 if isinstance(A, E4M3) else 0
    dut.PipeBfmt.value = 1 if isinstance(B, E4M3) else 0
    dut.PipeSave.value = 1
    await Timer(1, units="ns")
    assert dut.Pipe3Save.value.binstr == "1"
    Co = FP16.fromb(dut.Pipe3w.value.binstr, norm=True)
    Ci = FP16.fromf(FP16.fromf(A.f * B.f).f + C.f)
    assert Co == Ci or Co.f == Ci.f, f"({A.f}, {B.f}, {C.f}) {Co} != {Ci} ({A} * {B} + {C})"


# Test identity A * 1
@cocotb.test()
async def test_identity(dut):
    await cocotb.start_soon(reset(dut))
    dut._log.info("start test_identity")
    I = E5M2.fromf(1.0)
    for Acls in [E4M3, E5M2]:
        # Special values
        vals = [0., E5M2.MIN, E5M2.MIN * 2, E4M3.MIN, 1., E4M3.MAX, E5M2.MAX, 'inf', 'nan']
        vals = sum([[float(v), -float(v)] for v in vals], [])
        for a in vals:
            await check_ab(dut, Acls.fromf(a), I)
        # Random value tests
        for _ in range(TEST_N):
            await check_ab(dut, Acls.rand(), I)
        # Random real tests
        for _ in range(TEST_N):
            await check_ab(dut, Acls.real(), I)
        # Random sub tests
        for _ in range(TEST_N):
            await check_ab(dut, Acls.real(), I)
        # Random sub tests
        for _ in range(TEST_N):
            await check_ab(dut, Acls.rsub(), I)
        # Random sub tests
        for _ in range(TEST_N):
            await check_ab(dut, Acls.rsub(), I)


# Test multiplying A * B
@cocotb.test()
async def test_ab(dut):
    await cocotb.start_soon(reset(dut))
    dut._log.info("start test_ab")
    for Acls in [E5M2]: # [E4M3, E5M2]:  # TODO
        for Bcls in [E5M2]: # [E4M3, E5M2]:  # TODO
            # Special values
            vals = [0., E5M2.MIN, E4M3.MIN, 1., E4M3.MAX, E5M2.MAX, 'inf', 'nan']
            vals = sum([[float(v), -float(v)] for v in vals], [])
            for a in vals:
                for b in vals:
                    await check_ab(dut, Acls.fromf(a), Bcls.fromf(b))
            # Random value tests
            for _ in range(TEST_N):
                await check_ab(dut, Acls.rand(), Bcls.rand())
            # Random real tests
            for _ in range(TEST_N):
                await check_ab(dut, Acls.real(), Bcls.real())
            # Random sub tests
            for _ in range(TEST_N):
                await check_ab(dut, Acls.real(), Bcls.rsub())
            # Random sub tests
            for _ in range(TEST_N):
                await check_ab(dut, Acls.rsub(), Bcls.real())
            # Random sub tests
            for _ in range(TEST_N):
                await check_ab(dut, Acls.rsub(), Bcls.rsub())

# Test multiplying A * B + C
@cocotb.test()
async def test_ab(dut):
    await cocotb.start_soon(reset(dut))
    dut._log.info("start test_ab")
    for Acls in [E5M2]: # [E4M3, E5M2]:  # TODO
        for Bcls in [E5M2]: # [E4M3, E5M2]:  # TODO
            # Special values
            vals = [0., E5M2.MIN, E4M3.MIN, 1., E4M3.MAX, E5M2.MAX, 'inf', 'nan']
            vals = sum([[float(v), -float(v)] for v in vals], [])
            for a in vals:
                for b in vals:
                    for c in vals:
                        await check_ab(dut, Acls.fromf(a), Bcls.fromf(b), FP16.fromf(c))
            # Random value tests
            for _ in range(TEST_N):
                await check_ab(dut, Acls.rand(), Bcls.rand(), FP16.rand())
            # Random real tests
            for _ in range(TEST_N):
                await check_ab(dut, Acls.real(), Bcls.real(), FP16.real())
            # Random sub tests
            for _ in range(TEST_N):
                await check_ab(dut, Acls.real(), Bcls.rsub(), FP16.rsub())
            # Random sub tests
            for _ in range(TEST_N):
                await check_ab(dut, Acls.rsub(), Bcls.real(), FP16.rsub())
            # Random sub tests
            for _ in range(TEST_N):
                await check_ab(dut, Acls.rsub(), Bcls.rsub(), FP16.rsub())