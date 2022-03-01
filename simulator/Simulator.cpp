#include <iostream>
#include <string>
#include <boost/program_options.hpp>
#include <signal.h>
#include <chrono>

#include "ComplianceTest.h"

double cur_time_stamp = 0;
static bool sigint_received;

double sc_time_stamp()
{
    return cur_time_stamp;
}

static void sigint_handler(int signum)
{
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
            while (!sigint_received)
                sim->step();
        } catch (std::exception &e) {
            std::cerr << "\r\nERROR: " << e.what() << "\r\n" << std::endl;
        }
        auto end = std::chrono::steady_clock::now();
        std::chrono::duration<double> duration = end - start;

        fmt::print("[simulation finished]\n\r");
        auto stats = sim->get_perf_stats();
        // clang-format off
        fmt::print(
            "{0:d} instructions in {1:d} cycles ({2:0.2f} instructions per cycle)\n\r",
            stats.retired, stats.cycles, static_cast<double>(stats.retired) / stats.cycles);
        fmt::print("{0:d} IRQs\n\r", stats.num_irqs);
        fmt::print("Simulation speed {0:s}\r\n",
                   human_freq(stats.cycles / duration.count()));
        // clang-format on
    }

private:
    std::unique_ptr<SimulatorBase> sim;
};

static boost::program_options::variables_map parse_options(int argc,
                                                           char *argv[])
{
    boost::program_options::options_description options{"Options"};
    // clang-format off
    options.add_options()
        ("elf", boost::program_options::value<std::string>(), "ELF file")
        ("sim", boost::program_options::value<std::string>(), "Simulator")
        ("waves", boost::program_options::value<std::string>(), "Waves File")
        ("trace_file", boost::program_options::value<std::string>(), "TraceName")
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

        std::unique_ptr<SimulatorBase> sim;
        if (vm["sim"].as<std::string>() == "software") {
            sim = std::make_unique<RXVSim>(trace_name, 256 * 1024 * 1024,
                                           0x80000000);
        } else if (vm["sim"].as<std::string>() == "rtl") {
            bool waves = vm.count("waves");

            if (waves)
                sim = std::make_unique<RXVCore<true>>(
                    trace_name, 256 * 1024 * 1024, 0x80000000,
                    vm["waves"].as<std::string>());
            else
                sim = std::make_unique<RXVCore<false>>(
                    trace_name, 256 * 1024 * 1024, 0x80000000);
        } else {
            std::cerr << "error: invalid simulator "
                      << vm["sim"].as<std::string>() << std::endl;
            return 3;
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
