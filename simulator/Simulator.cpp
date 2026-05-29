// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
#include <iostream>
#include <memory>
#include <string>
#include <boost/program_options.hpp>
#include <signal.h>
#include <chrono>

#include "ComplianceTest.h"
#include "boost/algorithm/string.hpp"

static bool sigint_received;

static void sigint_handler(int signum)
{
    (void)signum;

    sigint_received = true;
}

#include <fmt/core.h>

static std::string human_freq(double hz)
{
    if (hz < 1000)
        return fmt::format("{0:0.2f}Hz", hz);
    if (hz < 1000000)
        return fmt::format("{0:0.2f}KHz", hz / 1000);
    if (hz < 1000000000)
        return fmt::format("{0:0.2f}MHz", hz / 1000000);
    return fmt::format("{0:0.2f}GHz", hz / 1000000000);
}

class Simulation
{
public:
    explicit Simulation(std::unique_ptr<SimulatorBase> sim,
                        const std::string &filename)
        : sim(std::move(sim))
    {
        RiscVELF elf(filename);

        this->sim->load_elf(elf);
    }

    void run()
    {
        signal(SIGINT, sigint_handler);
        signal(SIGQUIT, sigint_handler);

        auto start = std::chrono::steady_clock::now();
        try {
            while (!sigint_received && sim->step())
                continue;
        } catch (std::exception &e) {
            std::cerr << "\r\nERROR: " << e.what() << "\r\n" << std::endl;
        }
        auto end = std::chrono::steady_clock::now();
        std::chrono::duration<double> duration = end - start;

        fmt::print("[simulation finished]\n\r");
        auto stats = sim->get_perf_stats();
        // clang-format off
        fmt::print(
            "{0:d} instructions in {1:d} cycles, {2:d} seconds ({3:0.2f} instructions per cycle)\n\r",
            stats.retired, stats.cycles, std::chrono::duration_cast<std::chrono::seconds>(duration).count(),
            static_cast<double>(stats.retired) / stats.cycles);
        report_extended_perf_stats(stats);
        fmt::print("{0:d} IRQs\n\r", stats.num_irqs);
        fmt::print("Simulation speed {0:s}\r\n",
                   human_freq(stats.cycles / std::chrono::duration_cast<std::chrono::seconds>(duration).count()));
        // clang-format on
    }

private:
    void report_extended_perf_stats(const SimPerfStats &stats)
    {
        if (!stats.branch)
            return;

        report_one_perf_stat("BRANCH", stats.branch);
        report_one_perf_stat("BRANCH_MISPRED", stats.branch_mispred);
        report_one_perf_stat("FE_STALL", stats.fe_stall);
        report_one_perf_stat("BE_STALL", stats.be_stall);
        report_one_perf_stat("L1D_READ", stats.l1d_read);
        report_one_perf_stat("L1D_READ_MISS", stats.l1d_read_miss);
        report_one_perf_stat("L1D_WRITE", stats.l1d_write);
        report_one_perf_stat("L1D_WRITE_MISS", stats.l1d_write_miss);
        report_one_perf_stat("L1I_READ", stats.l1i_read);
        report_one_perf_stat("L1I_READ_MISS", stats.l1i_read_miss);
        report_one_perf_stat("DTLB_READ", stats.dtlb_read);
        report_one_perf_stat("DTLB_READ_MISS", stats.dtlb_read_miss);
        report_one_perf_stat("ITLB_READ", stats.itlb_read);
        report_one_perf_stat("ITLB_READ_MISS", stats.itlb_read_mis);
    }

    void report_one_perf_stat(const std::string &name, uint64_t v)
    {
        fmt::print("{0:20s} {1:d}\r\n", name, v);
    }

    std::unique_ptr<SimulatorBase> sim;
};

static boost::program_options::variables_map parse_options(int argc,
                                                           char *argv[])
{
    boost::program_options::options_description options{"Options"};
    // clang-format off
    options.add_options()
        ("elf", boost::program_options::value<std::string>(), "ELF file")
        ("binary", boost::program_options::value<std::vector<std::string>>()->multitoken(), "Extra binary file(s)")
        ("sim", boost::program_options::value<std::string>(), "Simulator")
        ("waves", boost::program_options::value<std::string>(), "Waves File")
        ("trace_file", boost::program_options::value<std::string>(), "TraceName")
        ("heartbeat_file", boost::program_options::value<std::string>(), "HeartbeatName")
        ("uart_log", boost::program_options::value<std::string>(), "UART log path")
        ("trigger-start", boost::program_options::value<unsigned long>(), "Trigger wave capture at cycle count N")
        ("trigger-end", boost::program_options::value<unsigned long>(), "Trigger wave capture at cycle count N")
        ("compliance", "Run compliance test")
        ("help,h", "Help screen");
    // clang-format on

    boost::program_options::positional_options_description positional;
    positional.add("sim", 1);
    positional.add("elf", 1);

    boost::program_options::command_line_parser parser{argc, argv};
    parser.options(options).positional(positional).allow_unregistered();
    boost::program_options::parsed_options parsed_options = parser.run();

    boost::program_options::variables_map vm;
    boost::program_options::store(parsed_options, vm);

    if (vm.count("help")) {
        std::cout << options << std::endl;
        exit(0);
    } else if (vm.count("elf") != 1) {
        std::cout << "error: one test ELF file must be supplied" << std::endl;
        exit(2);
    } else if (vm.count("sim") != 1) {
        std::cout << "error: one test simulator must be supplied" << std::endl;
        exit(2);
    }

    return vm;
}

int main(int argc, char *argv[])
{
    boost::program_options::variables_map vm;

    try {
        vm = parse_options(argc, argv);
    } catch (boost::program_options::error &e) {
        std::cerr << e.what() << std::endl;
        exit(3);
    }

    try {
        auto trace_name =
            vm.count("trace_file")
                ? std::optional<std::string>(vm["trace_file"].as<std::string>())
                : std::nullopt;
        auto heartbeat_name =
            vm.count("heartbeat_file")
                ? std::optional<std::string>(vm["heartbeat_file"].as<std::string>())
                : std::nullopt;
        auto uart_log = vm.count("uart_log") ? vm["uart_log"].as<std::string>()
                                             : "uart0.log";

        std::unique_ptr<SimulatorBase> sim;
        if (vm["sim"].as<std::string>() == "software") {
            sim = std::make_unique<RXVSim>(trace_name, heartbeat_name,
                                           384 * 1024 * 1024,
                                           0x80000000, uart_log);
        } else if (vm["sim"].as<std::string>() == "rtl") {
            bool waves = vm.count("waves");

            if (waves) {
                sim = std::make_unique<RXVCore<true>>(
                    trace_name, heartbeat_name,
                    384 * 1024 * 1024, 0x80000000,
                    vm["waves"].as<std::string>(), uart_log);
                if (vm.count("trigger-start"))
                    sim->set_trigger_start(
                        vm["trigger-start"].as<unsigned long>());
                if (vm.count("trigger-end"))
                    sim->set_trigger_end(vm["trigger-end"].as<unsigned long>());
            } else {
                sim = std::make_unique<RXVCore<false>>(
                    trace_name, heartbeat_name, 384 * 1024 * 1024, 0x80000000,
                    "no_waves.fst", uart_log);
            }
        } else {
            std::cerr << "error: invalid simulator "
                      << vm["sim"].as<std::string>() << std::endl;
            return 3;
        }

        if (vm.count("binary")) {
            auto binaries = vm["binary"].as<std::vector<std::string>>();

            for (auto &b : binaries) {
                std::vector<std::string> strs;
                boost::split(strs, b, boost::is_any_of("@"));

                if (strs.size() != 2)
                    throw std::runtime_error(
                        "invalid --binary usage: \"--binary PATH@ADDRESS\"");
                sim->load_binary(strs[0], strtoul(strs[1].c_str(), NULL, 0));
            }
        }

        if (vm.count("compliance")) {
            ComplianceTest test(std::move(sim), vm["elf"].as<std::string>());
            return test.run() ? 0 : 1;
        } else {
            Simulation test(std::move(sim), vm["elf"].as<std::string>());
            test.run();
        }
    } catch (std::exception &e) {
        std::cerr << "error: fatal exception " << e.what() << std::endl;
        return -1;
    }

    return 0;
}
