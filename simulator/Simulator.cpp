#include <iostream>
#include <string>
#include <boost/program_options.hpp>
#include <signal.h>

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

        try {
            while (!sigint_received)
                sim->step();
        } catch (std::exception &e) {
            std::cerr << "\r\nERROR: " << e.what() << "\r\n" << std::endl;
        }

        std::cout << "[simulation finished]\r" << std::endl;
        auto stats = sim->get_perf_stats();
        std::cout << std::dec << std::setprecision(2) << "  " << stats.retired
                  << " instructions in " << stats.cycles << " cycles ("
                  << static_cast<double>(stats.retired) / stats.cycles
                  << " instructions per cycle)" << std::endl;
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
        ("waves", "Waves Enabled")
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

static std::string instance_name(const std::string &elf_path)
{
    auto bn = basename(elf_path.c_str());

    return std::string(bn);
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
            if (vm.count("waves") || vm.count("trace_file"))
                sim = std::make_unique<RXVCore<true>>(
                    trace_name, 256 * 1024 * 1024, 0x80000000,
                    instance_name(vm["elf"].as<std::string>()));
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
