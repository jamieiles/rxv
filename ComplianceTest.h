#pragma once
#include <iostream>
#include <iomanip>
#include <string>
#include <vector>
#include <map>

#include <boost/io/ios_state.hpp>

#include "RXVSim.h"

class ComplianceTest
{
public:
    explicit ComplianceTest(const std::string &filename)
	    : elf(filename), sim(128 * 1024, 0x80000000)
    {
        sim.load_elf(elf);
        load_io_writes();
        load_gpr_assertions();
    }

    void run()
    {
        for (int i = 0; i < 100000; ++i) {
            auto pc = sim.get_pc();

            if (sim.read_mem<uint32_t>(pc) == 0xc0001073)
                break;

            if (io_writes.find(pc) != io_writes.end()) {
                std::cerr << io_writes.at(pc);
                std::cerr.flush();
            }

            if (gpr_assertions.find(pc) != gpr_assertions.end()) {
                auto assertion = gpr_assertions.at(pc);
                if (sim.read_reg(assertion.regnum) != assertion.expected) {
                    std::cerr << "ASSERTION FAILED AT " << std::hex
                              << assertion.location << ": x" << std::dec
                              << assertion.regnum << " != " << std::hex
                              << assertion.expected << ", got "
                              << sim.read_reg(assertion.regnum) << std::endl;
                    abort();
                } else {
                    std::cerr << "ASSERTION PASSED AT " << std::hex
                              << assertion.location << ": x" << std::dec
                              << assertion.regnum << " == " << std::hex
                              << assertion.expected << std::endl;
                }
            }

            sim.step();
        }

        output_signature();
    }

    void output_signature() const
    {
        auto begin_signature = elf.sym_addr("begin_signature");
        auto end_signature = elf.sym_addr("end_signature");
        auto signature = sim.read_mem<uint32_t>(
            begin_signature, (end_signature - begin_signature) / 4);

        boost::io::ios_flags_saver ifs(std::cout);
        std::cout << std::setfill('0') << std::setw(8);
        for (auto &v : signature)
            std::cout << std::setfill('0') << std::setw(8) << std::hex << v
                      << "\n";
        std::cout.flush();
    }

private:
    struct IOWrite {
        uint32_t instr_addr;
        uint32_t string_addr;
    };

    struct ELFGPRAssertion {
        uint32_t instr_addr;
        uint32_t regname_addr;
        uint32_t expected;
        uint32_t location_addr;
    };

    struct GPRAssertion {
        uint32_t regnum;
        uint32_t expected;
        std::string location;
    };

    void load_io_writes()
    {
        auto iow = elf.read_section<IOWrite>(".rvtest_io_write");
        for (auto &i : iow)
            io_writes[i.instr_addr] = sim.read_string(i.string_addr);
    }

    void load_gpr_assertions()
    {
        auto assertions =
            elf.read_section<ELFGPRAssertion>(".rvtest_gpr_assert");
        for (auto &a : assertions) {
            auto name = sim.read_string(a.regname_addr);
            auto location = sim.read_string(a.location_addr);
            auto regnum = static_cast<uint32_t>(std::stoi(name.substr(1)));

            gpr_assertions[a.instr_addr] = {regnum, a.expected, location};
        }
    }

    std::map<uint32_t, std::string> io_writes;
    std::map<uint32_t, GPRAssertion> gpr_assertions;

    RiscVELF elf;
    RXVSim sim;
};
