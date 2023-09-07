#!/usr/bin/env python
# %%
import random
from itertools import product

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge, Timer

from fp import E4M3, E5M2, FP16, fma, is_bin, is_hex

TEST_N = 10000  # TODO: turn this down to 10 for submission
# random.seed(0)  # TODO: deterministic seed for submission


async def reset(dut):
    # Set all the inputs to zero
    dut.PipeA.value = 0
    dut.PipeB.value = 0
    dut.PipeC.value = 0
    dut.PipeAe.value = 0
    dut.PipeBe.value = 0
    dut.PipeSave.value = 0
    await Timer(1, units="ns")


# Test that we get zeroes post-reset
@cocotb.test()
async def test_zero(dut):
    await cocotb.start_soon(reset(dut))
    dut._log.info("start test_zero")
    # Check that the outputs are zero
    assert dut.Pipe0w.value.binstr == "0" * 35
    assert dut.Pipe0Sw.value.binstr == "0"
    assert dut.Pipe1w.value.binstr == "0" * 32
    assert dut.Pipe1Sw.value.binstr == "0"
    assert dut.Pipe2w.value.binstr == "0" * 40
    assert dut.Pipe2Sw.value.binstr == "0"
    assert dut.Pipe3w.value.binstr == "0" * 16
    assert dut.Pipe3Sw.value.binstr == "0"
    # Same but with saving
    # NOTE: intermediate wires might be nonzero
    dut.PipeSave.value = 1
    await Timer(1, units="ns")
    assert dut.Pipe0Sw.value.binstr == "1"
    assert dut.Pipe1Sw.value.binstr == "1"
    assert dut.Pipe2Sw.value.binstr == "1"
    assert dut.Pipe3w.value.binstr == "0" * 16
    assert dut.Pipe3Sw.value.binstr == "1"


# Pass through C and return the result
async def check_pass(dut, Ci):
    await reset(dut)
    dut.PipeC.value = int(Ci, 2)
    dut.PipeSave.value = 1
    await Timer(1, units="ns")
    assert dut.Pipe3Sw.value.binstr == "1"
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
async def check_ab(dut, Ai, Bi):
    # TODO: make this a standalone function
    await reset(dut)
    A = E5M2.fromb(Ai, norm=True)
    B = E5M2.fromb(Bi, norm=True)
    dut.PipeA.value = int(Ai, 2)
    dut.PipeB.value = int(Bi, 2)
    dut.PipeSave.value = 1
    await Timer(1, units="ns")
    assert dut.Pipe3Sw.value.binstr == "1"
    Co = FP16.fromb(dut.Pipe3w.value.binstr, norm=True)
    Ci = FP16.fromf(FP16.fromf(A.f * B.f).f + 0.0)
    assert Co == Ci, f"({A.f}, {B.f}) {Co} != {Ci} ({A} * {B})"


# Test multiplying A * B
@cocotb.test()
async def test_ab(dut):
    await cocotb.start_soon(reset(dut))
    dut._log.info("start test_ab")
    # TODO: check other FP8 modes
    # Special values
    vals = [0., E5M2.MIN, 1., E5M2.MAX, 'inf', 'nan']
    values = sum([[float(v), -float(v)] for v in vals], [])
    for a in values:
        for b in values:
            await check_ab(dut, E5M2.fromf(a).b, E5M2.fromf(b).b)
    # Random value tests
    for _ in range(TEST_N):
        A = E5M2.rand()
        B = E5M2.rand()
        await check_ab(dut, A.b, B.b)
    # Random real tests
    for _ in range(TEST_N):
        A = E5M2.real()
        B = E5M2.real()
        await check_ab(dut, A.b, B.b)
    # Random sub tests
    for _ in range(TEST_N):
        A = E5M2.real()
        B = E5M2.rsub()
        await check_ab(dut, A.b, B.b)
    # Random sub tests
    for _ in range(TEST_N):
        A = E5M2.rsub()
        B = E5M2.real()
        await check_ab(dut, A.b, B.b)
    # Random sub tests
    for _ in range(TEST_N):
        A = E5M2.rsub()
        B = E5M2.rsub()
        await check_ab(dut, A.b, B.b)