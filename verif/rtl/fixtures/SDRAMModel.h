// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <array>
#include <cstdint>
#include <cstdio>
#include <deque>
#include <random>
#include <string>
#include <unordered_map>
#include <vector>

namespace sdram
{

// Timing at 60MHz for an IS42S16320D-7, in cycles.
inline const double clk_ns = 16.667;
inline const int cas_latency = 2;

inline int cycles(double ns)
{
    int c = static_cast<int>(ns / clk_ns);
    return c * clk_ns < ns ? c + 1 : c;
}

inline const int tRCD = cycles(15);
inline const int tRP = cycles(15);
inline const int tRC = cycles(60);
inline const int tRAS = cycles(37);
inline const int tRFC = cycles(60);
inline const int tRRD = cycles(14);
inline const int tDPL = 2;
inline const int tMRD = 2;
// 8192 refreshes per 64ms.  The controller can't refresh in the middle of
// a request so allow some slack for one.
inline const int max_refresh_gap = cycles(7812.5) + 64;

// Cycle based model of an x16 SDR SDRAM with 4 banks, 8192 rows and 1024
// columns that checks the command timing.  The controller's outputs are
// registered so the model samples them before each clock edge, as the
// device would on its rising edge.
template <typename T> class SDRAMModel
{
public:
    explicit SDRAMModel(T &dut) : dut(dut), rng(99)
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

        if (log && cmd != NOP)
            printf("sdram @%llu cmd %d ba %u addr %04x dq %04x dqm %u\n",
                   static_cast<unsigned long long>(edge), cmd, ba, addr,
                   dut.s_dq_o, dut.s_dqm);

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
                uint16_t v = read16(key);
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
                uint16_t v = read16(key);
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
        uint32_t lo = read16(key_of(byte_addr));
        uint32_t hi = read16(key_of(byte_addr + 2));
        return lo | (hi << 16);
    }

    template <size_t N>
    void preload(uint32_t byte_addr, const std::array<uint32_t, N> &words)
    {
        for (size_t w = 0; w < N; ++w)
            poke32(byte_addr + w * 4, words[w]);
    }

    template <size_t N = 16> std::array<uint32_t, N> peek(uint32_t byte_addr)
    {
        std::array<uint32_t, N> l{};
        for (size_t w = 0; w < N; ++w)
            l[w] = peek32(byte_addr + w * 4);
        return l;
    }

    unsigned refreshes = 0;
    unsigned activates = 0;
    unsigned reads = 0;
    unsigned writes = 0;
    unsigned mrs_count = 0;
    bool log = false;
    std::vector<std::string> errors;

private:
    struct Bank {
        bool open = false;
        unsigned row = 0;
        uint64_t last_act = 0;
        uint64_t last_pre = 0;
        uint64_t last_write = 0;
    };

    // Unwritten locations read as power up garbage, as on a real part.
    uint16_t read16(uint32_t key) const
    {
        auto it = mem.find(key);
        if (it != mem.end())
            return it->second;
        uint32_t h = key * 0x9e3779b1u;
        return (h ^ (h >> 16)) & 0xffff;
    }

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

    T &dut;
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

} // namespace sdram
