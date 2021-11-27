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

ys_formal(TOP DPRAM
          DEPTH 5
          SKIP 0
          DEFINES "FORMAL_DPRAM"
          SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/DPRAM.sv)

add_executable(rtl-unittest
               main.cpp
               TestBusTransactor.cpp
               TestFifo.cpp
               TestRXVBranchPredictor.cpp
               TestRXVCommitBuffer.cpp
               TestRXVRegisterAllocator.cpp
               TestRXVRegisterFile.cpp
               TestRXVRenameFile.cpp
               TestRXVScoreboard.cpp
               TestRXVFetch.cpp
               TestRXVDCache.cpp
               TestRXVICache.cpp
               TestRXVCoreEmulWrapper.cpp)
target_link_libraries(rtl-unittest
                      PRIVATE gtest gmock)
add_test(rtl-unittest rtl-unittest)

verilate(rtl-unittest
         VERILATOR_ARGS -Wall -Wpedantic --assert
         SOURCES
         fixtures/BusTransactorWrapper.sv
         fixtures/BusTransactor.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/MemInterface.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         TOP_MODULE BusTransactorWrapper
         TRACE_FST COVERAGE)

verilate(rtl-unittest
         VERILATOR_ARGS -Wall -Wpedantic --assert
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/BitPLRU.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE BitPLRU
         TRACE_FST COVERAGE)

verilate(rtl-unittest
         VERILATOR_ARGS -Wall -Wpedantic --assert
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTypes.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVRegisterFile.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/OneHotEncode.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE RXVRegisterFile
         PREFIX VRXVRegisterFile
         TRACE_FST COVERAGE)

verilate(rtl-unittest
         VERILATOR_ARGS -Wall -Wpedantic --assert
         SOURCES
         fixtures/RXVICacheWrapper.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVICache.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/MemInterface.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/OneHotDecode.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RAM.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/BusAdapter.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE RXVICacheWrapper
         TRACE_FST COVERAGE)

verilate(rtl-unittest
         VERILATOR_ARGS -Wall -Wpedantic --report-unoptflat --assert
         SOURCES
         fixtures/RXVDCacheWrapper.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVDCache.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/MemInterface.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/OneHotDecode.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RAM.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RAMBE.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/BusAdapter.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE RXVDCacheWrapper
         TRACE_FST COVERAGE)

verilate(rtl-unittest
         VERILATOR_ARGS -Wall -Wpedantic --report-unoptflat --assert
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTypes.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVRegisterAllocator.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE RXVRegisterAllocator
         PREFIX VRXVRegisterAllocator
         TRACE_FST COVERAGE)

verilate(rtl-unittest
         VERILATOR_ARGS -Wall -Wpedantic --report-unoptflat --assert
         PREFIX VRXVRenameFileWrapper
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTypes.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/fixtures/RXVRenameFileWrapper.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVRenameFile.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE RXVRenameFileWrapper
         TRACE_FST COVERAGE)

verilate(rtl-unittest
         VERILATOR_ARGS -Wall -Wpedantic --report-unoptflat --assert
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVBranchPredictor.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE RXVBranchPredictor
         TRACE_FST COVERAGE)

verilate(rtl-unittest
         VERILATOR_ARGS -Wall -Wpedantic --report-unoptflat --assert
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVFetch.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/PosedgeDetect.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE RXVFetch
         TRACE_FST COVERAGE)

verilate(rtl-unittest
         VERILATOR_ARGS -Wall -Wpedantic --report-unoptflat --assert
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/Fifo.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/OneHotEncode.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE Fifo
         TRACE_FST COVERAGE)

verilate(rtl-unittest
         VERILATOR_ARGS -Wall -Wpedantic --report-unoptflat --assert
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTypes.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVCommitBuffer.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/Fifo.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/OneHotEncode.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE RXVCommitBuffer
         PREFIX VRXVCommitBuffer
         TRACE_FST COVERAGE)

verilate(rtl-unittest
         VERILATOR_ARGS -Wall -Wpedantic --report-unoptflat --assert
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTypes.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVScoreboard.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/OneHotEncode.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE RXVScoreboard
         PREFIX VRXVScoreboard
         TRACE_FST COVERAGE)

verilate(rtl-unittest
         VERILATOR_ARGS -Wall -Wpedantic --report-unoptflat --assert
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/fixtures/RXVCoreEmulWrapper.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTypes.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVCore.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVFetch.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVBranchPredictor.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVCommitBuffer.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVDCache.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVICache.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVRegisterAllocator.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVRegisterFile.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVRenameFile.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVScoreboard.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/BitPLRU.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/BusAdapter.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/DPRAM.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/Fifo.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/MemInterface.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/OneHotEncode.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/OneHotDecode.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/PosedgeDetect.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RAM.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RAMBE.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE RXVCoreEmulWrapper
         TRACE_FST COVERAGE)

include_directories(${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/rtl-unittest.dir/VBusTransactorWrapper.dir
                    ${CMAKE_CURRENT_SOURCE_DIR}/../../simulator/include)