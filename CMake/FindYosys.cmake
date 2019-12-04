include(FindPackageHandleStandardArgs)

find_program(YOSYS_EXECUTABLE NAMES yosys)
find_program(SBY_EXECUTABLE NAMES sby)

find_package_handle_standard_args(Yosys FOUND_VAR YOSYS_FOUND
                                  REQUIRED_VARS
                                  YOSYS_EXECUTABLE
                                  SBY_EXECUTABLE)
