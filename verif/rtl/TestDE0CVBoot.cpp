// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
#include <fstream>
#include <iterator>

#include <gtest/gtest.h>
#include <VDE0CVBoot.h>

#include "VerilogTestbench.h"
#include "fixtures/FatImage.h"
#include "fixtures/SDCardModel.h"
#include "fixtures/SDRAMModel.h"

namespace
{
const uint32_t fb_dram_offset = 0x03f00000;
const uint32_t dtb_offset = 0x00200000;
const unsigned pass = 0x155;
const unsigned fail = 0x0aa;

std::vector<uint8_t> read_file(const std::string &path)
{
    std::ifstream f(path, std::ios::binary);
    EXPECT_TRUE(f.good()) << path;
    return std::vector<uint8_t>(std::istreambuf_iterator<char>(f), {});
}
} // namespace

// The DE0-CV system running its boot ROM: the SD card is initialised and the
// payload and DTB loaded from a FAT16 partition into the SDRAM, then the
// payload checks the arguments it was entered with.
class DE0CVBootTestbench : public VerilogTestbench<VDE0CVBoot>,
                           public ::testing::Test
{
public:
    DE0CVBootTestbench() : sdram(dut), card(16384)
    {
        dut.clint_refclk = 0;
        dut.vga_clk = 0;
        dut.vga_reset = 1;
        dut.kbd_clk_i = 1;
        dut.kbd_dat_i = 1;
        dut.mouse_clk_i = 1;
        dut.mouse_dat_i = 1;

        periodic(ClockSetup, [&] { sdram.setup(); });
        periodic(ClockCapture, [&] {
            sdram.capture();
            card.step(dut.sd_clk, dut.sd_cmd_o, dut.sd_cmd_t, dut.sd_dat_o,
                      dut.sd_dat_t);
            dut.sd_cmd_i = card.cmd_line();
            dut.sd_dat_i = card.dat_lines();
            if (++refclk_div == 3) {
                refclk_div = 0;
                dut.clint_refclk = !dut.clint_refclk;
            }
            dut.vga_clk = !dut.vga_clk;
            dut.eval();
        });
    }

    ~DE0CVBootTestbench()
    {
        for (auto &e : sdram.errors)
            ADD_FAILURE() << e;
    }

    void boot()
    {
        reset();
        dut.vga_reset = 0;
        uint64_t n = 0;
        while (dut.leds != pass && dut.leds != fail && n++ < 40000000)
            cycle();
    }

    sdram::SDRAMModel<VDE0CVBoot> sdram;
    SDCardModel card;
    int refclk_div = 0;
};

TEST_F(DE0CVBootTestbench, BootsPayload)
{
    std::vector<uint8_t> dtb(3000);
    for (size_t i = 0; i < dtb.size(); ++i)
        dtb[i] = i * 7 + 3;

    FatImage image;
    image.add_file("OPENSBI.BIN", read_file(DE0CV_PAYLOAD));
    image.add_file("DE0CV.DTB", dtb);
    auto disk = image.build();
    std::copy(disk.begin(), disk.end(), card.disk.begin());

    boot();
    ASSERT_EQ(dut.leds, pass) << "LEDs " << std::hex << dut.leds;

    for (size_t i = 0; i < dtb.size(); i += 4) {
        uint32_t expected = 0;
        for (size_t b = 0; b < 4 && i + b < dtb.size(); ++b)
            expected |= uint32_t(dtb[i + b]) << (8 * b);
        uint32_t mask = i + 4 <= dtb.size() ? 0xffffffff
                                             : (1u << (8 * (dtb.size() - i))) - 1;
        ASSERT_EQ(sdram.peek32(dtb_offset + i) & mask, expected)
            << "DTB offset " << i;
    }

    // The banner was drawn on the framebuffer: some foreground pixels in the
    // first rows of text.
    unsigned lit = 0;
    for (uint32_t off = 0; off < 640 * 2 * 16 * 8; off += 4)
        lit += sdram.peek32(fb_dram_offset + off) != 0;
    EXPECT_GT(lit, 100u);

    EXPECT_FALSE(card.contention);
    EXPECT_EQ(card.bad_commands, 0u);

    // Optionally save the screen as a PPM to look at.
    if (auto path = getenv("DE0CV_FB_DUMP")) {
        std::ofstream ppm(path, std::ios::binary);
        ppm << "P6\n640 480\n255\n";
        for (uint32_t i = 0; i < 640 * 480; ++i) {
            uint32_t w = sdram.peek32(fb_dram_offset + (i / 2) * 4);
            uint16_t p = i & 1 ? w >> 16 : w & 0xffff;
            ppm.put(((p >> 11) & 0x1f) << 3);
            ppm.put(((p >> 5) & 0x3f) << 2);
            ppm.put((p & 0x1f) << 3);
        }
    }
}
