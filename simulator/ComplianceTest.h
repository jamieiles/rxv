#pragma once
#include <iostream>
#include <iomanip>
#include <string>
#include <vector>
#include <map>

#include <boost/io/ios_state.hpp>

#include "RXVSim.h"
#include "RXVCore.h"

static constexpr int timeout = 100000;

class ComplianceTest
{
public:
    explicit ComplianceTest(std::unique_ptr<SimulatorBase> sim,
                            const std::string &filename)
        : sim(std::move(sim)), elf(filename), test_status(RUNNING)
    {
        this->sim->load_elf(elf);

        load_io_writes();
        load_gpr_assertions();
        to_host_addr = elf.sym_addr("tohost");
    }

    virtual ~ComplianceTest()
    {
    }

    bool run()
    {
        for (int i = 0; i < timeout; ++i) {
            check_for_completion();
            handle_io();
            check_assertions();

            if (test_status != RUNNING)
                break;
            sim->step();

            if (i == timeout - 1)
                std::cerr << "Test timeout" << std::endl;
        }

        output_signature();

        auto stats = sim->get_perf_stats();
        std::cerr << std::dec << std::setprecision(2) << "  " << stats.retired
                  << " instructions in " << stats.cycles << " cycles ("
                  << static_cast<double>(stats.retired) / stats.cycles
                  << " instructions per cycle)" << std::endl;

        return test_status == PASSED ? true : false;
    }

private:
    enum { RUNNING, PASSED, FAILED } test_status;

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

    void handle_io()
    {
        auto pc = sim->get_pc();

        if (io_writes.find(pc) == io_writes.end())
            return;

        std::cerr << io_writes.at(pc);
        std::cerr.flush();
    }

    void check_for_completion()
    {
        auto to_host = sim->template read_phys_mem<uint32_t>(to_host_addr);
        if (to_host != 0)
            test_status = to_host == 1 ? PASSED : FAILED;
    }

    void check_assertions()
    {
        auto pc = sim->get_pc();
        if (gpr_assertions.find(pc) == gpr_assertions.end())
            return;

        auto assertion = gpr_assertions.at(pc);
        if (sim->read_reg(assertion.regnum) != assertion.expected) {
            std::cerr << "ASSERTION FAILED AT " << std::hex
                      << assertion.location << ": x" << std::dec
                      << assertion.regnum << " != " << std::hex
                      << assertion.expected << ", got "
                      << sim->read_reg(assertion.regnum) << std::endl;
            test_status = FAILED;
        } else {
            std::cerr << "ASSERTION PASSED AT " << std::hex
                      << assertion.location << ": x" << std::dec
                      << assertion.regnum << " == " << std::hex
                      << assertion.expected << std::endl;
        }
    }

    void output_signature()
    {
        uint32_t begin_signature, end_signature;

        try {
            begin_signature = elf.sym_addr("begin_signature");
            end_signature = elf.sym_addr("end_signature");
        } catch (std::out_of_range &) {
            return;
        }

        auto signature = sim->template read_phys_mem_vector<uint32_t>(
            begin_signature, (end_signature - begin_signature) / 4);

        boost::io::ios_flags_saver ifs(std::cout);
        std::cout << std::setfill('0') << std::setw(8);
        for (auto &v : signature)
            std::cout << std::setfill('0') << std::setw(8) << std::hex << v
                      << "\n";
        std::cout.flush();
    }

    void load_io_writes()
    {
        auto iow = elf.read_section<IOWrite>(".rvtest_io_write");
        for (auto &i : iow)
            io_writes[i.instr_addr] = sim->read_phys_string(i.string_addr);
    }

    void load_gpr_assertions()
    {
        auto assertions =
            elf.read_section<ELFGPRAssertion>(".rvtest_gpr_assert");
        for (auto &a : assertions) {
            auto name = sim->read_phys_string(a.regname_addr);
            auto location = sim->read_phys_string(a.location_addr);
            auto regnum = static_cast<uint32_t>(std::stoi(name.substr(1)));

            gpr_assertions[a.instr_addr] = {regnum, a.expected, location};
        }
    }

    std::map<uint32_t, std::string> io_writes;
    std::map<uint32_t, GPRAssertion> gpr_assertions;

    RiscVELF elf;
    std::unique_ptr<SimulatorBase> sim;
    uint32_t to_host_addr;
};
