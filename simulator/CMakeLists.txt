set(Boost_NO_BOOST_CMAKE ON)
set(Boost_USE_MULTITHREADED TRUE)
find_package(Boost 1.71.0 COMPONENTS program_options REQUIRED)

get_target_property(RXVCORE_INCLUDE_DIRECTORIES RXVCoreEmul INCLUDE_DIRECTORIES)
set(CMAKE_CXX_FLAGS "-Wno-bool-operation -Wno-maybe-uninitialized -Wno-unused-parameter -Wno-error=unused-parameter ${CMAKE_CXX_FLAGS}")

include_directories(${Boost_INCLUDE_DIRS})
include_directories(${CMAKE_CURRENT_BINARY_DIR}/../tools)
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/../verif/rtl)
include_directories(include)
include_directories(${RXVCORE_INCLUDE_DIRECTORIES})

set(CMAKE_CXX_FLAGS "-Wno-bool-operation -Wno-unused-parameter -Wno-unused-variable ${CMAKE_CXX_FLAGS}")

add_subdirectory(bootrom)

add_executable(rxv-simulator
               Simulator.cpp
               ComplianceTest.h
               RXVCore.h
               RXVSim.cpp
               RXVSim.h
               SimulatorBase.cpp
               SimulatorBase.h
               RiscVELF.cpp
               RiscVELF.h)
add_dependencies(rxv-simulator gen_trace_h)
target_link_libraries(rxv-simulator
                      RXVCoreEmul
                      fmt
                      ${Boost_LIBRARIES}
                      ${ZLIB_LIBRARIES})

ExternalProject_Add(riscv-tests
                    GIT_REPOSITORY https://github.com/riscv/riscv-tests.git
                    GIT_TAG b1e56a620d976b89c7910e522989031e5f934b1b
                    UPDATE_DISCONNECTED ${UPDATE_DISCONNECTED}
                    UPDATE_COMMAND ""
                    CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env CFLAGS=-ggdb <SOURCE_DIR>/configure --target=riscv64-unknown-elf --with-xlen=32
                    BUILD_COMMAND make
                    INSTALL_COMMAND ""
                    TEST_COMMAND "")

enable_testing()

add_test(software-compliance
         python3 ${CMAKE_CURRENT_SOURCE_DIR}/../scripts/run-compliance-tests.py software ${CMAKE_CURRENT_SOURCE_DIR}/../vendor/riscv-arch-test ${CMAKE_CURRENT_BINARY_DIR}/software-compliance ${CMAKE_CURRENT_SOURCE_DIR}/../verif/rxv-arch-test-target)
set_tests_properties(software-compliance PROPERTIES TIMEOUT 60)
set_property(TEST software-compliance PROPERTY ENVIRONMENT
             "PATH=${CMAKE_CURRENT_BINARY_DIR}:$ENV{PATH}")

add_test(rtl-compliance
         python3 ${CMAKE_CURRENT_SOURCE_DIR}/../scripts/run-compliance-tests.py rtl ${CMAKE_CURRENT_SOURCE_DIR}/../vendor/riscv-arch-test ${CMAKE_CURRENT_BINARY_DIR}/rtl-compliance ${CMAKE_CURRENT_SOURCE_DIR}/../verif/rxv-arch-test-target)
set_tests_properties(rtl-compliance PROPERTIES TIMEOUT 1000)
set_property(TEST rtl-compliance PROPERTY ENVIRONMENT
             "PATH=${CMAKE_CURRENT_BINARY_DIR}:$ENV{PATH}")

add_test(software-isa
         ${CMAKE_CURRENT_SOURCE_DIR}/../scripts/run-isa-tests ${CMAKE_CURRENT_BINARY_DIR}/rxv-simulator software ${CMAKE_CURRENT_BINARY_DIR}/riscv-tests-prefix/src/riscv-tests-build/isa)
set_tests_properties(software-isa PROPERTIES TIMEOUT 60)

add_test(rtl-isa
         ${CMAKE_CURRENT_SOURCE_DIR}/../scripts/run-isa-tests ${CMAKE_CURRENT_BINARY_DIR}/rxv-simulator rtl ${CMAKE_CURRENT_BINARY_DIR}/riscv-tests-prefix/src/riscv-tests-build/isa)
set_tests_properties(rtl-isa PROPERTIES TIMEOUT 1000)
