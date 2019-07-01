find_package(Boost COMPONENTS program_options REQUIRED)
include_directories(${Boost_INCLUDE_DIR})
include_directories(../verif/rtl)
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

add_test(software-compliance
	 make -C ${CMAKE_CURRENT_BINARY_DIR}/riscv-compliance-prefix/src/riscv-compliance RISCV_TARGET="rxv-simulator" RXV_SIMULATOR=software RISCV_ISA=rv32i RISCV_DEVICE=rv32i -j1)
set_tests_properties(software-compliance PROPERTIES TIMEOUT 10)
set_property(TEST software-compliance PROPERTY ENVIRONMENT
	     "PATH=${CMAKE_CURRENT_BINARY_DIR}:$ENV{PATH}")
set_tests_properties(software-compliance PROPERTIES RESOURCE_LOCK "compliance")

add_test(software-isa
	 ${CMAKE_CURRENT_SOURCE_DIR}/../scripts/run-isa-tests ${CMAKE_CURRENT_BINARY_DIR}/rxv-simulator software ${CMAKE_CURRENT_BINARY_DIR}/riscv-tests-prefix/src/riscv-tests-build/isa)
set_tests_properties(software-isa PROPERTIES TIMEOUT 10)

add_test(rtl-compliance
	 make -C ${CMAKE_CURRENT_BINARY_DIR}/riscv-compliance-prefix/src/riscv-compliance RISCV_TARGET="rxv-simulator" RXV_SIMULATOR=rtl RISCV_ISA=rv32i RISCV_DEVICE=rv32i -j1)
set_tests_properties(rtl-compliance PROPERTIES TIMEOUT 20)
set_property(TEST rtl-compliance PROPERTY ENVIRONMENT
             "PATH=${CMAKE_CURRENT_BINARY_DIR}:$ENV{PATH}")
set_tests_properties(rtl-compliance PROPERTIES RESOURCE_LOCK "compliance")

add_test(rtl-isa
	 ${CMAKE_CURRENT_SOURCE_DIR}/../scripts/run-isa-tests ${CMAKE_CURRENT_BINARY_DIR}/rxv-simulator rtl ${CMAKE_CURRENT_BINARY_DIR}/riscv-tests-prefix/src/riscv-tests-build/isa)
set_tests_properties(rtl-isa PROPERTIES TIMEOUT 20)
