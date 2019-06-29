find_package(Boost COMPONENTS program_options REQUIRED)
include_directories(${Boost_INCLUDE_DIR})
include(Verilator)

verilate(TOPLEVEL RXVCore
         VERILOG_SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/../rtl/RXVCore.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../rtl/RegFile.sv)

add_executable(rxv-simulator
               Simulator.cpp
               ComplianceTest.h
               RXVSim.cpp
	       RXVSim.h
	       SimulatorBase.cpp
	       SimulatorBase.h
               RiscVELF.cpp
               RiscVELF.h)
target_link_libraries(rxv-simulator
		      verilator
		      VRXVCore
                      ${Boost_LIBRARIES})

ExternalProject_Add(riscv-compliance
		    GIT_REPOSITORY https://github.com/jamieiles/riscv-compliance.git
		    GIT_TAG origin/rxv
		    UPDATE_DISCONNECTED ${UPDATE_DISCONNECTED}
		    UPDATE_COMMAND ""
		    CONFIGURE_COMMAND ""
		    BUILD_COMMAND ""
		    INSTALL_COMMAND ""
		    TEST_COMMAND "")

ExternalProject_Add(riscv-tests
		    GIT_REPOSITORY https://github.com/riscv/riscv-tests.git
		    GIT_TAG origin/master
		    UPDATE_DISCONNECTED ${UPDATE_DISCONNECTED}
		    UPDATE_COMMAND ""
		    CONFIGURE_COMMAND <SOURCE_DIR>/configure --target=riscv64-unknown-elf --with-xlen=32
		    BUILD_COMMAND make
		    INSTALL_COMMAND ""
		    TEST_COMMAND "")

enable_testing()
add_test(compliance
	 make -C ${CMAKE_CURRENT_BINARY_DIR}/riscv-compliance-prefix/src/riscv-compliance RISCV_TARGET=rxv-simulator RISCV_ISA=rv32i RISCV_DEVICE=rv32i -j1)
set_property(TEST compliance PROPERTY ENVIRONMENT
	     "PATH=${CMAKE_CURRENT_BINARY_DIR}:$ENV{PATH}")

add_test(isa
	 ${CMAKE_CURRENT_SOURCE_DIR}/../scripts/run-isa-tests ${CMAKE_CURRENT_BINARY_DIR}/rxv-simulator ${CMAKE_CURRENT_BINARY_DIR}/riscv-tests-prefix/src/riscv-tests-build/isa)