// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
#include <deque>
#include <vector>

#include <gtest/gtest.h>
#include <VAltPS2.h>

#include "VerilogTestbench.h"

namespace
{

// The DUT runs at 60MHz, the PS/2 clock is ~12.5kHz: 2400 cycles low, 2400
// high.  The model is scaled down to keep the tests quick, the host only
// uses edges so the ratio doesn't matter beyond the synchronisers.
const int half_period = 40;

// PS/2 device: the open drain lines are low if either side pulls them low.
class PS2Device
{
public:
    explicit PS2Device(VAltPS2 &dut) : dut(dut)
    {
    }

    void send(uint8_t byte, bool bad_parity = false)
    {
        std::vector<int> bits;
        bits.push_back(0);
        int ones = 0;
        for (int i = 0; i < 8; ++i) {
            bits.push_back((byte >> i) & 1);
            ones += (byte >> i) & 1;
        }
        bits.push_back(((ones & 1) == 0) ^ bad_parity);
        bits.push_back(1);
        for (auto b : bits)
            tx_bits.push_back(b);
    }

    // Called every DUT cycle.
    void tick()
    {
        bool host_clk_low = dut.ps2_clk_low;

        if (state == State::Idle) {
            if (host_clk_low) {
                state = State::HostInhibit;
            } else if (!tx_bits.empty()) {
                state = State::Sending;
                phase = 0;
            }
        }

        switch (state) {
        case State::Idle:
            clk = 1;
            dat = 1;
            break;
        case State::Sending:
            // Data changes while the clock is high, the host samples on the
            // falling edge.
            if (phase == 0)
                dat = tx_bits.front();
            clk = phase < half_period ? 1 : 0;
            if (++phase == 2 * half_period) {
                tx_bits.pop_front();
                phase = 0;
                if (tx_bits.empty()) {
                    clk = 1;
                    dat = 1;
                    state = State::Idle;
                }
            }
            break;
        case State::HostInhibit:
            clk = 1;
            dat = 1;
            if (!host_clk_low) {
                // Host request to send: it should be driving data low.
                EXPECT_TRUE(dut.ps2_dat_low);
                state = State::Receiving;
                phase = 0;
                pulse = 0;
                rx_byte = 0;
            }
            break;
        case State::Receiving:
            // Generate 11 clocks, sampling on the rising edge: 8 data bits,
            // parity and stop, then acknowledge during the 11th.
            clk = phase < half_period ? 0 : 1;
            dat = pulse == 10 && phase < half_period ? 0 : 1;
            if (phase == half_period) {
                int v = !dut.ps2_dat_low;
                if (pulse < 8) {
                    rx_byte |= v << pulse;
                } else if (pulse == 8) {
                    rx_parity = v;
                } else if (pulse == 9) {
                    EXPECT_EQ(v, 1) << "stop bit";
                }
            }
            if (++phase == 2 * half_period) {
                phase = 0;
                if (++pulse == 11) {
                    int ones = __builtin_popcount(rx_byte) + rx_parity;
                    EXPECT_EQ(ones & 1, 1) << "parity";
                    received.push_back(rx_byte);
                    state = State::Idle;
                }
            }
            break;
        }

        dut.ps2_clk_i = clk && !dut.ps2_clk_low;
        dut.ps2_dat_i = dat && !dut.ps2_dat_low;
    }

    bool idle() const
    {
        return state == State::Idle && tx_bits.empty();
    }

    std::vector<uint8_t> received;

private:
    enum class State { Idle, Sending, HostInhibit, Receiving };

    VAltPS2 &dut;
    State state = State::Idle;
    std::deque<int> tx_bits;
    int phase = 0;
    int clk = 1;
    int dat = 1;
    int pulse = 0;
    int rx_byte = 0;
    int rx_parity = 0;
};

} // namespace

class AltPS2Testbench : public VerilogTestbench<VAltPS2>,
                        public ::testing::Test
{
public:
    AltPS2Testbench() : device(dut)
    {
        dut.reg_wr = 0;
        dut.reg_rd = 0;
        dut.ps2_clk_i = 1;
        dut.ps2_dat_i = 1;
        reset();
        periodic(ClockCapture, [&] {
            device.tick();
            dut.eval();
        });
    }

    void write(uint32_t addr, uint32_t v)
    {
        dut.reg_waddr = addr;
        dut.reg_wdata = v;
        dut.reg_wstrb = 0xf;
        dut.reg_wr = 1;
        cycle();
        dut.reg_wr = 0;
    }

    uint32_t read(uint32_t addr)
    {
        dut.reg_raddr = addr;
        dut.reg_rd = 1;
        dut.eval();
        uint32_t v = dut.reg_rdata;
        cycle();
        dut.reg_rd = 0;
        return v;
    }

    void wait_device_idle()
    {
        int n = 0;
        while (!device.idle() && n++ < 100000)
            cycle();
        ASSERT_LT(n, 100000);
        cycle(4 * half_period);
    }

    // The driver's interrupt handler.
    std::vector<uint8_t> drain()
    {
        std::vector<uint8_t> bytes;
        uint32_t status;
        while ((status = read(0)) & 0xffff0000) {
            EXPECT_TRUE(status & 0x8000);
            bytes.push_back(status & 0xff);
        }
        return bytes;
    }

    PS2Device device;
};

TEST_F(AltPS2Testbench, ReceiveBytes)
{
    device.send(0xaa);
    device.send(0x1c);
    device.send(0xf0);
    wait_device_idle();

    auto status = read(0);
    // RAVAIL counts this byte
    EXPECT_EQ(status >> 16, 3u);
    EXPECT_EQ(status & 0xff, 0xaau);
    EXPECT_EQ(drain(), (std::vector<uint8_t>{0x1c, 0xf0}));
    EXPECT_EQ(read(0), 0u);
}

TEST_F(AltPS2Testbench, ParityErrorDropped)
{
    device.send(0x12);
    device.send(0x34, true);
    device.send(0x56);
    wait_device_idle();

    EXPECT_EQ(drain(), (std::vector<uint8_t>{0x12, 0x56}));
}

TEST_F(AltPS2Testbench, ReceiveInterrupt)
{
    device.send(0x55);
    wait_device_idle();
    EXPECT_FALSE(dut.irq);
    EXPECT_EQ(read(4) & 0x100, 0u);

    write(4, 1);
    EXPECT_TRUE(dut.irq);
    EXPECT_EQ(read(4), 0x101u);

    drain();
    EXPECT_FALSE(dut.irq);
    EXPECT_EQ(read(4), 0x1u);
}

TEST_F(AltPS2Testbench, Transmit)
{
    write(0, 0xff);
    // A second byte written while the first is sent is held.
    cycle(10);
    write(0, 0xed);
    int n = 0;
    while (device.received.size() < 2 && n++ < 200000)
        cycle();
    EXPECT_EQ(device.received, (std::vector<uint8_t>{0xff, 0xed}));
}
