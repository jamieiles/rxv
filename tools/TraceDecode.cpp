#include <err.h>
#include <stdint.h>
#include <iostream>
#include <fstream>
#include <fmt/core.h>
#include <cstring>

#include <boost/program_options.hpp>

#include <elfio/elfio.hpp>

#include "llvm-c/Disassembler.h"
#include "llvm-c/Target.h"

#include "Trace_generated.h"

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
    case 20: return "s3";
    case 19: return "s4";
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
        ("elf", boost::program_options::value<std::string>(), "ELF file")
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

static const RXV::Trace::ProcessorTrace *get_trace(const std::string &filename)
{
    std::ifstream insn_trace_file;
    insn_trace_file.open(filename, std::ios::in | std::ios::binary);
    insn_trace_file.seekg(0, std::ios::end);
    int length = insn_trace_file.tellg();
    insn_trace_file.seekg(0, std::ios::beg);
    char *data = new char[length];
    insn_trace_file.read(data, length);
    insn_trace_file.close();

    return RXV::Trace::GetProcessorTrace(data);
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
    M_SWINT = mcause_interrupt | 3,
    M_TINT = mcause_interrupt | 7,
    M_EINT = mcause_interrupt | 11,
    INSTR_ALIGN = 0,
    ILLEGAL_INSTRUCTION = 2,
    BREAKPOINT = 3,
    LOAD_MISALIGN = 4,
    STORE_MISALIGN = 6,
    M_ECALL = 11
};

static std::string decode_mcause(uint32_t v)
{
    if (v == M_SWINT)
        return "M_SWINT";
    if (v == M_TINT)
        return "M_TINT";
    if (v == M_EINT)
        return "M_EINT";
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

    return "UNKNOWN";
}

struct Symbol {
    std::string name;
    uint32_t start;
    uint32_t end;
};

static std::vector<Symbol> symbols;

static bool symbol_compare(const Symbol &a, const Symbol &b)
{
    return a.start < b.start;
}

static std::string lookup_pc_symbol(uint32_t addr)
{
    auto s = std::find_if(symbols.rbegin(), symbols.rend(),
                          [&](const Symbol &s) { return addr >= s.start; });

    if (s == symbols.rend())
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

static void load_symbols(const std::string &filename)
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
            symtab.get_symbol(j, name, value, size, bind, type, section_index,
                              other);

            if (!is_interesting_symbol(name, type))
                continue;

            symbols.emplace_back(
                Symbol{name, static_cast<uint32_t>(value),
                       static_cast<uint32_t>(value + size - 1)});
        }
    }

    std::sort(symbols.begin(), symbols.end(), symbol_compare);
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

    if (vm.count("elf"))
        load_symbols(vm["elf"].as<std::string>());

    auto dcr = get_disassembler();
    auto proc_trace = get_trace(vm["trace_file"].as<std::string>());

    for (auto instr : *proc_trace->instructions()) {
        union {
            uint32_t instr;
            uint8_t bytes[4];
        } converter;
        converter.instr = instr->instruction();

        char instr_string[128];
        LLVMDisasmInstruction(dcr, converter.bytes, sizeof(converter), 0,
                              instr_string, sizeof(instr_string) - 1);

        while (strchr(instr_string, '\t'))
            *strchr(instr_string, '\t') = ' ';

        std::string notes;
        std::string symbol = lookup_pc_symbol(instr->pc());

        if (instr->exception_raised())
            notes += " /EXCEPTION";

        std::cout << fmt::format(
            "@ {:<10d} {:08x} {:32s} # [instr: {:08x}] {:s}{:s}\n",
            instr->cycle_num(), instr->pc(), instr_string, converter.instr,
            symbol, notes);
        for (auto reg : *instr->gpr_accesses()) {
            if (reg->id() == 0)
                continue;
            std::cout << fmt::format("{:23s}{:<3s} {:s} {:08x}\n", "",
                                     reg_name(reg->id()),
                                     reg->read() ? "==" : ":=", reg->value());
        }
        for (auto csr : *instr->csr_writes()) {
            std::string decoding = "";
            if (csr->id() == RXV::Trace::CSRId_MCAUSE)
                decoding = decode_mcause(csr->value());
            std::cout << fmt::format("{:23s}{:<10s} {:08x} {:s}\n", "",
                                     EnumNameCSRId(csr->id()), csr->value(),
                                     decoding);
        }
        for (auto mem : *instr->mem_accesses()) {
            std::cout << fmt::format("{:23s}{:c}{:d} M[{:08x}] {:s} {:08x}\n",
                                     "", mem->read() ? 'R' : 'W',
                                     mem->size() * 8, mem->addr(),
                                     mem->read() ? "==" : ":=", mem->value());
        }
    }

    return 0;
}
