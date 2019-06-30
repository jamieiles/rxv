#include <iostream>
#include <string>
#include <boost/program_options.hpp>

#include "ComplianceTest.h"
#include "RXVCPU.h"

double cur_time_stamp = 0;

static boost::program_options::variables_map parse_options(int argc, char *argv[])
{
    boost::program_options::options_description options{"Options"};
    // clang-format off
    options.add_options()
        ("test", boost::program_options::value<std::string>(), "Test")
        ("help,h", "Help screen");
    // clang-format on

    boost::program_options::positional_options_description positional;
    positional.add("test", 1);

    boost::program_options::command_line_parser parser{argc, argv};
    parser.options(options).positional(positional).allow_unregistered();
    boost::program_options::parsed_options parsed_options = parser.run();

    boost::program_options::variables_map vm;
    boost::program_options::store(parsed_options, vm);

    if (vm.count("help")) {
        std::cout << options << std::endl;
        exit(0);
    } else if (vm.count("test") != 1) {
        std::cout << "error: one test ELF file must be supplied" << std::endl;
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

    ComplianceTest<RXVSim> test(vm["test"].as<std::string>());

    return test.run() ? 0 : 1;
}
