# cocotb tests for tt_um_matmul2x2_int8
import random
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, Timer


async def reset(dut):
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 4)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)


async def write_byte(dut, d):
    await FallingEdge(dut.clk)
    dut.ui_in.value = d & 0xFF
    dut.uio_in.value = 0x01          # WR high
    await FallingEdge(dut.clk)
    dut.uio_in.value = 0x00


async def start_and_wait(dut):
    await FallingEdge(dut.clk)
    dut.uio_in.value = 0x02          # START
    await FallingEdge(dut.clk)
    dut.uio_in.value = 0x00
    for _ in range(40):
        if (int(dut.uio_out.value) >> 5) & 1:
            return
        await FallingEdge(dut.clk)
    assert False, "DONE never asserted"


async def read_elem(dut, sel):
    dut.uio_in.value = (sel << 2)            # HI = 0
    await Timer(1, "ns")
    lo = int(dut.uo_out.value)
    b16 = (int(dut.uio_out.value) >> 7) & 1
    dut.uio_in.value = (sel << 2) | 0x10     # HI = 1
    await Timer(1, "ns")
    hi = int(dut.uo_out.value)
    raw = (b16 << 16) | (hi << 8) | lo
    return raw - (1 << 17) if raw >= (1 << 16) else raw


async def run_case(dut, A, B):
    """A, B: flat row-major lists of 4 signed ints."""
    for v in A + B:
        await write_byte(dut, v)
    await start_and_wait(dut)
    for i in range(2):
        for j in range(2):
            exp = A[i * 2] * B[j] + A[i * 2 + 1] * B[2 + j]
            got = await read_elem(dut, i * 2 + j)
            assert got == exp, f"C{i}{j}: got {got}, expected {exp} (A={A}, B={B})"


@cocotb.test()
async def test_corners(dut):
    cocotb.start_soon(Clock(dut.clk, 20, "ns").start())
    await reset(dut)
    await run_case(dut, [-128] * 4, [-128] * 4)      # +32768, needs 17 bits
    await run_case(dut, [127] * 4, [127] * 4)
    await run_case(dut, [-128] * 4, [127] * 4)
    await run_case(dut, [0] * 4, [55] * 4)
    await run_case(dut, [1, 0, 0, 1], [-5, 7, 100, -100])  # identity


@cocotb.test()
async def test_random(dut):
    cocotb.start_soon(Clock(dut.clk, 20, "ns").start())
    await reset(dut)
    rng = random.Random(1234)
    for _ in range(100):
        A = [rng.randint(-128, 127) for _ in range(4)]
        B = [rng.randint(-128, 127) for _ in range(4)]
        await run_case(dut, A, B)
