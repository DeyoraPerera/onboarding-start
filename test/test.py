# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Edge
from cocotb.triggers import ClockCycles
from cocotb.types import Logic
from cocotb.types import LogicArray
from cocotb.utils import get_sim_time

async def await_half_sclk(dut):
    """Wait for the SCLK signal to go high or low."""
    start_time = cocotb.utils.get_sim_time(unit="ns")
    while True:
        await ClockCycles(dut.clk, 1)
        # Wait for half of the SCLK period (10 us)
        if (start_time + 100*100*0.5) < cocotb.utils.get_sim_time(unit="ns"):
            break
    return

def ui_in_logicarray(ncs, bit, sclk):
    """Setup the ui_in value as a LogicArray."""
    return LogicArray(f"00000{ncs}{bit}{sclk}")

async def send_spi_transaction(dut, r_w, address, data):
    """
    Send an SPI transaction with format:
    - 1 bit for Read/Write
    - 7 bits for address
    - 8 bits for data
    
    Parameters:
    - r_w: boolean, True for write, False for read
    - address: int, 7-bit address (0-127)
    - data: LogicArray or int, 8-bit data
    """
    # Convert data to int if it's a LogicArray
    if isinstance(data, LogicArray):
        data_int = int(data)
    else:
        data_int = data
    # Validate inputs
    if address < 0 or address > 127:
        raise ValueError("Address must be 7-bit (0-127)")
    if data_int < 0 or data_int > 255:
        raise ValueError("Data must be 8-bit (0-255)")
    # Combine RW and address into first byte
    first_byte = (int(r_w) << 7) | address
    # Start transaction - pull CS low
    sclk = 0
    ncs = 0
    bit = 0
    # Set initial state with CS low
    dut.ui_in.value = ui_in_logicarray(ncs, bit, sclk)
    await ClockCycles(dut.clk, 1)
    # Send first byte (RW + Address)
    for i in range(8):
        bit = (first_byte >> (7-i)) & 0x1
        # SCLK low, set COPI
        sclk = 0
        dut.ui_in.value = ui_in_logicarray(ncs, bit, sclk)
        await await_half_sclk(dut)
        # SCLK high, keep COPI
        sclk = 1
        dut.ui_in.value = ui_in_logicarray(ncs, bit, sclk)
        await await_half_sclk(dut)
    # Send second byte (Data)
    for i in range(8):
        bit = (data_int >> (7-i)) & 0x1
        # SCLK low, set COPI
        sclk = 0
        dut.ui_in.value = ui_in_logicarray(ncs, bit, sclk)
        await await_half_sclk(dut)
        # SCLK high, keep COPI
        sclk = 1
        dut.ui_in.value = ui_in_logicarray(ncs, bit, sclk)
        await await_half_sclk(dut)
    # End transaction - return CS high
    sclk = 0
    ncs = 1
    bit = 0
    dut.ui_in.value = ui_in_logicarray(ncs, bit, sclk)
    await ClockCycles(dut.clk, 600)
    return ui_in_logicarray(ncs, bit, sclk)

@cocotb.test()
async def test_spi(dut):
    dut._log.info("Start SPI test")

    # Set the clock period to 100 ns (10 MHz)
    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut._log.info("Reset")
    dut.ena.value = 1
    ncs = 1
    bit = 0
    sclk = 0
    dut.ui_in.value = ui_in_logicarray(ncs, bit, sclk)
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)

    dut._log.info("Test project behavior")
    dut._log.info("Write transaction, address 0x00, data 0xF0")
    ui_in_val = await send_spi_transaction(dut, 1, 0x00, 0xF0)  # Write transaction
    assert dut.uo_out.value == 0xF0, f"Expected 0xF0, got {dut.uo_out.value}"
    await ClockCycles(dut.clk, 1000) 

    dut._log.info("Write transaction, address 0x01, data 0xCC")
    ui_in_val = await send_spi_transaction(dut, 1, 0x01, 0xCC)  # Write transaction
    assert dut.uio_out.value == 0xCC, f"Expected 0xCC, got {dut.uio_out.value}"
    await ClockCycles(dut.clk, 100)

    dut._log.info("Write transaction, address 0x30 (invalid), data 0xAA")
    ui_in_val = await send_spi_transaction(dut, 1, 0x30, 0xAA)
    await ClockCycles(dut.clk, 100)

    dut._log.info("Read transaction (invalid), address 0x00, data 0xBE")
    ui_in_val = await send_spi_transaction(dut, 0, 0x30, 0xBE)
    assert dut.uo_out.value == 0xF0, f"Expected 0xF0, got {dut.uo_out.value}"
    await ClockCycles(dut.clk, 100)
    
    dut._log.info("Read transaction (invalid), address 0x41 (invalid), data 0xEF")
    ui_in_val = await send_spi_transaction(dut, 0, 0x41, 0xEF)
    await ClockCycles(dut.clk, 100)

    dut._log.info("Write transaction, address 0x02, data 0xFF")
    ui_in_val = await send_spi_transaction(dut, 1, 0x02, 0xFF)  # Write transaction
    await ClockCycles(dut.clk, 100)

    dut._log.info("Write transaction, address 0x04, data 0xCF")
    ui_in_val = await send_spi_transaction(dut, 1, 0x04, 0xCF)  # Write transaction
    await ClockCycles(dut.clk, 30000)

    dut._log.info("Write transaction, address 0x04, data 0xFF")
    ui_in_val = await send_spi_transaction(dut, 1, 0x04, 0xFF)  # Write transaction
    await ClockCycles(dut.clk, 30000)

    dut._log.info("Write transaction, address 0x04, data 0x00")
    ui_in_val = await send_spi_transaction(dut, 1, 0x04, 0x00)  # Write transaction
    await ClockCycles(dut.clk, 30000)

    dut._log.info("Write transaction, address 0x04, data 0x01")
    ui_in_val = await send_spi_transaction(dut, 1, 0x04, 0x01)  # Write transaction
    await ClockCycles(dut.clk, 30000)

    dut._log.info("SPI test completed successfully")

@cocotb.test()
async def test_pwm_freq(dut):
    """Verify PWM frequency is ~3kHz at v0%, 50%, 100% duty cycles."""
    dut._log.info("Starting PWM frequency test")
    cocotb.start_soon(Clock(dut.clk, 100, unit="ns").start()) 

    await send_spi_transaction(dut, 1, 0x00, 0x01)
    await send_spi_transaction(dut, 1, 0x02, 0x01)

    for duty in [0x00, 0x80, 0xFF]: 
        await send_spi_transaction(dut, 1, 0x04, duty)
        await ClockCycles(dut.clk, 5000)

        current_val = dut.uo_out.value[0]

        if duty == 0x00:
            assert current_val == 0, f"Expected 0, got {current_val}"
            continue

        elif duty == 0xFF:
            assert current_val == 1, f"Expected 1, got {current_val}"
            continue

        # period between two rising edges
        t1 = None
        for _ in range(10000): # safety timeout
            await Edge(dut.uo_out)
            if dut.uo_out.value[0] == 1:
                t1 = get_sim_time(unit="ns")
                break

        if t1 is None: raise AssertionError("Timeout: First rising edge not detected")
        
        await Edge(dut.uo_out) # skip falling edge
        
        t2 = None
        for _ in range(10000): #safety timoout
            await Edge(dut.uo_out)
            if dut.uo_out.value[0] == 1:
                t2 = get_sim_time(unit="ns")
                break

        if t2 is None: raise AssertionError("Timeout: Second rising edge not detected")

        period = t2 - t1
        freq = 1e9 / period
        dut._log.info(f"Duty {duty:#04x}: {freq:.2f} Hz")
        assert 2970 <= freq <= 3030, f"Frequency {freq} out of tolerance"
    dut._log.info("PWM Frequency test completed successfully")

@cocotb.test()
async def test_pwm_duty(dut):
    """Verify duty cycle pulse width accuracy."""
    dut._log.info("Starting PWM duty cycle test")
    cocotb.start_soon(Clock(dut.clk, 100, unit="ns").start())

    await send_spi_transaction(dut, 1, 0x00, 0x01) 
    await send_spi_transaction(dut, 1, 0x02, 0x01) 

    for duty in [0x00, 0x80, 0xFF]:
        if duty in [0x00, 0xFF]: continue
        
        await send_spi_transaction(dut, 1, 0x04, duty)
        await ClockCycles(dut.clk, 5000) 

        # first rising edge
        t_rise1 = None
        for _ in range(10000):
            await Edge(dut.uo_out)
            if dut.uo_out.value[0] == 1:
                t_rise1 = get_sim_time(unit="ns")
                break

        if t_rise1 is None: raise AssertionError("Timeout: Rising edge 1 not detected")
        
        # falling edge
        t_fall = None
        for _ in range(10000):
            await Edge(dut.uo_out)
            if dut.uo_out.value[0] == 0:
                t_fall = get_sim_time(unit="ns")
                break

        if t_fall is None: raise AssertionError("Timeout: Falling edge not detected")
        
        # second rising edge
        t_rise2 = None
        for _ in range(10000):
            await Edge(dut.uo_out)
            if dut.uo_out.value[0] == 1:
                t_rise2 = get_sim_time(unit="ns")
                break

        if t_rise2 is None: raise AssertionError("Timeout: Rising edge 2 not detected")

        high_time = t_fall - t_rise1
        period = t_rise2 - t_rise1
        measured_duty = (high_time / period) * 100
        expected_duty = (duty / 256) * 100
        dut._log.info(f"Duty {duty:#04x}: Measured {measured_duty:.2f}%, Expected {expected_duty:.2f}%")
        assert abs(measured_duty - expected_duty) <= 1.0, f"Duty cycle error too high"

    dut._log.info("PWM Duty Cycle test completed successfully")