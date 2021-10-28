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

template <typename T>
class Simulation
{
public:
    explicit Simulation(const std::string &filename,
                        const std::optional<std::string> trace_name)
        : sim(trace_name, 256 * 1024 * 1024, 0x80000000)
    {
        RiscVELF elf(filename);

        sim.load_elf(elf);
    }

    void run()
    {
        signal(SIGINT, sigint_handler);
        signal(SIGQUIT, sigint_handler);

        try {
            while (!sigint_received)
                sim.step();
        } catch (std::exception &e) {
            std::cerr << "\r\nERROR: " << e.what() << "\r\n" << std::endl;
        }

        std::cout << "[simulation finished]\r" << std::endl;
    }

private:
    T sim;
};

static boost::program_options::variables_map parse_options(int argc,
                                                           char *argv[])
{
    boost::program_options::options_description options{"Options"};
    // clang-format off
    options.add_options()
        ("elf", boost::program_options::value<std::string>(), "ELF file")
        ("sim", boost::program_options::value<std::string>(), "Simulator")
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

        if (vm["sim"].as<std::string>() == "software") {
            if (vm.count("compliance")) {
                ComplianceTest<RXVSim> test(vm["elf"].as<std::string>(),
                                            trace_name);
                return test.run() ? 0 : 1;
            } else {
                Simulation<RXVSim> test(vm["elf"].as<std::string>(),
                                        trace_name);
                test.run();
            }
        } else {
            std::cerr << "error: invalid simulator " << vm["sim"].as<std::string>() << std::endl;
            return 3;
        }
    } catch (std::exception &e) {
        std::cerr << "error: fatal exception " << e.what() << std::endl;
        return -1;
    }

    return 0;
}
