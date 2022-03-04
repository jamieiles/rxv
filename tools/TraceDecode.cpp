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

#include "llvm-c/Disassembler.h"
#include "llvm-c/Target.h"

#include "Trace_generated.h"
#include "TraceFile.h"

static std::string reg_name(int id)
{
    switch (id) {
    case 0: return "zero";
    case 1: return "ra";
    case 2: return "sp";
    case 3: return "gp";
    case 4: return "tp";
    case 5: return "t0";
    case 6: return "t1";
    case 7: return "t2";
    case 8: return "fp";
    case 9: return "s1";
    case 10: return "a0";
    case 11: return "a1";
    case 12: return "a2";
    case 13: return "a3";
    case 14: return "a4";
    case 15: return "a5";
    case 16: return "a6";
    case 17: return "a7";
    case 18: return "s2";
    case 19: return "s3";
    case 20: return "s4";
    case 21: return "s5";
    case 22: return "s6";
    case 23: return "s7";
    case 24: return "s8";
    case 25: return "s9";
    case 26: return "s10";
    case 27: return "s11";
    case 28: return "t3";
    case 29: return "t4";
    case 30: return "t5";
    case 31: return "t6";
    default: throw std::runtime_error("invalid register " + std::to_string(id));
    }
}

static boost::program_options::variables_map parse_options(int argc,
                                                           char *argv[])
{
    boost::program_options::options_description options{"Options"};
    // clang-format off
    options.add_options()
        ("trace_file", boost::program_options::value<std::string>(), "TraceName")
        ("last", boost::program_options::value<unsigned long>()->default_value(0), "Decode last N cycles")
        ("m-elf", boost::program_options::value<std::string>(), "M-mode ELF file")
        ("s-elf", boost::program_options::value<std::string>(), "S-mode ELF file")
        ("u-elf", boost::program_options::value<std::string>(), "U-mode ELF file")
        ("instruction-count", "Count instructions rather than cycles")
        ("help,h", "Help screen");
    // clang-format on

    boost::program_options::positional_options_description positional;
    positional.add("trace_file", 1);

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

static LLVMDisasmContextRef get_disassembler()
{
    LLVMInitializeAllAsmPrinters();
    LLVMInitializeAllTargets();
    LLVMInitializeAllTargetInfos();
    LLVMInitializeAllTargetMCs();
    LLVMInitializeAllDisassemblers();

    LLVMDisasmContextRef dcr = LLVMCreateDisasmCPUFeatures(
        "riscv32-unknown-none", "generic-rv32", "+m,+a", NULL, 0, NULL, NULL);

    if (!dcr)
        errx(1, "failed to create disassembler");

    if (!LLVMSetDisasmOptions(dcr, LLVMDisassembler_Option_PrintImmHex))
        errx(1, "failed to set disassembler options");

    return dcr;
}

static constexpr uint32_t mcause_interrupt = (1U << 31);

enum mcause_type {
    S_SWINT = mcause_interrupt | 1,
    M_SWINT = mcause_interrupt | 3,
    S_TINT = mcause_interrupt | 5,
    M_TINT = mcause_interrupt | 7,
    S_EINT = mcause_interrupt | 9,
    M_EINT = mcause_interrupt | 11,
    INSTR_ALIGN = 0,
    ILLEGAL_INSTRUCTION = 2,
    BREAKPOINT = 3,
    LOAD_MISALIGN = 4,
    STORE_MISALIGN = 6,
    U_ECALL = 8,
    S_ECALL = 9,
    M_ECALL = 11,
    INSTRUCTION_PAGE_FAULT = 12,
    LOAD_PAGE_FAULT = 13,
    STORE_PAGE_FAULT = 15,
};

static std::string decode_mcause(uint32_t v)
{
    if (v == M_SWINT)
        return "M_SWINT";
    if (v == M_TINT)
        return "M_TINT";
    if (v == M_EINT)
        return "M_EINT";
    if (v == S_SWINT)
        return "S_SWINT";
    if (v == S_TINT)
        return "S_TINT";
    if (v == S_EINT)
        return "S_EINT";
    if (v == INSTR_ALIGN)
        return "INSTR_ALIGN";
    if (v == ILLEGAL_INSTRUCTION)
        return "ILLEGAL_INSTRUCTION";
    if (v == BREAKPOINT)
        return "BREAKPOINT";
    if (v == LOAD_MISALIGN)
        return "LOAD_MISALIGN";
    if (v == STORE_MISALIGN)
        return "STORE_MISALIGN";
    if (v == M_ECALL)
        return "M_ECALL";
    if (v == S_ECALL)
        return "S_ECALL";
    if (v == U_ECALL)
        return "U_ECALL";
    if (v == INSTRUCTION_PAGE_FAULT)
        return "INSTRUCTION_PAGE_FAULT";
    if (v == LOAD_PAGE_FAULT)
        return "LOAD_PAGE_FAULT";
    if (v == STORE_PAGE_FAULT)
        return "STORE_PAGE_FAULT";

    return "UNKNOWN";
}

struct Symbol {
    std::string name;
    uint32_t start;
    uint32_t end;
};

static std::map<RXV::Trace::Privilege, std::vector<Symbol>> symbols;

static bool symbol_compare(const Symbol &a, const Symbol &b)
{
    return a.start < b.start;
}

static std::string lookup_pc_symbol(RXV::Trace::Privilege level, uint32_t addr)
{
    auto s = std::find_if(symbols[level].rbegin(), symbols[level].rend(),
                          [&](const Symbol &s) { return addr >= s.start; });

    if (s == symbols[level].rend())
        return "";

    return fmt::format("{:s}+0x{:x}", s->name, addr - s->start);
}

static bool is_interesting_symbol(const std::string &name, unsigned char type)
{
    if (name.size() == 0)
        return false;

    if (!(type == ELFIO::STT_OBJECT || type == ELFIO::STT_FUNC ||
          type == ELFIO::STT_NOTYPE))
        return false;

    return true;
}

static void load_symbols(RXV::Trace::Privilege level,
                         const std::string &filename)
{
    ELFIO::elfio reader;

    reader.load(filename);

    ELFIO::Elf_Half sec_num = reader.sections.size();
    for (int i = 0; i < sec_num; ++i) {
        auto psec = reader.sections[i];
        if (psec->get_type() != ELFIO::SHT_SYMTAB)
            continue;

        const ELFIO::symbol_section_accessor symtab(reader, psec);
        for (unsigned int j = 0; j < symtab.get_symbols_num(); ++j) {
            std::string name;
            ELFIO::Elf64_Addr value;
            ELFIO::Elf_Xword size;
            unsigned char bind;
            unsigned char type;
            ELFIO::Elf_Half section_index;
            unsigned char other;
            if (!symtab.get_symbol(j, name, value, size, bind, type,
                                   section_index, other))
                continue;

            if (!is_interesting_symbol(name, type))
                continue;

            symbols[level].emplace_back(
                Symbol{name, static_cast<uint32_t>(value),
                       static_cast<uint32_t>(value + size - 1)});
        }
    }

    std::sort(symbols[level].begin(), symbols[level].end(), symbol_compare);
}

static void dump_instruction(const LLVMDisasmContextRef &dcr,
                             int id,
                             const RXV::Trace::InstructionTrace *instr)
{
    union {
        uint32_t instr;
        uint8_t bytes[4];
    } converter;
    converter.instr = instr->instruction();

    char instr_string[128] = " invalid";
    LLVMDisasmInstruction(dcr, converter.bytes, sizeof(converter), 0,
                          instr_string, sizeof(instr_string) - 1);

    while (strchr(instr_string, '\t'))
        *strchr(instr_string, '\t') = ' ';

    std::string notes;
    std::string symbol = lookup_pc_symbol(instr->privilege(), instr->pc());

    if (instr->exception_raised())
        notes += " /EXCEPTION";

    fmt::print("@ {:<10d} {:s} {:08x} {:32s} # [instr: {:08x}] {:s}{:s}\n", id,
               EnumNamePrivilege(instr->privilege()), instr->pc(), instr_string,
               converter.instr, symbol, notes);
    for (auto reg : *instr->gpr_accesses()) {
        if (reg->id() == 0)
            continue;
        fmt::print("{:25s}{:<3s} {:s} {:08x}\n", "", reg_name(reg->id()),
                   reg->read() ? "==" : ":=", reg->value());
    }
    for (auto csr : *instr->csr_writes()) {
        std::string decoding = "";
        if (csr->id() == RXV::Trace::CSRId_MCAUSE ||
            csr->id() == RXV::Trace::CSRId_SCAUSE)
            decoding = decode_mcause(csr->value());
        fmt::print("{:25s}{:<10s} {:08x} {:s}\n", "", EnumNameCSRId(csr->id()),
                   csr->value(), decoding);
    }
    for (auto mem : *instr->mem_accesses()) {
        fmt::print(
            "{:25s}{:c}{:<2d} M[{:08x}] {:s} {:08x}     # [v2p({:08x}) == "
            "{:08x}]\n",
            "", mem->read() ? 'R' : 'W', mem->size() * 8, mem->addr(),
            mem->read() ? "==" : ":=", mem->value(), mem->addr(), mem->phys());
    }
}

static void dump_interrupt(const RXV::Trace::InterruptTrace *irq)
{
    fmt::print("@ {:<10d} INTERRUPT target {:s}\n", irq->cycle_num(),
               EnumNamePrivilege(irq->target_level()));
    for (auto csr : *irq->csr_writes()) {
        std::string decoding = "";
        if (csr->id() == RXV::Trace::CSRId_MCAUSE ||
            csr->id() == RXV::Trace::CSRId_SCAUSE)
            decoding = decode_mcause(csr->value());
        fmt::print("{:25s}{:<10s} {:08x} {:s}\n", "", EnumNameCSRId(csr->id()),
                   csr->value(), decoding);
    }
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

    if (vm.count("m-elf"))
        load_symbols(RXV::Trace::Privilege::Privilege_M,
                     vm["m-elf"].as<std::string>());
    if (vm.count("s-elf"))
        load_symbols(RXV::Trace::Privilege::Privilege_S,
                     vm["s-elf"].as<std::string>());
    if (vm.count("u-elf"))
        load_symbols(RXV::Trace::Privilege::Privilege_U,
                     vm["u-elf"].as<std::string>());
    if (vm.count("trace_file") != 1) {
        std::cerr << "ERROR: no trace file" << std::endl;
        exit(1);
    }

    auto dcr = get_disassembler();
    TraceFile tf(vm["trace_file"].as<std::string>());

    unsigned long start = 0;
    auto last = vm["last"].as<unsigned long>();
    auto num_events = tf.num_events();
    bool count_instructions = vm.count("instruction-count");
    if (last != 0) {
        if (last < num_events)
            start = num_events - last;
    }
    auto trace_range = tf.range_containing_event(start);

    for (;;) {
        auto range_start = trace_range.event_offset;
        auto range_end = range_start + trace_range.trace->events()->size() - 1;

        for (unsigned long i = start > range_end ? 0 : start - range_start;
             i <= range_end - range_start; ++i) {
            if ((*trace_range.trace->events_type())[i] ==
                RXV::Trace::Event_InstructionTrace) {
                auto instr = static_cast<const RXV::Trace::InstructionTrace *>(
                    (*trace_range.trace->events())[i]);

                int id = count_instructions ? i : instr->cycle_num();
                dump_instruction(dcr, id, instr);
            } else if ((*trace_range.trace->events_type())[i] ==
                       RXV::Trace::Event_InterruptTrace) {
                auto irq = static_cast<const RXV::Trace::InterruptTrace *>(
                    (*trace_range.trace->events())[i]);

                dump_interrupt(irq);
            }
        }

        if (tf.end_of_trace())
            break;
        trace_range = tf.next_range();
    }

    return 0;
}
