// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
#include <gtest/gtest.h>
#include <VDE0CVSoC.h>

#include "VerilogTestbench.h"
#include "fixtures/SDRAMModel.h"

namespace
{
const uint32_t fb_dram_offset = 0x03f00000;
const uint32_t results = fb_dram_offset + 0x100;
const uint32_t trap_info = fb_dram_offset + 0x80;
const unsigned trapped = 0x2aa;

uint8_t seg7(unsigned v)
{
    static const uint8_t segs[16] = {0x3f, 0x06, 0x5b, 0x4f, 0x66, 0x6d,
                                     0x7d, 0x07, 0x7f, 0x6f, 0x77, 0x7c,
                                     0x39, 0x5e, 0x79, 0x71};
    return segs[v & 0xf];
}
} // namespace

// The whole DE0-CV system with an SDRAM model, running soctest.S from the
// boot ROM.
class DE0CVSoCTestbench : public VerilogTestbench<VDE0CVSoC>,
                          public ::testing::Test
{
public:
    DE0CVSoCTestbench() : sdram(dut)
    {
        dut.clint_refclk = 0;
        dut.vga_clk = 0;
        dut.vga_reset = 1;
        dut.sd_cmd_i = 1;
        dut.sd_dat_i = 0xf;
        dut.kbd_clk_i = 1;
        dut.kbd_dat_i = 1;
        dut.mouse_clk_i = 1;
        dut.mouse_dat_i = 1;

        periodic(ClockSetup, [&] { sdram.setup(); });
        periodic(ClockCapture, [&] {
            sdram.capture();
            // ~10MHz mtime reference and a 30MHz pixel clock
            if (++refclk_div == 3) {
                refclk_div = 0;
                dut.clint_refclk = !dut.clint_refclk;
            }
            dut.vga_clk = !dut.vga_clk;
            dut.eval();
        });

        reset();
        dut.vga_reset = 0;
    }

    ~DE0CVSoCTestbench()
    {
        for (auto &e : sdram.errors)
            ADD_FAILURE() << e;
    }

    sdram::SDRAMModel<VDE0CVSoC> sdram;
    int refclk_div = 0;
};

TEST_F(DE0CVSoCTestbench, AddressMap)
{
    int n = 0;
    while (dut.leds != 0x3ff && dut.leds != trapped && n++ < 200000)
        cycle();
    ASSERT_NE(dut.leds, trapped)
        << std::hex << "trap: mcause " << sdram.peek32(trap_info)
        << " mepc " << sdram.peek32(trap_info + 4) << " mtval "
        << sdram.peek32(trap_info + 8);
    ASSERT_EQ(dut.leds, 0x3ffu) << "soctest stopped at step " << dut.leds;

    // .data in the boot ROM
    EXPECT_EQ(sdram.peek32(results + 0x00), 0x42u);
    // Cached DRAM, cleaned out to the SDRAM and refetched
    EXPECT_EQ(sdram.peek32(0x1000), 0x12345678u);
    EXPECT_EQ(sdram.peek32(0x103c), 0x9abcdef0u);
    EXPECT_EQ(sdram.peek32(results + 0x04), 0x12345678u);
    EXPECT_EQ(sdram.peek32(results + 0x08), 0x9abcdef0u);
    // Uncached framebuffer window with a byte store
    EXPECT_EQ(sdram.peek32(fb_dram_offset), 0xcafe5a0du);
    EXPECT_EQ(sdram.peek32(results + 0x0c), 0xcafe5a0du);
    // PLIC priority
    EXPECT_EQ(sdram.peek32(results + 0x10), 3u);
    // mtime is counting
    EXPECT_GT(sdram.peek32(results + 0x18), 0u);
    EXPECT_GE(sdram.peek32(results + 0x18), sdram.peek32(results + 0x14));
    // PS/2 receive interrupt enabled, nothing received
    EXPECT_EQ(sdram.peek32(results + 0x1c), 1u);
    // SDHCI specification version 2.00
    EXPECT_EQ((sdram.peek32(results + 0x20) >> 16) & 0xff, 1u);
    EXPECT_NE(sdram.peek32(results + 0x24), 0u);

    // Seven segment displays, active low
    uint32_t value = 0x123abc;
    for (int d = 0; d < 6; ++d)
        EXPECT_EQ((dut.hex_n >> (d * 7)) & 0x7f,
                  (~seg7(value >> (d * 4))) & 0x7fu)
            << "digit " << d;
}
