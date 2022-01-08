#include <err.h>
#include <stdint.h>
#include <iostream>
#include <fstream>
#include <fmt/core.h>
#include <cstring>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <sys/stat.h>

#include <boost/program_options.hpp>
#include <elfio/elfio.hpp>

#include "Trace_generated.h"
#include "MemoryDevice.h"

#define NT_PRSTATUS 1

struct elf_siginfo {
    int32_t si_signo;
    int32_t si_code;
    int32_t si_errno;
};

struct timeval32 {
    uint32_t tv_sec;
    uint32_t tv_usec;
};

struct rv32_pt_regs {
    uint32_t pc;
    uint32_t gpregs[31];
};

struct riscv_prstatus {
    struct elf_siginfo pr_info;
    uint32_t pr_cursig;
    uint32_t pr_sigpend;
    uint32_t pr_sighold;
    uint32_t pr_pid;
    uint32_t pr_ppid;
    uint32_t pr_pgrp;
    uint32_t pr_sid;
    struct timeval32 pr_utime;
    struct timeval32 pr_stime;
    struct timeval32 pr_cutime;
    struct timeval32 pr_cstime;
    struct rv32_pt_regs pr_reg;
    int pr_fpvalid;
};

class TrackingMemoryBus : public MemoryBus
{
public:
    TrackingMemoryBus(uint32_t ram_base, size_t ram_size)
        : MemoryBus(ram_base, ram_size), ram_base(ram_base), ram_size(ram_size)
    {
        auto num_pages = ram_size / 4096;
        accessed.reserve(num_pages);
    }

    virtual void read(uint32_t addr, char *dst, size_t len) override
    {
        mark_accessed(addr);
        MemoryBus::read(addr, dst, len);
    }

    virtual void write(uint32_t addr, const char *val, size_t len) override
    {
        mark_accessed(addr);
        MemoryBus::write(addr, val, len);
    }

    virtual void write(uint32_t addr, uint32_t val, uint8_t wstb) override
    {
        mark_accessed(addr);
        MemoryBus::write(addr, val, wstb);
    }

    virtual uint32_t read(uint32_t addr) override
    {
        mark_accessed(addr);
        return MemoryBus::read(addr);
    }

    bool page_accessed(uint32_t addr)
    {
        auto pfn = (addr - ram_base) >> 12;

        if (addr < ram_base || addr >= ram_base + ram_size)
            return false;

        return accessed[pfn];
    }

private:
    void mark_accessed(uint32_t addr)
    {
        if (addr < ram_base || addr >= ram_base + ram_size)
            return;

        auto pfn = (addr - ram_base) >> 12;
        accessed[pfn] = 1;
    }
    std::vector<bool> accessed;
    uint32_t ram_base;
    size_t ram_size;
};

class SV32WalkerBase
{
public:
    SV32WalkerBase(TrackingMemoryBus *bus, uint32_t satp) : bus(bus), satp(satp)
    {
    }

    void walk_phys()
    {
        for (uint64_t addr = 0; addr != 0x100000000; addr += 4096)
            if (bus->page_accessed(addr))
                visit_page(addr, addr, true, true);
    }

    void walk_virt()
    {
        if (!(satp & (0x1 << 31))) {
            walk_phys();
            return;
        }

        const int entries_per_table = 1 << 10;
        uint32_t base = (satp & 0x3fffff) << 12;

        assert(bus->page_accessed(base));

        for (int i = 0; i < entries_per_table; ++i) {
            uint32_t pgd = bus->read(base + i * sizeof(uint32_t));
            if (!(pgd & pte_valid))
                continue;

            if (pgd & (pte_exec | pte_write | pte_read))
                visit_megapage((pgd & 0xfff00000) << 2, i << 22, pgd & pte_exec,
                               pgd & pte_write);
            else
                walk_ptes((pgd << 2) & 0xfffff000, i);
        }
    }

    virtual void visit_page(uint32_t phys,
                            uint32_t virt,
                            bool exec,
                            bool writable) = 0;

    virtual void visit_megapage(uint32_t phys,
                                uint32_t virt,
                                bool exec,
                                bool writable) = 0;

private:
    static constexpr int sv32_levels = 2;
    static constexpr int sv32_page_offset_bits = 12;
    static constexpr int sv32_vpn_bits = 10;
    static constexpr uint32_t sv32_page_mask = (1 << sv32_page_offset_bits) - 1;
    static constexpr uint32_t sv32_megapage_mask =
        (1 << (sv32_page_offset_bits + sv32_vpn_bits)) - 1;
    static constexpr uint32_t pte_valid = (1 << 0);
    static constexpr uint32_t pte_read = (1 << 1);
    static constexpr uint32_t pte_write = (1 << 2);
    static constexpr uint32_t pte_exec = (1 << 3);
    static constexpr uint32_t pte_user = (1 << 4);
    static constexpr uint32_t pte_global = (1 << 5);
    static constexpr uint32_t pte_accessed = (1 << 6);
    static constexpr uint32_t pte_dirty = (1 << 7);

    void walk_ptes(uint32_t base, uint32_t vpn1)
    {
        const int entries_per_table = 1 << 10;
        if (!bus->page_accessed(base))
            return;

        for (int i = 0; i < entries_per_table; ++i) {
            uint32_t pte = bus->read(base + i * sizeof(uint32_t));
            if (!(pte & pte_valid))
                continue;

            if (!(pte & (pte_exec | pte_write | pte_read)))
                continue;

            uint32_t phys = (pte & sv32_page_mask) << 2;
            uint32_t virt = (vpn1 << 22) | (i << 12);
            visit_page(phys, virt, pte & pte_exec, pte & pte_write);
        }
    }
    TrackingMemoryBus *bus;
    uint32_t satp;
};

class SV32Dumper : public SV32WalkerBase
{
public:
    SV32Dumper(TrackingMemoryBus *bus, uint32_t satp, ELFIO::elfio *writer)
        : SV32WalkerBase(bus, satp), writer(writer), bus(bus)
    {
    }

    virtual void visit_page(uint32_t phys,
                            uint32_t virt,
                            bool exec,
                            bool writable)
    {
        write(phys, virt, exec, writable, 4 * 1024);
    }

    virtual void visit_megapage(uint32_t phys,
                                uint32_t virt,
                                bool exec,
                                bool writable)
    {
        for (uint32_t offs = 0; offs < 4 * 1024 * 1024; offs += 4096)
            write(phys + offs, virt + offs, exec, writable, 4 * 1024);
    }

private:
    void write(uint32_t phys,
               uint32_t virt,
               bool exec,
               bool writable,
               size_t len)
    {
        if (!bus->page_accessed(phys))
            return;

        auto *section = writer->sections.add(".text." + std::to_string(virt));
        section->set_type(ELFIO::SHT_PROGBITS);
        section->set_flags(ELFIO::SHF_ALLOC | ELFIO::SHF_EXECINSTR);
        section->set_addr_align(len);

        char page_buf[len];
        for (int i = 0; i < len; ++i)
            bus->read(phys + i, &page_buf[i], 1);
        section->set_data(page_buf, sizeof(page_buf));

        auto *seg = writer->segments.add();
        seg->set_type(ELFIO::PT_LOAD);
        seg->set_virtual_address(virt);
        seg->set_physical_address(phys);
        seg->set_flags(ELFIO::PF_X | ELFIO::PF_R);
        seg->set_align(len);

        seg->add_section_index(section->get_index(), section->get_addr_align());
    }

    ELFIO::elfio *writer;
    TrackingMemoryBus *bus;
};

static const RXV::Trace::ProcessorTrace *get_trace(const std::string &filename)
{
    auto fd = open(filename.c_str(), O_RDONLY);
    if (fd < 0)
        err(1, "failed to open %s trace", filename.c_str());
    struct stat statbuf = {};
    if (fstat(fd, &statbuf))
        err(1, "failed to stat %s", filename.c_str());
    auto pad_size =
        ((statbuf.st_size + getpagesize() - 1) / getpagesize()) * getpagesize();
    void *buf = mmap(NULL, pad_size, PROT_READ, MAP_PRIVATE, fd, 0);
    if (buf == MAP_FAILED)
        err(1, "failed to map trace file");

    return RXV::Trace::GetProcessorTrace(buf);
}

class CoreFileGenerator
{
public:
    CoreFileGenerator(const std::string &trace_file,
                      const std::string output_file,
                      uint64_t until)
        : trace_file(trace_file)
        , output_file(output_file)
        , prstatus()
        , bus(0x80000000, 256 * 1024 * 1024)
        , satp(0)
        , mode(RXV::Trace::Privilege_M)
        , until(until)
    {
    }

    void run()
    {
        run_trace();
        write_core();
    }

private:
    void run_trace()
    {
        auto proc_trace = get_trace(trace_file);

        auto num_instructions = proc_trace->instructions()->size();
        for (unsigned long idx = 0; idx < num_instructions; ++idx) {
            auto instr = (*proc_trace->instructions())[idx];

            prstatus.pr_reg.pc = instr->pc();
            if (until && instr->cycle_num() >= until)
                break;
            mode = instr->privilege();

            bus.write(instr->pc_phys(), instr->instruction(), 0xf);

            for (auto mem : *instr->mem_accesses()) {
                auto v = mem->value();
                bus.write(mem->phys(), reinterpret_cast<const char *>(&v),
                          mem->size());
            }
            for (auto gpr : *instr->gpr_accesses()) {
                auto v = gpr->value();
                prstatus.pr_reg.gpregs[gpr->id() - 1] = v;
            }
            for (auto csr : *instr->csr_writes()) {
                if (csr->id() == RXV::Trace::CSRId_SATP)
                    satp = csr->value();
            }
        }
    }

    void write_core()
    {
        ELFIO::elfio writer;

        writer.create(ELFIO::ELFCLASS32, ELFIO::ELFDATA2LSB);
        writer.set_os_abi(ELFIO::ELFOSABI_LINUX);
        writer.set_type(ELFIO::ET_CORE);
        writer.set_machine(ELFIO::EM_RISCV);

        SV32Dumper dumper(&bus, satp, &writer);
        if (mode == RXV::Trace::Privilege_M)
            dumper.walk_phys();
        else
            dumper.walk_virt();

        auto *note_sec = writer.sections.add(".note");
        note_sec->set_type(ELFIO::SHT_NOTE);
        note_sec->set_addr_align(1);

        ELFIO::note_section_accessor note_writer(writer, note_sec);
        note_writer.add_note(NT_PRSTATUS, "CORE", &prstatus, sizeof(prstatus));

        auto *note_seg = writer.segments.add();
        note_seg->set_type(ELFIO::PT_NOTE);
        note_seg->set_flags(ELFIO::PF_R);
        note_seg->set_align(1);
        note_seg->add_section_index(note_sec->get_index(),
                                    note_sec->get_addr_align());

        writer.save(output_file);
    }

    std::string trace_file;
    std::string output_file;
    riscv_prstatus prstatus;
    TrackingMemoryBus bus;
    uint32_t satp;
    RXV::Trace::Privilege mode;
    uint64_t until;
};

static boost::program_options::variables_map parse_options(int argc,
                                                           char *argv[])
{
    boost::program_options::options_description options{"Options"};
    // clang-format off
    options.add_options()
        ("trace_file", boost::program_options::value<std::string>(), "TraceName")
        ("output", boost::program_options::value<std::string>(), "Output")
        ("until", boost::program_options::value<uint64_t>()->default_value(0), "Stop before Cycle")
        ("help,h", "Help screen");
    // clang-format on

    boost::program_options::positional_options_description positional;
    positional.add("trace_file", 1);
    positional.add("output", 1);

    boost::program_options::command_line_parser parser{argc, argv};
    parser.options(options).positional(positional).allow_unregistered();
    boost::program_options::parsed_options parsed_options = parser.run();

    boost::program_options::variables_map vm;
    boost::program_options::store(parsed_options, vm);

    if (vm.count("help")) {
        std::cout << options << std::endl;
        exit(0);
    }

    return vm;
}

int main(int argc, char **argv)
{
    boost::program_options::variables_map vm;

    try {
        vm = parse_options(argc, argv);
    } catch (boost::program_options::error &e) {
        std::cerr << e.what() << std::endl;
        exit(3);
    }

    if (vm.count("trace_file") != 1) {
        std::cerr << "ERROR: no trace file" << std::endl;
        exit(1);
    }
    if (vm.count("output") != 1) {
        std::cerr << "ERROR: no output file" << std::endl;
        exit(1);
    }

    CoreFileGenerator core(vm["trace_file"].as<std::string>(),
                           vm["output"].as<std::string>(),
                           vm["until"].as<uint64_t>());
    core.run();

    return 0;
}
