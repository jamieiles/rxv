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

namespace
{

const int line_words = 16;
const uint32_t dram_base = 0x80000000;
const uint32_t fb_window = 0xf8000000;
const uint32_t fb_dram_offset = 0x03f00000;

// Timing at 60MHz for an IS42S16320D-7, in cycles.
const double clk_ns = 16.667;
const int cas_latency = 2;

int cycles(double ns)
{
    int c = static_cast<int>(ns / clk_ns);
    return c * clk_ns < ns ? c + 1 : c;
}

const int tRCD = cycles(15);
const int tRP = cycles(15);
const int tRC = cycles(60);
const int tRAS = cycles(37);
const int tRFC = cycles(60);
const int tRRD = cycles(14);
const int tDPL = 2;
const int tMRD = 2;
// 8192 refreshes per 64ms.  The controller can't refresh in the middle of
// a request so allow some slack for one.
const int max_refresh_gap = cycles(7812.5) + 64;

using Line = std::array<uint32_t, line_words>;

// Cycle based model of an x16 SDR SDRAM with 4 banks, 8192 rows and 1024
// columns that checks the command timing.  The controller's outputs are
// registered so the model samples them before each clock edge, as the
// device would on its rising edge.
class SDRAMModel
{
public:
    explicit SDRAMModel(VSDRAMFrontendWrapper &dut) : dut(dut), rng(99)
    {
        for (auto &b : banks)
            b = Bank{};
    }

    enum Cmd { MRS = 0, REF = 1, PRE = 2, ACT = 3, WRITE = 4, READ = 5,
               BST = 6, NOP = 7 };

    void setup()
    {
        ++edge;

        if (dut.s_cs_n || !dut.s_cke)
            return;

        int cmd = (dut.s_ras_n << 2) | (dut.s_cas_n << 1) | dut.s_we_n;
        unsigned ba = dut.s_ba;
        unsigned addr = dut.s_addr;

        if (cmd != NOP && !mode_set && cmd != PRE && cmd != REF &&
            cmd != MRS)
            error("command before the mode register was set");

        switch (cmd) {
        case MRS:
            for (auto &b : banks)
                if (b.open)
                    error("MRS with a bank open");
            check_since(last_pre_any, tRP, "MRS after PRE (tRP)");
            check_since(last_ref, tRFC, "MRS after REF (tRFC)");
            if ((addr & 7) != 0)
                error("burst length is not 1");
            cl = (addr >> 4) & 7;
            if (cl != cas_latency)
                error("unexpected CAS latency");
            mode_set = true;
            last_mrs = edge;
            ++mrs_count;
            break;
        case REF:
            for (auto &b : banks)
                if (b.open)
                    error("REF with a bank open");
            check_since(last_pre_any, tRP, "REF after PRE (tRP)");
            check_since(last_ref, tRFC, "REF after REF (tRFC)");
            if (mode_set && last_ref && edge - last_ref > max_refresh_gap)
                error("refresh interval exceeded");
            last_ref = edge;
            ++refreshes;
            break;
        case PRE:
            if (addr & (1 << 10)) {
                for (unsigned b = 0; b < 4; ++b)
                    precharge(b);
            } else {
                precharge(ba);
            }
            last_pre_any = edge;
            break;
        case ACT: {
            auto &b = banks[ba];
            if (b.open)
                error("ACT to an open bank");
            check_since(b.last_pre, tRP, "ACT after PRE (tRP)");
            check_since(b.last_act, tRC, "ACT to ACT same bank (tRC)");
            check_since(last_act_any, tRRD, "ACT to ACT (tRRD)");
            check_since(last_ref, tRFC, "ACT after REF (tRFC)");
            check_since(last_mrs, tMRD, "ACT after MRS (tMRD)");
            b.open = true;
            b.row = addr;
            b.last_act = edge;
            last_act_any = edge;
            ++activates;
            break;
        }
        case READ:
        case WRITE: {
            auto &b = banks[ba];
            if (!b.open)
                error("column command to a closed bank");
            check_since(b.last_act, tRCD, "column command after ACT (tRCD)");
            if (addr & (1 << 10))
                error("unexpected auto precharge");
            uint32_t key = (ba << 23) | (b.row << 10) | (addr & 0x3ff);
            if (cmd == WRITE) {
                if (!dut.s_dq_oe)
                    error("write without driving DQ");
                uint16_t v = mem.count(key) ? mem[key] : 0;
                if (!(dut.s_dqm & 1))
                    v = (v & 0xff00) | (dut.s_dq_o & 0x00ff);
                if (!(dut.s_dqm & 2))
                    v = (v & 0x00ff) | (dut.s_dq_o & 0xff00);
                mem[key] = v;
                b.last_write = edge;
                ++writes;
            } else {
                if (dut.s_dqm)
                    error("DQM asserted for a read");
                uint16_t v = mem.count(key) ? mem[key] : 0;
                // Sampled by the controller CL edges after this one
                reads_out.push_back({edge + cl, v});
                ++reads;
            }
            break;
        }
        case BST:
            error("unexpected burst terminate");
            break;
        default:
            break;
        }

        if (dut.s_dq_oe && driving)
            error("DQ contention");
    }

    void capture()
    {
        driving = false;
        // Drive garbage outside of read data so that a mistimed capture is
        // caught.
        dut.s_dq_i = rng() & 0xffff;
        while (!reads_out.empty() && reads_out.front().first < edge + 1)
            reads_out.pop_front();
        if (!reads_out.empty() && reads_out.front().first == edge + 1) {
            dut.s_dq_i = reads_out.front().second;
            reads_out.pop_front();
            driving = true;
        }
    }

    // Byte addresses within the device, using the controller's mapping:
    // column [10:1], bank [12:11], row [25:13].
    static uint32_t key_of(uint32_t byte_addr)
    {
        uint32_t col = (byte_addr >> 1) & 0x3ff;
        uint32_t bank = (byte_addr >> 11) & 3;
        uint32_t row = (byte_addr >> 13) & 0x1fff;
        return (bank << 23) | (row << 10) | col;
    }

    void poke32(uint32_t byte_addr, uint32_t v)
    {
        mem[key_of(byte_addr)] = v & 0xffff;
        mem[key_of(byte_addr + 2)] = v >> 16;
    }

    uint32_t peek32(uint32_t byte_addr)
    {
        uint32_t lo = mem.count(key_of(byte_addr)) ? mem[key_of(byte_addr)] : 0;
        uint32_t hi = mem.count(key_of(byte_addr + 2)) ?
                          mem[key_of(byte_addr + 2)] : 0;
        return lo | (hi << 16);
    }

    void preload(uint32_t byte_addr, const Line &line)
    {
        for (int w = 0; w < line_words; ++w)
            poke32(byte_addr + w * 4, line[w]);
    }

    Line peek(uint32_t byte_addr)
    {
        Line l{};
        for (int w = 0; w < line_words; ++w)
            l[w] = peek32(byte_addr + w * 4);
        return l;
    }

    unsigned refreshes = 0;
    unsigned activates = 0;
    unsigned reads = 0;
    unsigned writes = 0;
    unsigned mrs_count = 0;
    std::vector<std::string> errors;

private:
    struct Bank {
        bool open = false;
        unsigned row = 0;
        uint64_t last_act = 0;
        uint64_t last_pre = 0;
        uint64_t last_write = 0;
    };

    void error(const std::string &msg)
    {
        errors.push_back("@" + std::to_string(edge) + " " + msg);
    }

    void check_since(uint64_t when, int min, const char *what)
    {
        if (when && edge - when < static_cast<uint64_t>(min))
            error(std::string("timing violation: ") + what);
    }

    void precharge(unsigned ba)
    {
        auto &b = banks[ba];
        if (b.open) {
            check_since(b.last_act, tRAS, "PRE after ACT (tRAS)");
            check_since(b.last_write, tDPL, "PRE after WRITE (tDPL)");
        }
        b.open = false;
        b.last_pre = edge;
    }

    VSDRAMFrontendWrapper &dut;
    std::mt19937 rng;
    std::array<Bank, 4> banks;
    std::unordered_map<uint32_t, uint16_t> mem;
    std::deque<std::pair<uint64_t, uint16_t>> reads_out;
    uint64_t edge = 0;
    uint64_t last_ref = 0;
    uint64_t last_mrs = 0;
    uint64_t last_pre_any = 0;
    uint64_t last_act_any = 0;
    unsigned cl = 0;
    bool mode_set = false;
    bool driving = false;
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
