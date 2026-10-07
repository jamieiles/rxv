// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
#include <algorithm>
#include <deque>
#include <random>
#include <vector>

#include <gtest/gtest.h>
#include <VVGAScanoutWrapper.h>

#include "VerilogTestbench.h"

namespace
{

const uint32_t fb_base = 0x83f00000;
const int width = 640;
const int height = 480;
const int h_back = 48;
const int v_back = 33;

uint16_t pixel(int x, int y)
{
    return static_cast<uint16_t>((x * 7 + y * 131) ^ (y << 9) ^ (x << 4));
}

uint32_t word_at(uint32_t addr)
{
    uint32_t off = addr - fb_base;
    int y = off / (width * 2);
    int x = (off % (width * 2)) / 2;
    return pixel(x, y) | (uint32_t(pixel(x + 1, y)) << 16);
}

// The video port of SDRAMFrontend: a line read is accepted when the
// frontend is free and returns 16 words after a latency.
class VideoMemory
{
public:
    explicit VideoMemory(VVGAScanoutWrapper &dut) : dut(dut), rng(7)
    {
    }

    void set_latency(int min, int max)
    {
        min_latency = min;
        max_latency = max;
    }

    void setup(uint64_t cycle)
    {
        if (dut.v_arvalid && dut.v_arready) {
            EXPECT_EQ(dut.v_rlen, 15);
            EXPECT_EQ(dut.v_raddr & 63, 0u);
            EXPECT_GE(dut.v_raddr, fb_base);
            EXPECT_LT(dut.v_raddr, fb_base + width * height * 2);
            std::uniform_int_distribution<int> lat(min_latency, max_latency);
            pending.push_back({cycle + lat(rng), dut.v_raddr});
            ++bursts;
        }
        if (dut.v_rvalid && dut.v_rready)
            ++beat;
    }

    void capture(uint64_t cycle)
    {
        if (beat == 16) {
            pending.pop_front();
            beat = 0;
        }
        dut.v_arready = pending.empty();
        dut.v_rvalid = 0;
        dut.v_rlast = 0;
        if (!pending.empty() && pending.front().first <= cycle) {
            dut.v_rvalid = 1;
            dut.v_rdata = word_at(pending.front().second + beat * 4);
            dut.v_rlast = beat == 15;
        }
    }

    unsigned bursts = 0;

private:
    VVGAScanoutWrapper &dut;
    std::mt19937 rng;
    int min_latency = 10;
    int max_latency = 40;
    std::deque<std::pair<uint64_t, uint32_t>> pending;
    int beat = 0;
};

// Samples the DAC on each pixel clock and reassembles a frame from the
// sync pulses.
class Monitor
{
public:
    explicit Monitor(VVGAScanoutWrapper &dut) : dut(dut)
    {
    }

    void sample()
    {
        bool vga_clk = dut.vga_clk;
        bool rising = vga_clk && !last_clk;
        last_clk = vga_clk;
        if (!rising)
            return;

        bool hs = dut.vga_hsync, vs = dut.vga_vsync;
        if (vs && !last_vs) {
            // Start of the vertical back porch.
            if (frames > 0)
                last_frame = frame;
            ++frames;
            hsyncs = 0;
            frame.assign(height, std::vector<uint16_t>(width, 0));
        }
        if (hs && !last_hs) {
            ++hsyncs;
            pixel_x = -h_back;
        }
        last_vs = vs;
        last_hs = hs;

        // The first hsync after vsync is in the first back porch line.
        int y = hsyncs - v_back;
        if (frames > 0 && y >= 0 && y < height && pixel_x >= 0 &&
            pixel_x < width) {
            frame[y][pixel_x] =
                (dut.vga_r << 8) | (dut.vga_g << 4) | dut.vga_b;
        } else if (pixel_x >= width || pixel_x < 0) {
            if (dut.vga_r || dut.vga_g || dut.vga_b)
                ++blank_errors;
        }
        ++pixel_x;
    }

    int frames = 0;
    int blank_errors = 0;
    std::vector<std::vector<uint16_t>> frame;
    std::vector<std::vector<uint16_t>> last_frame;

private:
    VVGAScanoutWrapper &dut;
    bool last_clk = false;
    bool last_vs = true;
    bool last_hs = true;
    int hsyncs = 0;
    int pixel_x = 0;
};

uint16_t expected_dac(uint16_t p)
{
    int r = (p >> 12) & 0xf, g = (p >> 7) & 0xf, b = (p >> 1) & 0xf;
    return (r << 8) | (g << 4) | b;
}

} // namespace

class VGAScanoutTestbench : public VerilogTestbench<VVGAScanoutWrapper>,
                            public ::testing::Test
{
public:
    VGAScanoutTestbench() : mem(dut), mon(dut)
    {
        dut.v_arready = 1;
        dut.v_rvalid = 0;
        reset();
        periodic(ClockSetup, [&] { mem.setup(cur_cycle()); });
        periodic(ClockCapture, [&] {
            mem.capture(cur_cycle());
            dut.eval();
            mon.sample();
        });
    }

    // Run until a whole frame has been captured into last_frame.  The
    // syncs come out of reset high, which looks like the end of a vsync,
    // so the first frame is partial.
    void run_frame()
    {
        int start = std::max(mon.frames, 1);
        while (mon.frames < start + 2)
            cycle();
    }

    void check_frame(const std::vector<std::vector<uint16_t>> &frame)
    {
        int errors = 0;
        for (int y = 0; y < height; ++y)
            for (int x = 0; x < width; ++x)
                if (frame[y][x] != expected_dac(pixel(x, y)) &&
                    errors++ < 10)
                    ADD_FAILURE() << "pixel (" << x << ", " << y << ") "
                                  << std::hex << frame[y][x] << " expected "
                                  << expected_dac(pixel(x, y));
        EXPECT_EQ(errors, 0);
        EXPECT_EQ(mon.blank_errors, 0);
    }

    VideoMemory mem;
    Monitor mon;
};

TEST_F(VGAScanoutTestbench, FrameMatchesFramebuffer)
{
    run_frame();
    check_frame(mon.last_frame);
}

TEST_F(VGAScanoutTestbench, ToleratesContention)
{
    mem.set_latency(20, 70);
    run_frame();
    check_frame(mon.last_frame);
}

// With video priority a burst waits for at most the SDRAM request being
// executed and then its own: about 80 system clocks of the 2304 (a line and
// the horizontal blanking at 60MHz / 25MHz) for the 20 bursts of a line,
// leaving ~30% margin.  The pixel clock here is half the system clock, so
// the budget is 1920 clocks and the same margin is a latency of ~50 before
// the 16 beats.
TEST_F(VGAScanoutTestbench, WorstCaseLatency)
{
    mem.set_latency(50, 50);
    run_frame();
    check_frame(mon.last_frame);
}

