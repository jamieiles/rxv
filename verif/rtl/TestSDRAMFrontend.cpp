// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
#include <array>
#include <deque>
#include <functional>
#include <map>
#include <optional>
#include <random>
#include <unordered_map>

#include <gtest/gtest.h>
#include <VSDRAMFrontendWrapper.h>

#include "VerilogTestbench.h"
#include "fixtures/SDRAMModel.h"

namespace
{

const int line_words = 16;
const uint32_t dram_base = 0x80000000;
const uint32_t fb_window = 0xf8000000;
const uint32_t fb_dram_offset = 0x03f00000;

using Line = std::array<uint32_t, line_words>;
using SDRAMModel = sdram::SDRAMModel<VSDRAMFrontendWrapper>;
using sdram::cycles;

struct Txn {
    bool write;
    uint32_t addr;
    Line data;
    uint8_t bytesel;
    int len;
};

struct Result {
    Txn txn;
    Line data;
    uint64_t start;
    uint64_t end;
};

// The DUT signals for one BusAdapter driven port.
struct PortSignals {
    CData *valid;
    IData *address;
    CData *len;
    CData *wren;
    IData *wdata;
    CData *bytesel;
    CData *complete;
    IData *rdata;
    CData *beat_ack;
    CData *beat_num;
};

#define PORT_SIGNALS(dut, p)                                                   \
    PortSignals                                                                \
    {                                                                          \
        &dut.p##_valid, &dut.p##_address, &dut.p##_len, &dut.p##_wren,         \
            &dut.p##_wdata, &dut.p##_bytesel, &dut.p##_complete,               \
            &dut.p##_rdata, &dut.p##_beat_ack, &dut.p##_beat_num               \
    }

// Drives a BusAdapter the same way the caches do: valid is held until
// complete, write data follows beat_num.
class PortDriver
{
public:
    explicit PortDriver(PortSignals sig) : sig(sig)
    {
        *sig.valid = 0;
        *sig.wren = 0;
        *sig.len = 15;
        *sig.bytesel = 0xf;
    }

    void push(const Txn &t)
    {
        queue.push_back(t);
    }

    void setup(uint64_t cycle)
    {
        if (!active)
            return;
        if (*sig.beat_ack) {
            EXPECT_LT(beat, 16);
            if (beat < 16)
                cur.data[beat++] = *sig.rdata;
        }
        if (*sig.complete) {
            cur.end = cycle;
            done = true;
        }
    }

    void capture(uint64_t cycle)
    {
        if (done) {
            EXPECT_EQ(beat, cur.txn.len + 1);
            results.push_back(cur);
            done = false;
            active = false;
            *sig.valid = 0;
        }
        if (!active && !queue.empty()) {
            cur = Result{queue.front(), {}, cycle, 0};
            queue.pop_front();
            active = true;
            beat = 0;
            *sig.valid = 1;
            *sig.address = cur.txn.addr >> 2;
            *sig.wren = cur.txn.write;
            *sig.bytesel = cur.txn.bytesel;
            *sig.len = cur.txn.len;
        }
        if (active && cur.txn.write)
            *sig.wdata = cur.txn.data[*sig.beat_num & 0xf];
    }

    bool busy() const
    {
        return active || !queue.empty();
    }

    std::deque<Txn> queue;
    std::vector<Result> results;

private:
    PortSignals sig;
    Result cur{};
    bool active = false;
    bool done = false;
    int beat = 0;
};

Line make_line(uint32_t seed)
{
    Line l;
    for (int i = 0; i < line_words; ++i)
        l[i] = seed * 0x9e3779b9u + i * 0x01010101u;
    return l;
}

Txn read_line(uint32_t addr)
{
    return Txn{false, addr, {}, 0xf, 15};
}

Txn write_line(uint32_t addr, const Line &data, uint8_t bytesel = 0xf)
{
    return Txn{true, addr, data, bytesel, 15};
}

Txn read_word(uint32_t addr)
{
    return Txn{false, addr, {}, 0xf, 0};
}

Txn write_word(uint32_t addr, uint32_t v, uint8_t bytesel = 0xf)
{
    Line l{};
    l[0] = v;
    return Txn{true, addr, l, bytesel, 0};
}

} // namespace

class SDRAMFrontendTestbench : public VerilogTestbench<VSDRAMFrontendWrapper>,
                               public ::testing::Test
{
public:
    SDRAMFrontendTestbench()
        : sdram(dut), iport(PORT_SIGNALS(dut, i)),
          dport(PORT_SIGNALS(dut, d)), xport(PORT_SIGNALS(dut, x)),
          vport(PORT_SIGNALS(dut, v)), uport(PORT_SIGNALS(dut, u))
    {
        reset();

        periodic(ClockSetup, [&] {
            sdram.setup();
            for (auto *p : ports())
                p->setup(cur_cycle());
        });
        periodic(ClockCapture, [&] {
            sdram.capture();
            for (auto *p : ports())
                p->capture(cur_cycle());
            dut.eval();
        });

        while (!dut.init_done)
            cycle();
    }

    ~SDRAMFrontendTestbench()
    {
        for (auto &e : sdram.errors)
            ADD_FAILURE() << e;
    }

    std::array<PortDriver *, 5> ports()
    {
        return {&iport, &dport, &xport, &vport, &uport};
    }

    void run_until_idle(int max_cycles = 200000)
    {
        int i = 0;
        auto busy = [&] {
            for (auto *p : ports())
                if (p->busy())
                    return true;
            return false;
        };
        while (busy() && i++ < max_cycles)
            cycle();
        ASSERT_LT(i, max_cycles) << "timed out";
        cycle(64);
    }

    SDRAMModel sdram;
    PortDriver iport;
    PortDriver dport;
    PortDriver xport;
    PortDriver vport;
    PortDriver uport;
};

TEST_F(SDRAMFrontendTestbench, InitSequence)
{
    EXPECT_EQ(sdram.mrs_count, 1u);
    EXPECT_EQ(sdram.refreshes, 8u);
    EXPECT_TRUE(sdram.errors.empty());
}

TEST_F(SDRAMFrontendTestbench, ReadLineEachPort)
{
    std::array<PortDriver *, 4> line_ports = {&iport, &dport, &xport, &vport};
    for (unsigned p = 0; p < line_ports.size(); ++p) {
        sdram.preload(0x1000 + p * 0x40, make_line(p + 1));
        line_ports[p]->push(read_line(dram_base + 0x1000 + p * 0x40));
    }
    run_until_idle();

    for (unsigned p = 0; p < line_ports.size(); ++p) {
        ASSERT_EQ(line_ports[p]->results.size(), 1u) << "port " << p;
        EXPECT_EQ(line_ports[p]->results[0].data, make_line(p + 1))
            << "port " << p;
    }
    EXPECT_EQ(sdram.reads, 4u * 32);
}

TEST_F(SDRAMFrontendTestbench, ReadLineAcrossBanksAndRows)
{
    // Last line of a row in bank 3, first line of the next row
    uint32_t a = 0x1fc0 + 0x2000 * 5;
    sdram.preload(a, make_line(10));
    sdram.preload(a + 0x40, make_line(11));
    dport.push(read_line(dram_base + a));
    dport.push(read_line(dram_base + a + 0x40));
    run_until_idle();

    ASSERT_EQ(dport.results.size(), 2u);
    EXPECT_EQ(dport.results[0].data, make_line(10));
    EXPECT_EQ(dport.results[1].data, make_line(11));
}

TEST_F(SDRAMFrontendTestbench, WriteLineThenReadBack)
{
    auto line = make_line(3);

    dport.push(write_line(dram_base + 0x2040, line));
    dport.push(read_line(dram_base + 0x2040));
    run_until_idle();

    EXPECT_EQ(sdram.peek(0x2040), line);
    EXPECT_EQ(sdram.writes, 32u);
    ASSERT_EQ(dport.results.size(), 2u);
    EXPECT_EQ(dport.results[1].data, line);
}

TEST_F(SDRAMFrontendTestbench, DMAWriteThenCPURead)
{
    auto line = make_line(8);

    xport.push(write_line(dram_base + 0x3ffffc0, line));
    run_until_idle();
    iport.push(read_line(dram_base + 0x3ffffc0));
    run_until_idle();

    EXPECT_EQ(sdram.peek(0x3ffffc0), line);
    ASSERT_EQ(iport.results.size(), 1u);
    EXPECT_EQ(iport.results[0].data, line);
}

TEST_F(SDRAMFrontendTestbench, WriteByteMask)
{
    auto old_line = make_line(4);
    auto new_line = make_line(5);
    sdram.preload(0x3000, old_line);

    dport.push(write_line(dram_base + 0x3000, new_line, 0x6));
    run_until_idle();

    auto got = sdram.peek(0x3000);
    for (int i = 0; i < line_words; ++i)
        EXPECT_EQ(got[i],
                  (old_line[i] & 0xff0000ffu) | (new_line[i] & 0x00ffff00u))
            << "word " << i;
}

TEST_F(SDRAMFrontendTestbench, UncachedWindow)
{
    sdram.poke32(fb_dram_offset + 0x100, 0x11223344);

    uport.push(read_word(fb_window + 0x100));
    uport.push(write_word(fb_window + 0x104, 0xdeadbeef));
    uport.push(write_word(fb_window + 0x9fffc, 0xcafef00d));
    uport.push(read_word(fb_window + 0x104));
    run_until_idle();

    ASSERT_EQ(uport.results.size(), 4u);
    EXPECT_EQ(uport.results[0].data[0], 0x11223344u);
    EXPECT_EQ(uport.results[3].data[0], 0xdeadbeefu);
    EXPECT_EQ(sdram.peek32(fb_dram_offset + 0x104), 0xdeadbeefu);
    EXPECT_EQ(sdram.peek32(fb_dram_offset + 0x9fffc), 0xcafef00du);
    // Each single word access is two beats.
    EXPECT_EQ(sdram.reads, 4u);
    EXPECT_EQ(sdram.writes, 4u);
}

TEST_F(SDRAMFrontendTestbench, UncachedByteStrobes)
{
    for (uint8_t strb = 1; strb < 16; ++strb) {
        uint32_t off = 0x200 + strb * 4;
        sdram.poke32(fb_dram_offset + off, 0xaaaaaaaa);
        uport.push(write_word(fb_window + off, 0x55555555, strb));
    }
    run_until_idle();

    for (uint8_t strb = 1; strb < 16; ++strb) {
        uint32_t off = 0x200 + strb * 4;
        uint32_t mask = 0;
        for (int b = 0; b < 4; ++b)
            if (strb & (1 << b))
                mask |= 0xffu << (b * 8);
        EXPECT_EQ(sdram.peek32(fb_dram_offset + off),
                  (0xaaaaaaaa & ~mask) | (0x55555555 & mask))
            << "strobes " << int(strb);
    }
}

TEST_F(SDRAMFrontendTestbench, RefreshWhileIdle)
{
    auto before = sdram.refreshes;
    cycle(cycles(7812.5) * 10);
    EXPECT_GE(sdram.refreshes - before, 9u);
    EXPECT_LE(sdram.refreshes - before, 11u);
}

// Video reads take priority: with the other ports saturating the SDRAM a
// video read waits for at most the request in the slot and the one being
// executed.
TEST_F(SDRAMFrontendTestbench, VideoPriority)
{
    for (int n = 0; n < 64; ++n) {
        dport.push(write_line(dram_base + 0x10000 + (n % 16) * 64,
                              make_line(n)));
        xport.push(read_line(dram_base + 0x20000 + (n % 16) * 64));
        iport.push(read_line(dram_base + 0x30000 + (n % 16) * 64));
    }
    for (int n = 0; n < 16; ++n)
        vport.push(read_line(dram_base + 0x40000 + n * 64));
    run_until_idle();

    ASSERT_EQ(vport.results.size(), 16u);
    uint64_t worst = 0;
    for (auto &r : vport.results)
        worst = std::max(worst, r.end - r.start);
    // A line is about 40 cycles plus refresh.
    EXPECT_LT(worst, 200u);
    // The other ports are still busy for most of the run.
    EXPECT_GT(dport.results.back().end, vport.results.back().end);
}

TEST_F(SDRAMFrontendTestbench, ConcurrentPortsRandomStress)
{
    std::mt19937 rng(42);

    // The data and DMA ports own lines [0, 32) and [32, 64) and read and
    // write them, the instruction and video ports read the read only lines
    // [64, 96), the uncached port reads and writes its own words in the
    // window.
    std::map<uint32_t, Line> golden;
    for (uint32_t l = 0; l < 96; ++l) {
        golden[l] = make_line(100 + l);
        sdram.preload(l * 64, golden[l]);
    }
    std::map<uint32_t, uint32_t> golden_u;
    for (uint32_t w = 0; w < 64; ++w) {
        golden_u[w] = 0x1000 + w;
        sdram.poke32(fb_dram_offset + w * 4, golden_u[w]);
    }

    struct Expect {
        bool write;
        Line data;
    };
    std::vector<Expect> expected_d, expected_x;
    std::vector<uint32_t> expected_i, expected_v;
    std::vector<std::optional<uint32_t>> expected_u;

    auto rw_port = [&](PortDriver &p, std::vector<Expect> &exp,
                       uint32_t base) {
        uint32_t l = base + rng() % 32;
        if (rng() % 2) {
            auto line = make_line(rng());
            golden[l] = line;
            p.push(write_line(dram_base + l * 64, line));
            exp.push_back({true, {}});
        } else {
            p.push(read_line(dram_base + l * 64));
            exp.push_back({false, golden[l]});
        }
    };

    for (int n = 0; n < 200; ++n) {
        rw_port(dport, expected_d, 0);
        rw_port(xport, expected_x, 32);

        uint32_t il = 64 + rng() % 32;
        iport.push(read_line(dram_base + il * 64));
        expected_i.push_back(il);

        if (n % 4 == 0) {
            uint32_t vl = 64 + rng() % 32;
            vport.push(read_line(dram_base + vl * 64));
            expected_v.push_back(vl);
        }

        uint32_t w = rng() % 64;
        if (rng() % 2) {
            uint32_t v = rng();
            golden_u[w] = v;
            uport.push(write_word(fb_window + w * 4, v));
            expected_u.push_back(std::nullopt);
        } else {
            uport.push(read_word(fb_window + w * 4));
            expected_u.push_back(golden_u[w]);
        }
    }

    run_until_idle(2000000);

    auto check_rw = [&](PortDriver &p, std::vector<Expect> &exp,
                        const char *name) {
        ASSERT_EQ(p.results.size(), exp.size()) << name;
        for (size_t i = 0; i < exp.size(); ++i) {
            if (!exp[i].write) {
                EXPECT_EQ(p.results[i].data, exp[i].data)
                    << name << " txn " << i;
            }
        }
    };
    check_rw(dport, expected_d, "d");
    check_rw(xport, expected_x, "x");

    ASSERT_EQ(iport.results.size(), expected_i.size());
    for (size_t i = 0; i < expected_i.size(); ++i)
        EXPECT_EQ(iport.results[i].data, golden[expected_i[i]])
            << "i txn " << i;
    ASSERT_EQ(vport.results.size(), expected_v.size());
    for (size_t i = 0; i < expected_v.size(); ++i)
        EXPECT_EQ(vport.results[i].data, golden[expected_v[i]])
            << "v txn " << i;
    ASSERT_EQ(uport.results.size(), expected_u.size());
    for (size_t i = 0; i < expected_u.size(); ++i) {
        if (expected_u[i]) {
            EXPECT_EQ(uport.results[i].data[0], *expected_u[i])
                << "u txn " << i;
        }
    }

    for (uint32_t l = 0; l < 64; ++l)
        EXPECT_EQ(sdram.peek(l * 64), golden[l]) << "line " << l;
    for (uint32_t w = 0; w < 64; ++w)
        EXPECT_EQ(sdram.peek32(fb_dram_offset + w * 4), golden_u[w])
            << "word " << w;
}
