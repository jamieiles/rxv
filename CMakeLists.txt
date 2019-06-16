cmake_minimum_required(VERSION 3.0.2)
include(ExternalProject)
include(CTest)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(UPDATE_DISCONNECTED true CACHE BOOL "Don't update external git repos during build")

find_package(Boost COMPONENTS program_options REQUIRED)
include_directories(${Boost_INCLUDE_DIR})

add_executable(rxv-simulator
               Simulator.cpp
               ComplianceTest.h
               RXVSim.cpp
               RXVSim.h
               RiscVELF.cpp
               RiscVELF.h)
target_link_libraries(rxv-simulator
                      ${Boost_LIBRARIES})

ExternalProject_Add(riscv-compliance
		    GIT_REPOSITORY https://github.com/jamieiles/riscv-compliance.git
		    GIT_TAG origin/rxv
		    UPDATE_DISCONNECTED ${UPDATE_DISCONNECTED}
		    CONFIGURE_COMMAND ""
		    BUILD_COMMAND ""
		    INSTALL_COMMAND ""
		    TEST_COMMAND "")

enable_testing()
add_test(compliance
	 make -C ${CMAKE_CURRENT_BINARY_DIR}/riscv-compliance-prefix/src/riscv-compliance RISCV_TARGET=rxv-simulator RISCV_ISA=rv32i RISCV_DEVICE=rv32i -j1)
set_property(TEST compliance PROPERTY ENVIRONMENT
	     "PATH=${CMAKE_CURRENT_BINARY_DIR}:$ENV{PATH}")
