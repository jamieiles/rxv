find_package(verilator HINTS $ENV{VERILATOR_ROOT})
include(Yosys)

include_directories(../../vendor/googletest/googletest/include)
include_directories(../../vendor/googletest/googlemock/include)
include_directories(../../simulator)
include_directories(${CMAKE_CURRENT_BINARY_DIR}/../../simulator)

ys_formal(TOP RAMBE
          DEPTH 5
          SKIP 0
          DEFINES "FORMAL_RAMBE"
          SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RAMBE.sv)

ys_formal(TOP RAM
          DEPTH 5
          SKIP 0
          DEFINES "FORMAL_RAM"
          SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RAM.sv)

add_executable(rtl-unittest
               main.cpp
               TestBusTransactor.cpp)
target_link_libraries(rtl-unittest
                      PRIVATE gtest gmock)
add_test(rtl-unittest rtl-unittest)

verilate(rtl-unittest
         VERILATOR_ARGS -Wall
         SOURCES
         fixtures/BusTransactorWrapper.sv
         fixtures/BusTransactor.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/MemInterface.sv
         TOP_MODULE BusTransactorWrapper
         TRACE_FST COVERAGE)
include_directories(${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/rtl-unittest.dir/VBusTransactorWrapper.dir
                    ${CMAKE_CURRENT_SOURCE_DIR}/../../simulator/include)