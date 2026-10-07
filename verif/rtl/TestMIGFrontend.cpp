// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
#include <array>
#include <deque>
#include <map>
#include <random>

#include <gtest/gtest.h>
#include <VMIGFrontendWrapper.h>

#include "VerilogTestbench.h"

namespace
{

const int line_words = 16;
const int beats_per_line = 4;
const uint32_t dram_base = 0x80000000;

using Line = std::array<uint32_t, line_words>;
using Beat = std::array<uint32_t, 4>;

// Behavioural model of the MIG native app interface: commands are accepted
// when app_en && app_rdy, write data is buffered ahead of the command and
// read data is returned in request order after a configurable latency.
class MIGModel
{
public:
    explicit MIGModel(VMIGFrontendWrapper &dut)
        : dut(dut), rng(1234), rdy_percent(100), wdf_rdy_percent(100),
          min_latency(20), max_latency(20), cycle(0), last_return(0)
    {
    }

    void set_backpressure(int rdy, int wdf_rdy)
    {
        rdy_percent = rdy;
        wdf_rdy_percent = wdf_rdy;
    }

    void set_latency(int min, int max)
    {
        min_latency = min;
        max_latency = max;
    }

    // Before the clock edge: handshakes that take place on this edge.
    void setup()
    {
        if (dut.app_wdf_wren && dut.app_wdf_rdy) {
            EXPECT_TRUE(dut.app_wdf_end);
            Beat data;
            for (int i = 0; i < 4; ++i)
                data[i] = dut.app_wdf_data[i];
            wdf.push_back({data, static_cast<uint16_t>(dut.app_wdf_mask)});
        }

        if (dut.app_en && dut.app_rdy) {
            uint32_t addr = dut.app_addr;
            // Each command is a BL8 of 16-bit words: 8 app_addr units
            EXPECT_EQ(addr & 7, 0u);
            uint32_t byte_addr = addr * 2;

            if (dut.app_cmd == 0) {
                ++write_cmds;
                // The frontend always provides data ahead of the command.
                EXPECT_FALSE(wdf.empty());
                if (!wdf.empty()) {
                    auto [data, mask] = wdf.front();
                    wdf.pop_front();
                    for (int b = 0; b < 16; ++b) {
                        if (mask & (1 << b))
                            continue;
                        uint8_t v = (data[b / 4] >> ((b % 4) * 8)) & 0xff;
                        bytes[byte_addr + b] = v;
                    }
                }
            } else if (dut.app_cmd == 1) {
                ++read_cmds;
                std::uniform_int_distribution<int> lat(min_latency,
                                                       max_latency);
                uint64_t when = std::max(last_return + 1, cycle + lat(rng));
                last_return = when;
                rd_queue.push_back({when, read_beat(byte_addr)});
            } else {
                ADD_FAILURE() << "unexpected app_cmd " << dut.app_cmd;
            }
        }
    }

    // After the clock edge: drive the inputs for the next cycle.
    void capture()
    {
        ++cycle;
        std::uniform_int_distribution<int> pct(0, 99);
        dut.init_calib_complete = 1;
        dut.app_rdy = pct(rng) < rdy_percent;
        dut.app_wdf_rdy = pct(rng) < wdf_rdy_percent;

        dut.app_rd_data_valid = 0;
        dut.app_rd_data_end = 0;
        if (!rd_queue.empty() && rd_queue.front().first <= cycle) {
            auto data = rd_queue.front().second;
            rd_queue.pop_front();
            for (int i = 0; i < 4; ++i)
                dut.app_rd_data[i] = data[i];
            dut.app_rd_data_valid = 1;
            dut.app_rd_data_end = 1;
        }
    }

    Beat read_beat(uint32_t byte_addr)
    {
        Beat beat{};
        for (int b = 0; b < 16; ++b)
            beat[b / 4] |= uint32_t(bytes[byte_addr + b]) << ((b % 4) * 8);
        return beat;
    }

    // The DRAM is 256MB, mapped at dram_base in the CPU address space.
    void preload(uint32_t byte_addr, const Line &line)
    {
        byte_addr &= 0x0fffffff;
        for (int w = 0; w < line_words; ++w)
            for (int b = 0; b < 4; ++b)
                bytes[byte_addr + w * 4 + b] = (line[w] >> (b * 8)) & 0xff;
    }

    Line peek(uint32_t byte_addr)
    {
        byte_addr &= 0x0fffffff;
        Line line{};
        for (int w = 0; w < line_words; ++w)
            for (int b = 0; b < 4; ++b)
                line[w] |= uint32_t(bytes[byte_addr + w * 4 + b]) << (b * 8);
        return line;
    }

    bool idle() const
    {
        return rd_queue.empty() && wdf.empty();
    }

    unsigned read_cmds = 0;
    unsigned write_cmds = 0;

private:
    VMIGFrontendWrapper &dut;
    std::mt19937 rng;
    int rdy_percent;
    int wdf_rdy_percent;
    int min_latency;
    int max_latency;
    uint64_t cycle;
    uint64_t last_return;
    std::map<uint32_t, uint8_t> bytes;
    std::deque<std::pair<Beat, uint16_t>> wdf;
    std::deque<std::pair<uint64_t, Beat>> rd_queue;
};

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

enum Port { PORT_I, PORT_D, PORT_X };

// Drives a BusAdapter the same way the caches do: valid is held until
// complete, write data follows beat_num.
template <Port port>
class PortDriver
{
public:
    explicit PortDriver(VMIGFrontendWrapper &dut) : dut(dut)
    {
    }

    void push(const Txn &t)
    {
        queue.push_back(t);
    }

    void setup(uint64_t cycle)
    {
        if (!active)
            return;
        if (beat_ack()) {
            EXPECT_LT(beat, 16);
            if (beat < 16)
                cur.data[beat++] = rdata();
        }
        if (complete()) {
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
            set_valid(false);
        }
        if (!active && !queue.empty() && cycle >= hold_off_until) {
            cur = Result{queue.front(), {}, cycle, 0};
            queue.pop_front();
            active = true;
            beat = 0;
            set_valid(true);
        }
        if (active && cur.txn.write) {
            if constexpr (port == PORT_D) {
                auto n = dut.d_beat_num;
                dut.d_wdata = cur.txn.data[n & 0xf];
            } else if constexpr (port == PORT_X) {
                auto n = dut.x_beat_num;
                dut.x_wdata = cur.txn.data[n & 0xf];
            }
        }
    }

    bool busy() const
    {
        return active || !queue.empty();
    }

    std::deque<Txn> queue;
    std::vector<Result> results;
    uint64_t hold_off_until = 0;

private:
    bool beat_ack() const
    {
        if constexpr (port == PORT_D)
            return dut.d_beat_ack;
        else if constexpr (port == PORT_X)
            return dut.x_beat_ack;
        return dut.i_beat_ack;
    }
    bool complete() const
    {
        if constexpr (port == PORT_D)
            return dut.d_complete;
        else if constexpr (port == PORT_X)
            return dut.x_complete;
        return dut.i_complete;
    }
    uint32_t rdata() const
    {
        if constexpr (port == PORT_D)
            return dut.d_rdata;
        else if constexpr (port == PORT_X)
            return dut.x_rdata;
        return dut.i_rdata;
    }

    void set_valid(bool v)
    {
        if constexpr (port == PORT_D) {
            dut.d_valid = v;
            if (v) {
                dut.d_address = cur.txn.addr >> 2;
                dut.d_wren = cur.txn.write;
                dut.d_bytesel = cur.txn.bytesel;
                dut.d_len = cur.txn.len;
            }
        } else if constexpr (port == PORT_X) {
            dut.x_valid = v;
            if (v) {
                dut.x_address = cur.txn.addr >> 2;
                dut.x_wren = cur.txn.write;
                dut.x_bytesel = cur.txn.bytesel;
                dut.x_len = cur.txn.len;
            }
        } else {
            dut.i_valid = v;
            if (v) {
                dut.i_address = cur.txn.addr >> 2;
                dut.i_len = cur.txn.len;
            }
        }
    }

    VMIGFrontendWrapper &dut;
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

} // namespace

class MIGFrontendTestbench : public VerilogTestbench<VMIGFrontendWrapper>,
                             public ::testing::Test
{
public:
    MIGFrontendTestbench() : mig(dut), iport(dut), dport(dut), xport(dut)
    {
        dut.init_calib_complete = 1;
        dut.app_rdy = 1;
        dut.app_wdf_rdy = 1;
        dut.i_valid = 0;
        dut.d_valid = 0;
        dut.i_len = 15;
        dut.d_len = 15;
        dut.d_bytesel = 0xf;
        dut.x_valid = 0;
        dut.x_len = 15;
        dut.x_bytesel = 0xf;
        reset();

        periodic(ClockSetup, [&] {
            mig.setup();
            iport.setup(cur_cycle());
            dport.setup(cur_cycle());
            xport.setup(cur_cycle());
        });
        periodic(ClockCapture, [&] {
            mig.capture();
            iport.capture(cur_cycle());
            dport.capture(cur_cycle());
            xport.capture(cur_cycle());
            dut.eval();
        });
    }

    void run_until_idle(int max_cycles = 100000)
    {
        int i = 0;
        while ((iport.busy() || dport.busy() || xport.busy() || !mig.idle()) &&
               i++ < max_cycles)
            cycle();
        ASSERT_LT(i, max_cycles) << "timed out";
        // Let any trailing write commands drain
        cycle(8);
    }

    static Txn read_line(uint32_t addr)
    {
        return Txn{false, addr, {}, 0xf, 15};
    }

    static Txn write_line(uint32_t addr, const Line &data,
                          uint8_t bytesel = 0xf)
    {
        return Txn{true, addr, data, bytesel, 15};
    }

    MIGModel mig;
    PortDriver<PORT_I> iport;
    PortDriver<PORT_D> dport;
    PortDriver<PORT_X> xport;
};

TEST_F(MIGFrontendTestbench, ReadLineInstruction)
{
    auto line = make_line(1);
    mig.preload(dram_base + 0x1000, line);

    iport.push(read_line(dram_base + 0x1000));
    run_until_idle();

    ASSERT_EQ(iport.results.size(), 1u);
    EXPECT_EQ(iport.results[0].data, line);
    EXPECT_EQ(mig.read_cmds, 4u);
}

TEST_F(MIGFrontendTestbench, ReadLineData)
{
    auto line = make_line(2);
    mig.preload(dram_base + 0x0ffffc0, line);

    dport.push(read_line(dram_base + 0x0ffffc0));
    run_until_idle();

    ASSERT_EQ(dport.results.size(), 1u);
    EXPECT_EQ(dport.results[0].data, line);
}

TEST_F(MIGFrontendTestbench, WriteLineThenReadBack)
{
    auto line = make_line(3);

    dport.push(write_line(dram_base + 0x2040, line));
    dport.push(read_line(dram_base + 0x2040));
    run_until_idle();

    EXPECT_EQ(mig.peek(dram_base + 0x2040), line);
    EXPECT_EQ(mig.write_cmds, 4u);
    ASSERT_EQ(dport.results.size(), 2u);
    EXPECT_EQ(dport.results[1].data, line);
}

TEST_F(MIGFrontendTestbench, WriteByteMask)
{
    auto old_line = make_line(4);
    auto new_line = make_line(5);
    mig.preload(dram_base + 0x3000, old_line);

    dport.push(write_line(dram_base + 0x3000, new_line, 0x6));
    run_until_idle();

    auto got = mig.peek(dram_base + 0x3000);
    for (int i = 0; i < line_words; ++i)
        EXPECT_EQ(got[i],
                  (old_line[i] & 0xff0000ffu) | (new_line[i] & 0x00ffff00u))
            << "word " << i;
}

// A write that has completed from the data port's point of view may still
// have commands waiting to be issued.  A read of the same line from the
// instruction port immediately after must still observe the new data.
TEST_F(MIGFrontendTestbench, ReadAfterWriteHazard)
{
    auto old_line = make_line(6);
    auto new_line = make_line(7);
    mig.preload(dram_base + 0x4000, old_line);
    // Throttle commands so that the write commands are still queued in the
    // frontend when the data port sees completion.
    mig.set_backpressure(30, 100);

    dport.push(write_line(dram_base + 0x4000, new_line));
    while (dport.results.empty())
        cycle();
    EXPECT_LT(mig.write_cmds, 4u) << "test did not exercise the hazard";

    iport.push(read_line(dram_base + 0x4000));
    run_until_idle();

    ASSERT_EQ(iport.results.size(), 1u);
    EXPECT_EQ(iport.results[0].data, new_line);
}

TEST_F(MIGFrontendTestbench, ConcurrentPortsRandomStress)
{
    std::mt19937 rng(42);
    mig.set_backpressure(60, 70);
    mig.set_latency(8, 40);

    // The data port owns lines [0, 32) and reads/writes them, the
    // instruction port reads its own read-only lines [64, 96) so the expected
    // values are unambiguous.
    std::map<uint32_t, Line> golden;
    for (uint32_t l = 0; l < 32; ++l) {
        golden[l] = make_line(100 + l);
        mig.preload(dram_base + l * 64, golden[l]);
    }
    for (uint32_t l = 64; l < 96; ++l) {
        golden[l] = make_line(100 + l);
        mig.preload(dram_base + l * 64, golden[l]);
    }

    std::vector<std::pair<uint32_t, Line>> expected_d;
    std::vector<uint32_t> expected_i;
    for (int n = 0; n < 300; ++n) {
        uint32_t l = rng() % 32;
        if (rng() % 2) {
            auto line = make_line(rng());
            golden[l] = line;
            dport.push(write_line(dram_base + l * 64, line));
            expected_d.push_back({l, {}});
        } else {
            dport.push(read_line(dram_base + l * 64));
            expected_d.push_back({l, golden[l]});
        }

        uint32_t il = 64 + rng() % 32;
        iport.push(read_line(dram_base + il * 64));
        expected_i.push_back(il);
    }

    run_until_idle(1000000);

    ASSERT_EQ(dport.results.size(), expected_d.size());
    for (size_t i = 0; i < expected_d.size(); ++i) {
        if (!dport.results[i].txn.write) {
            EXPECT_EQ(dport.results[i].data, expected_d[i].second)
                << "d txn " << i;
        }
    }

    ASSERT_EQ(iport.results.size(), expected_i.size());
    for (size_t i = 0; i < expected_i.size(); ++i)
        EXPECT_EQ(iport.results[i].data, golden[expected_i[i]])
            << "i txn " << i;

    for (uint32_t l = 0; l < 32; ++l)
        EXPECT_EQ(mig.peek(dram_base + l * 64), golden[l]) << "line " << l;
}

TEST_F(MIGFrontendTestbench, DeviceAccessesBypassDRAM)
{
    dport.push(Txn{false, 0xfffd0010, {}, 0xf, 0});
    Line wdata{};
    wdata[0] = 0xcafef00d;
    dport.push(Txn{true, 0xffff0004, wdata, 0x3, 0});
    iport.push(Txn{false, 0x40000040, {}, 0xf, 15});
    run_until_idle();

    ASSERT_EQ(dport.results.size(), 2u);
    EXPECT_EQ(dport.results[0].data[0], 0xfffd0010u ^ 0x5a5a5a5au);
    EXPECT_EQ(dut.dev_last_waddr, 0xffff0004u);
    EXPECT_EQ(dut.dev_last_wdata, 0xcafef00du);
    EXPECT_EQ(dut.dev_last_wstb, 0x3u);
    EXPECT_EQ(dut.dev_write_count, 1u);

    ASSERT_EQ(iport.results.size(), 1u);
    for (int i = 0; i < line_words; ++i)
        EXPECT_EQ(iport.results[0].data[i],
                  (0x40000040u + i * 4) ^ 0x5a5a5a5au);

    EXPECT_EQ(mig.read_cmds, 0u);
    EXPECT_EQ(mig.write_cmds, 0u);
}

// With no backpressure the cost of a line fill should be the MIG latency plus
// the 16 cycles to stream the line at 32 bits/cycle and a few cycles of
// pipeline overhead - no bubbles in the data stream.
TEST_F(MIGFrontendTestbench, FillHasNoBubbles)
{
    const int latency = 20;
    mig.set_latency(latency, latency);
    for (int n = 0; n < 8; ++n)
        dport.push(read_line(dram_base + n * 64));
    dport.push(write_line(dram_base + 0x8000, make_line(9)));
    run_until_idle();

    ASSERT_EQ(dport.results.size(), 9u);
    for (int n = 0; n < 8; ++n) {
        auto cycles = dport.results[n].end - dport.results[n].start;
        // valid->arvalid (1) + arvalid->cmd (1) + latency + FIFO (1) +
        // 16 words
        EXPECT_LE(cycles, uint64_t(latency + 16 + 4)) << "line " << n;
    }
    // A write streams at one word per cycle.
    auto wr_cycles = dport.results[8].end - dport.results[8].start;
    EXPECT_LE(wr_cycles, 16u + 3u);
    RecordProperty("fill_cycles",
                   int(dport.results[0].end - dport.results[0].start));
}

TEST_F(MIGFrontendTestbench, DMAPortWriteThenReadBack)
{
    auto line = make_line(20);

    xport.push(write_line(dram_base + 0x5040, line));
    xport.push(read_line(dram_base + 0x5040));
    run_until_idle();

    EXPECT_EQ(mig.peek(dram_base + 0x5040), line);
    ASSERT_EQ(xport.results.size(), 2u);
    EXPECT_EQ(xport.results[1].data, line);
}

// A DMA write that is still waiting for its commands must be observed by a
// CPU read of the same line, as for the data port.
TEST_F(MIGFrontendTestbench, DMAWriteThenDataReadHazard)
{
    auto old_line = make_line(21);
    auto new_line = make_line(22);
    mig.preload(dram_base + 0x6000, old_line);
    mig.set_backpressure(30, 100);

    xport.push(write_line(dram_base + 0x6000, new_line));
    while (xport.results.empty())
        cycle();
    EXPECT_LT(mig.write_cmds, 4u) << "test did not exercise the hazard";

    dport.push(read_line(dram_base + 0x6000));
    run_until_idle();

    ASSERT_EQ(dport.results.size(), 1u);
    EXPECT_EQ(dport.results[0].data, new_line);
}

TEST_F(MIGFrontendTestbench, ThreePortsRandomStress)
{
    std::mt19937 rng(7);
    mig.set_backpressure(60, 70);
    mig.set_latency(8, 40);

    // The data port owns lines [0, 32), the DMA port [32, 64), both read and
    // write them, the instruction port reads [64, 96).
    std::map<uint32_t, Line> golden;
    for (uint32_t l = 0; l < 96; ++l) {
        golden[l] = make_line(200 + l);
        mig.preload(dram_base + l * 64, golden[l]);
    }

    std::vector<std::pair<bool, Line>> expected_d;
    std::vector<std::pair<bool, Line>> expected_x;
    std::vector<uint32_t> expected_i;
    for (int n = 0; n < 300; ++n) {
        uint32_t dl = rng() % 32;
        if (rng() % 2) {
            golden[dl] = make_line(rng());
            dport.push(write_line(dram_base + dl * 64, golden[dl]));
            expected_d.push_back({true, {}});
        } else {
            dport.push(read_line(dram_base + dl * 64));
            expected_d.push_back({false, golden[dl]});
        }

        uint32_t xl = 32 + rng() % 32;
        if (rng() % 2) {
            golden[xl] = make_line(rng());
            xport.push(write_line(dram_base + xl * 64, golden[xl]));
            expected_x.push_back({true, {}});
        } else {
            xport.push(read_line(dram_base + xl * 64));
            expected_x.push_back({false, golden[xl]});
        }

        uint32_t il = 64 + rng() % 32;
        iport.push(read_line(dram_base + il * 64));
        expected_i.push_back(il);
    }

    run_until_idle(2000000);

    ASSERT_EQ(dport.results.size(), expected_d.size());
    for (size_t i = 0; i < expected_d.size(); ++i) {
        if (!expected_d[i].first) {
            EXPECT_EQ(dport.results[i].data, expected_d[i].second) << "d txn " << i;
        }
    }

    ASSERT_EQ(xport.results.size(), expected_x.size());
    for (size_t i = 0; i < expected_x.size(); ++i) {
        if (!expected_x[i].first) {
            EXPECT_EQ(xport.results[i].data, expected_x[i].second) << "x txn " << i;
        }
    }

    ASSERT_EQ(iport.results.size(), expected_i.size());
    for (size_t i = 0; i < expected_i.size(); ++i)
        EXPECT_EQ(iport.results[i].data, golden[expected_i[i]]) << "i txn " << i;

    for (uint32_t l = 0; l < 64; ++l)
        EXPECT_EQ(mig.peek(dram_base + l * 64), golden[l]) << "line " << l;
}
