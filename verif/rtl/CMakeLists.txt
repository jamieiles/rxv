include(Verilator)
include(Yosys)

include_directories(../../vendor/googletest/googletest/include)
include_directories(../../vendor/googletest/googlemock/include)
include_directories(../../simulator)
include_directories(${CMAKE_CURRENT_BINARY_DIR}/../../simulator)

set_source_files_properties(${VERILATED_DPI_CPP} PROPERTIES COMPILE_FLAGS "-Wno-unused-parameter -Wno-error")
set_source_files_properties(${VERILATED_CPP} PROPERTIES COMPILE_FLAGS "-Wno-unused-parameter -Wno-error")
add_library(verilator SHARED ${VERILATOR_LIB_SOURCES})

verilate(TOPLEVEL RegFile
         VERILOG_SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RegFile.sv)

verilate(TOPLEVEL RXVICache
	     VERILOG_SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVICache.sv
	     ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/DPRAM.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/DPRAMBE.sv
         VERILATOR_ARGS -Gline_size_bytes=16 -Gnr_ways=4 -Gnr_lines=16)

add_executable(rtl-unittest
               TestCache.cpp
               TestRegisterFile.cpp
               TestRXVCore.cpp
               main.cpp)
target_link_libraries(rtl-unittest
                      gtest
                      gmock
                      verilator
                      VRXVCore
                      VRegFile
                      VRXVICache
		      ${ZLIB_LIBRARIES})
add_test(rtl-unittest rtl-unittest)
set_tests_properties(rtl-unittest PROPERTIES TIMEOUT 10)

ys_formal(TOP DPRAMBE
          DEPTH 5
          SKIP 0
          DEFINES "FORMAL_DPRAMBE"
          SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/DPRAMBE.sv)

ys_formal(TOP DPRAM
          DEPTH 5
          SKIP 0
          DEFINES "FORMAL_DPRAM"
          SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/DPRAM.sv)

ys_formal(TOP RXVICache
          DEPTH 15
          SKIP 0
          DEFINES "FORMAL_RXVICACHE"
          SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVICache.sv
                  ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/DPRAM.sv
                  ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/DPRAMBE.sv)

