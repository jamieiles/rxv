// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
#include <arpa/inet.h>
#include <netinet/in.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>

#include <array>
#include <cassert>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <thread>
#include <unordered_set>
#include <vector>

#include <boost/program_options.hpp>
#include <fmt/core.h>

#include "MemoryDevice.h"
#include "Trace_generated.h"
#include "TraceFile.h"

// ---------------------------------------------------------------------------
// TrackingMemoryBus — same as MakeCore.cpp
// ---------------------------------------------------------------------------

class TrackingMemoryBus : public MemoryBus
{
public:
    TrackingMemoryBus(uint32_t ram_base, size_t ram_size)
        : MemoryBus(ram_base, ram_size, false)
        , ram_base(ram_base)
        , ram_size(ram_size)
    {
        accessed.resize(ram_size / 4096, false);
    }

    void read(uint32_t addr, char *dst, size_t len, bool ifetch) override
    {
        mark_accessed(addr);
        MemoryBus::read(addr, dst, len, ifetch);
    }

    void write(uint32_t addr, const char *val, size_t len) override
    {
        mark_accessed(addr);
        MemoryBus::write(addr, val, len);
    }

    void write(uint32_t addr, uint32_t val, uint8_t wstb) override
    {
        mark_accessed(addr);
        MemoryBus::write(addr, val, wstb);
    }

    uint32_t read(uint32_t addr, bool ifetch) override
    {
        mark_accessed(addr);
        return MemoryBus::read(addr, ifetch);
    }

private:
    void mark_accessed(uint32_t addr)
    {
        if (addr < ram_base || addr >= ram_base + ram_size)
            return;
        accessed[(addr - ram_base) >> 12] = true;
    }

    std::vector<bool> accessed;
    uint32_t ram_base;
    size_t ram_size;
};

// ---------------------------------------------------------------------------
// SV32 virtual-to-physical translation
// ---------------------------------------------------------------------------

static uint32_t translate_vaddr(MemoryBus &bus, uint32_t satp, uint32_t vaddr)
{
    if (!(satp & (1u << 31)))
        return vaddr;

    const uint32_t vpn1 = (vaddr >> 22) & 0x3ff;
    const uint32_t vpn0 = (vaddr >> 12) & 0x3ff;
    const uint32_t offset = vaddr & 0xfff;
    const uint32_t root_pa = (satp & 0x3fffff) << 12;

    const uint32_t pgd = bus.read(root_pa + vpn1 * 4, false);
    if (!(pgd & 1u))
        return ~0u;

    // Megapage: R/W/X bits set in level-1 PTE
    if (pgd & 0xeu) {
        const uint32_t ppn = pgd >> 10;
        return (ppn << 12) | (vaddr & 0x3fffffu);
    }

    const uint32_t pte_table_pa = (pgd >> 10) << 12;
    const uint32_t pte = bus.read(pte_table_pa + vpn0 * 4, false);
    if (!(pte & 1u) || !(pte & 0xeu))
        return ~0u;

    return ((pte >> 10) << 12) | offset;
}

// ---------------------------------------------------------------------------
// TraceReplayer — shadow state machine
// ---------------------------------------------------------------------------

class TraceReplayer
{
public:
    explicit TraceReplayer(const std::string &trace_path)
        : bus(0x80000000u, 256u * 1024u * 1024u)
        , regs{}
        , pc(0)
        , satp(0)
        , privilege(RXV::Trace::Privilege_M)
        , tf(trace_path)
        , at_end(false)
        , current_instr(nullptr)
    {
        step();
    }

    // Advance to the next InstructionTrace event.  Returns false at end of trace.
    bool step()
    {
        while (!tf.end_of_trace() || current_range) {
            // If we have a range loaded and events remaining in it, use them
            if (current_range) {
                auto &r = *current_range;
                while (range_idx < r.trace->events()->size()) {
                    unsigned long idx = range_idx++;
                    if ((*r.trace->events_type())[idx] !=
                        RXV::Trace::Event_InstructionTrace)
                        continue;

                    auto *instr = static_cast<const RXV::Trace::InstructionTrace *>(
                        (*r.trace->events())[idx]);

                    apply(instr);
                    current_instr = instr;
                    return true;
                }
                current_range.reset();
            }

            if (tf.end_of_trace())
                break;

            current_range = std::make_unique<TraceRange>(tf.next_range());
            range_idx = 0;
        }

        at_end = true;
        return false;
    }

    bool ended() const { return at_end; }

    uint32_t current_pc() const { return pc; }
    uint32_t reg(unsigned idx) const { return idx < 32 ? regs[idx] : 0; }
    uint32_t current_satp() const { return satp; }
    RXV::Trace::Privilege current_privilege() const { return privilege; }

    // Read len bytes at virtual address vaddr into buf.  Returns false on fault.
    bool read_memory(uint32_t vaddr, size_t len, char *buf)
    {
        const uint32_t paddr = translate_vaddr(bus, satp, vaddr);
        if (paddr == ~0u)
            return false;

        try {
            bus.read(paddr, buf, len, false);
        } catch (...) {
            return false;
        }
        return true;
    }

    const RXV::Trace::InstructionTrace *instr() const { return current_instr; }

private:
    void apply(const RXV::Trace::InstructionTrace *instr)
    {
        bus.write(instr->pc_phys(), instr->instruction(), 0xfu);

        for (auto *ma : *instr->mem_accesses()) {
            auto v = ma->value();
            bus.write(ma->phys(), reinterpret_cast<const char *>(&v), ma->size());
        }

        for (auto *gpr : *instr->gpr_accesses()) {
            if (gpr->id() > 0 && gpr->id() < 32)
                regs[gpr->id()] = gpr->value();
        }

        for (auto *csr : *instr->csr_writes()) {
            if (csr->id() == RXV::Trace::CSRId_SATP)
                satp = csr->value();
        }

        regs[0] = 0;
        pc = instr->pc();
        privilege = instr->privilege();
    }

    TrackingMemoryBus bus;
    std::array<uint32_t, 32> regs;
    uint32_t pc;
    uint32_t satp;
    RXV::Trace::Privilege privilege;
    TraceFile tf;
    bool at_end;

    std::unique_ptr<TraceRange> current_range;
    size_t range_idx = 0;
    const RXV::Trace::InstructionTrace *current_instr;
};

// ---------------------------------------------------------------------------
// GDB RSP packet I/O
// ---------------------------------------------------------------------------

static uint8_t rsp_checksum(std::string_view data)
{
    uint8_t sum = 0;
    for (unsigned char c : data)
        sum += c;
    return sum;
}

static std::string hex8(uint8_t v)
{
    return fmt::format("{:02x}", v);
}

// Encode a 32-bit register value as 8 hex chars, little-endian byte order.
static std::string hex32_le(uint32_t v)
{
    return fmt::format("{:02x}{:02x}{:02x}{:02x}",
                       v & 0xffu,
                       (v >> 8) & 0xffu,
                       (v >> 16) & 0xffu,
                       (v >> 24) & 0xffu);
}

static uint32_t parse_hex32(std::string_view s)
{
    return static_cast<uint32_t>(std::stoul(std::string(s), nullptr, 16));
}

class GdbPacketIO
{
public:
    explicit GdbPacketIO(int fd) : fd(fd) {}

    // Receive one RSP packet; returns nullopt on disconnect.
    std::optional<std::string> recv()
    {
        for (;;) {
            // Drain +/- ACKs and stray bytes until '$'
            for (;;) {
                char c;
                if (!read_byte(c))
                    return std::nullopt;
                if (c == '$')
                    break;
            }

            // Read packet data until '#'
            std::string data;
            for (;;) {
                char c;
                if (!read_byte(c))
                    return std::nullopt;
                if (c == '#')
                    break;
                data += c;
            }

            // Read 2-char checksum
            char cs[2];
            if (!read_byte(cs[0]) || !read_byte(cs[1]))
                return std::nullopt;

            const uint8_t expected = rsp_checksum(data);
            const uint8_t received = static_cast<uint8_t>(
                std::stoul(std::string(cs, 2), nullptr, 16));

            if (received != expected) {
                send_raw("-");
                continue;
            }

            send_raw("+");
            return data;
        }
    }

    void send(std::string_view data)
    {
        const std::string pkt =
            fmt::format("${}#{}", data, hex8(rsp_checksum(data)));
        send_raw(pkt);
    }

    // Returns true if a Ctrl-C interrupt byte (0x03) is waiting on the socket.
    bool has_interrupt()
    {
        struct pollfd pfd{fd, POLLIN, 0};
        if (poll(&pfd, 1, 0) <= 0)
            return false;
        char c;
        if (::recv(fd, &c, 1, MSG_PEEK) != 1)
            return false;
        if (static_cast<unsigned char>(c) == 0x03) {
            ::recv(fd, &c, 1, 0);
            return true;
        }
        return false;
    }

private:
    bool read_byte(char &c)
    {
        return ::read(fd, &c, 1) == 1;
    }

    void send_raw(std::string_view s)
    {
        const char *p = s.data();
        size_t rem = s.size();
        while (rem > 0) {
            ssize_t n = ::write(fd, p, rem);
            if (n <= 0)
                return;
            p += n;
            rem -= n;
        }
    }

    int fd;
};

// ---------------------------------------------------------------------------
// GdbSession — one connected client
// ---------------------------------------------------------------------------

struct Watchpoint {
    uint32_t addr;
    int type; // 1=read, 2=write, 3=access
};

class GdbSession
{
public:
    GdbSession(int fd, const std::string &trace_path)
        : io(fd), replayer(trace_path)
    {
    }

    void run()
    {
        for (;;) {
            auto pkt = io.recv();
            if (!pkt)
                break;

            std::string reply = dispatch(*pkt);
            io.send(reply);

            if (!pkt->empty() && (*pkt)[0] == 'D')
                break;
        }
    }

private:
    std::string dispatch(std::string_view pkt)
    {
        if (pkt.empty())
            return "";

        switch (pkt[0]) {
        case '?':
            return "S05";

        case 'g':
            return read_all_regs();

        case 'G':
            return "E01";

        case 'p':
            return read_reg(pkt.substr(1));

        case 'P':
            return "E01";

        case 'm':
            return read_memory(pkt.substr(1));

        case 'M':
            return "E01";

        case 's':
            return step_one();

        case 'c':
            return run_to_stop();

        case 'Z':
            return set_point(pkt.substr(1), true);

        case 'z':
            return set_point(pkt.substr(1), false);

        case 'H':
        case 'T':
            return "OK";

        case 'D':
            return "OK";

        case 'q':
            return handle_query(pkt.substr(1));

        default:
            return "";
        }
    }

    // g — read all registers: x0..x31 then PC (33 × 8 hex chars)
    std::string read_all_regs()
    {
        std::string out;
        out.reserve(33 * 8);
        for (unsigned i = 0; i < 32; ++i)
            out += hex32_le(replayer.reg(i));
        out += hex32_le(replayer.current_pc());
        return out;
    }

    // p N — read single register
    std::string read_reg(std::string_view arg)
    {
        const unsigned n = static_cast<unsigned>(
            std::stoul(std::string(arg), nullptr, 16));
        if (n < 32)
            return hex32_le(replayer.reg(n));
        if (n == 32)
            return hex32_le(replayer.current_pc());
        return "E01";
    }

    // m addr,len — read memory (virtual addresses)
    std::string read_memory(std::string_view arg)
    {
        const auto comma = arg.find(',');
        if (comma == std::string_view::npos)
            return "E14";

        const uint32_t addr = parse_hex32(arg.substr(0, comma));
        const size_t len = static_cast<size_t>(
            std::stoul(std::string(arg.substr(comma + 1)), nullptr, 16));

        std::vector<char> buf(len);
        if (!replayer.read_memory(addr, len, buf.data()))
            return "E14";

        std::string out;
        out.reserve(len * 2);
        for (size_t i = 0; i < len; ++i)
            out += fmt::format("{:02x}", static_cast<uint8_t>(buf[i]));
        return out;
    }

    // Z/z N,addr,kind — set/clear breakpoints and watchpoints
    std::string set_point(std::string_view arg, bool add)
    {
        const auto c1 = arg.find(',');
        if (c1 == std::string_view::npos)
            return "E01";
        const auto c2 = arg.find(',', c1 + 1);

        const unsigned type = static_cast<unsigned>(
            std::stoul(std::string(arg.substr(0, c1)), nullptr, 10));
        const uint32_t addr = parse_hex32(
            arg.substr(c1 + 1, c2 == std::string_view::npos ? c2 : c2 - c1 - 1));

        if (type == 0) {
            // Software breakpoint — track by PC
            if (add)
                breakpoints.insert(addr);
            else
                breakpoints.erase(addr);
            return "OK";
        }

        // Watchpoints: type 2=write, 3=read, 4=access
        if (type < 2 || type > 4)
            return "";

        const int wp_type = (type == 2) ? 2 : (type == 3) ? 1 : 3;

        if (add) {
            watchpoints.push_back({addr, wp_type});
        } else {
            watchpoints.erase(
                std::remove_if(watchpoints.begin(), watchpoints.end(),
                               [&](const Watchpoint &w) {
                                   return w.addr == addr && w.type == wp_type;
                               }),
                watchpoints.end());
        }
        return "OK";
    }

    std::string handle_query(std::string_view q)
    {
        if (q.starts_with("Supported"))
            return "PacketSize=4096";
        if (q == "Attached")
            return "1";
        return "";
    }

    std::string step_one()
    {
        if (replayer.ended())
            return "S0f";
        if (!replayer.step())
            return "S0f";
        return stop_reply();
    }

    std::string run_to_stop()
    {
        for (;;) {
            if (io.has_interrupt())
                return "S02";

            if (replayer.ended())
                return "S0f";

            if (!replayer.step())
                return "S0f";

            if (breakpoints.count(replayer.current_pc()))
                return "S05";

            if (watchpoint_hit())
                return watchpoint_reply();
        }
    }

    bool watchpoint_hit() const
    {
        if (watchpoints.empty() || !replayer.instr())
            return false;

        for (auto *ma : *replayer.instr()->mem_accesses()) {
            for (const auto &wp : watchpoints) {
                if (ma->addr() != wp.addr)
                    continue;
                const bool is_write = !ma->read();
                const bool is_read = ma->read();
                if (wp.type == 2 && is_write)
                    return true;
                if (wp.type == 1 && is_read)
                    return true;
                if (wp.type == 3)
                    return true;
            }
        }
        return false;
    }

    std::string watchpoint_reply() const
    {
        for (auto *ma : *replayer.instr()->mem_accesses()) {
            for (const auto &wp : watchpoints) {
                if (ma->addr() != wp.addr)
                    continue;
                const bool is_write = !ma->read();
                const bool is_read = ma->read();
                const char *kind = nullptr;
                if (wp.type == 2 && is_write)
                    kind = "watch";
                else if (wp.type == 1 && is_read)
                    kind = "rwatch";
                else if (wp.type == 3)
                    kind = "awatch";
                if (kind)
                    return fmt::format("T05{}:{:08x};", kind, wp.addr);
            }
        }
        return "S05";
    }

    std::string stop_reply()
    {
        if (breakpoints.count(replayer.current_pc()))
            return "S05";
        if (watchpoint_hit())
            return watchpoint_reply();
        return "S05";
    }

    GdbPacketIO io;
    TraceReplayer replayer;
    std::unordered_set<uint32_t> breakpoints;
    std::vector<Watchpoint> watchpoints;
};

// ---------------------------------------------------------------------------
// GdbServer — TCP listener
// ---------------------------------------------------------------------------

class GdbServer
{
public:
    GdbServer(int port, std::string trace_path)
        : port(port), trace_path(std::move(trace_path))
    {
    }

    void start()
    {
        const int srv = socket(AF_INET, SOCK_STREAM, 0);
        if (srv < 0)
            throw std::runtime_error("socket failed");

        const int opt = 1;
        setsockopt(srv, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

        sockaddr_in addr{};
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = INADDR_ANY;
        addr.sin_port = htons(static_cast<uint16_t>(port));

        if (bind(srv, reinterpret_cast<sockaddr *>(&addr), sizeof(addr)) < 0)
            throw std::runtime_error("bind failed");

        if (listen(srv, 1) < 0)
            throw std::runtime_error("listen failed");

        fmt::print("gdb-server listening on port {}\n", port);

        while (true) {
            const int client = accept(srv, nullptr, nullptr);
            if (client < 0)
                continue;

            const std::string path = trace_path;
            std::thread([client, path]() {
                GdbSession session(client, path);
                session.run();
                close(client);
            }).detach();
        }
    }

private:
    int port;
    std::string trace_path;
};

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

int main(int argc, char **argv)
{
    namespace po = boost::program_options;

    po::options_description opts{"Options"};
    // clang-format off
    opts.add_options()
        ("trace", po::value<std::string>(), "Trace file")
        ("port",  po::value<int>()->default_value(1234), "TCP port")
        ("help,h", "Help screen");
    // clang-format on

    po::positional_options_description pos;
    pos.add("trace", 1);

    po::variables_map vm;
    try {
        auto parsed = po::command_line_parser(argc, argv)
                          .options(opts)
                          .positional(pos)
                          .run();
        po::store(parsed, vm);
    } catch (const po::error &e) {
        fmt::print(stderr, "error: {}\n", e.what());
        return 3;
    }

    if (vm.count("help")) {
        std::cout << opts << "\n";
        return 0;
    }

    if (!vm.count("trace")) {
        fmt::print(stderr, "error: trace file required\n");
        return 1;
    }

    GdbServer server(vm["port"].as<int>(), vm["trace"].as<std::string>());
    server.start();
}
