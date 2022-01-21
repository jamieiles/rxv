find_package(verilator HINTS $ENV{VERILATOR_ROOT})
include(Yosys)

include_directories(../../vendor/googletest/googletest/include)
include_directories(../../vendor/googletest/googlemock/include)
include_directories(../../simulator)
include_directories(../../simulator/include)
include_directories(${CMAKE_CURRENT_BINARY_DIR}/../../simulator)
include_directories(${CMAKE_CURRENT_BINARY_DIR}/../../tools)

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

ys_formal(TOP RXVIntExec
          DEPTH 2
          SKIP 0
          DEFINES "FORMAL_RXVINTEXEC"
          SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTypes.sv
          SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVCSR.sv
          ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVIntExec.sv
          ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVALU.sv
          ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVCSRALU.sv
          ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv)

add_executable(rtl-unittest
               main.cpp
               TestBusTransactor.cpp
               TestFifo.cpp
               TestRXVALU.cpp
               TestRXVBranchPredictor.cpp
               TestRXVCommitBuffer.cpp
               TestRXVLSU.cpp
               TestRXVMul.cpp
               TestRXVDiv.cpp
               TestRXVRegisterAllocator.cpp
               TestRXVRegisterFile.cpp
               TestRXVRenameFile.cpp
               TestRXVScheduler.cpp
               TestRXVScoreboard.cpp
               TestRXVFetch.cpp
               TestRXVDCache.cpp
               TestRXVICache.cpp
               TestRXVCoreEmulWrapper.cpp)
target_link_libraries(rtl-unittest
                      PRIVATE gtest gmock RXVCoreEmul)
add_test(rtl-unittest rtl-unittest)

verilate(rtl-unittest
         VERILATOR_ARGS -Wall -Wpedantic --assert
         SOURCES
         fixtures/BusTransactorWrapper.sv
         fixtures/BusTransactor.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/MemInterface.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         TOP_MODULE BusTransactorWrapper
         TRACE_FST)

verilate(rtl-unittest
         VERILATOR_ARGS -Wall -Wpedantic --assert
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/BitPLRU.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE BitPLRU
         TRACE_FST)

verilate(rtl-unittest
         VERILATOR_ARGS -Wall -Wpedantic --assert
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTypes.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVRegisterFile.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVRegisterFileBanked.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVRegisterFileDFF.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/OneHotEncode.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE RXVRegisterFile
         PREFIX VRXVRegisterFile
         TRACE_FST)

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
         TRACE_FST)

verilate(rtl-unittest
         VERILATOR_ARGS -Wall -Wpedantic --report-unoptflat --assert
         SOURCES
         fixtures/RXVDCacheWrapper.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTypes.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTrace.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVDCache.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVAssert.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/MemInterface.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/OneHotDecode.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RAM.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RAMBE.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/BusAdapter.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE RXVDCacheWrapper
         PREFIX VRXVDCacheWrapper
         TRACE_FST)

verilate(rtl-unittest
         VERILATOR_ARGS -Wall -Wpedantic --report-unoptflat --assert
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTypes.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTrace.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVRegisterAllocator.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE RXVRegisterAllocator
         PREFIX VRXVRegisterAllocator
         DEPENDS gen_trace_h
         TRACE_FST)

verilate(rtl-unittest
         VERILATOR_ARGS -Wall -Wpedantic --report-unoptflat --assert
         PREFIX VRXVRenameFileWrapper
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTypes.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTrace.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/fixtures/RXVRenameFileWrapper.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVRenameFile.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFFPipe.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE RXVRenameFileWrapper
         DEPENDS gen_trace_h
         TRACE_FST)

verilate(rtl-unittest
         VERILATOR_ARGS -Wall -Wpedantic --report-unoptflat --assert
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTypes.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/fixtures/RXVBranchPredictorWrapper.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVBranchPredictor.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE RXVBranchPredictorWrapper
         PREFIX VRXVBranchPredictorWrapper
         TRACE_FST)

verilate(rtl-unittest
         VERILATOR_ARGS -Wall -Wpedantic --report-unoptflat --assert
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTypes.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTrace.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/fixtures/RXVFetchWrapper.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVFetch.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/PosedgeDetect.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE RXVFetchWrapper
         PREFIX VRXVFetchWrapper
         DEPENDS gen_trace_h
         TRACE_FST)

verilate(rtl-unittest
         VERILATOR_ARGS -Wall -Wpedantic --report-unoptflat --assert
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/Fifo.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/OneHotEncode.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE Fifo
         TRACE_FST)

verilate(rtl-unittest
         VERILATOR_ARGS -Wall -Wpedantic --report-unoptflat --assert
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTypes.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTrace.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVCommitBuffer.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/Fifo.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/OneHotEncode.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE RXVCommitBuffer
         PREFIX VRXVCommitBuffer
         DEPENDS gen_trace_h
         TRACE_FST)

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
         TRACE_FST)

verilate(rtl-unittest
         VERILATOR_ARGS -Wall -Wpedantic --report-unoptflat --assert
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTypes.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVALU.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE RXVALU
         PREFIX VRXVALU
         TRACE_FST)

verilate(rtl-unittest
         VERILATOR_ARGS -Wall -Wpedantic --report-unoptflat --assert
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTypes.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTrace.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVScheduler.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE RXVScheduler
         PREFIX VRXVScheduler
         DEPENDS gen_trace_h
         TRACE_FST)

verilate(rtl-unittest
         VERILATOR_ARGS -Wall -Wpedantic --report-unoptflat --assert
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTypes.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTrace.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVCSR.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/fixtures/RXVLSUWrapper.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFFPipe.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVLSU.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVDCache.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE RXVLSUWrapper
         PREFIX VRXVLSUWrapper
         DEPENDS gen_trace_h
         TRACE_FST)

verilate(rtl-unittest
         VERILATOR_ARGS -Wall -Wpedantic --report-unoptflat --assert
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVMul.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE RXVMul
         PREFIX VRXVMul
         TRACE_FST)

verilate(rtl-unittest
         VERILATOR_ARGS -Wall -Wpedantic --report-unoptflat --assert
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTypes.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTrace.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVAssert.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVDiv.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE RXVDiv
         PREFIX VRXVDiv
         TRACE_FST)

add_library(RXVCoreEmul SHARED)
add_dependencies(rtl-unittest gen_trace_h)

verilate(RXVCoreEmul
         VERILATOR_ARGS -Wall -Wpedantic --report-unoptflat --assert -DRXV_TRACE
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/fixtures/RXVCoreEmulWrapper.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTypes.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTrace.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVCSR.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVALU.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVCSRALU.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVCore.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVDecode.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVFetch.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVBranchPredictor.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVCommitBuffer.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVCommitter.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVCSRFile.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVDCache.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVDiv.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVDivExec.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVICache.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVMul.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVMulExec.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVPMU.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVRegisterAllocator.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVRegisterFile.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVRegisterFileBanked.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVRegisterFileDFF.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVRenameFile.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVScheduler.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVScoreboard.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFFPipe.sv
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
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVAssert.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE RXVCoreEmulWrapper
         DEPENDS gen_trace_h
         TRACE_FST)

include_directories(${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/rtl-unittest.dir/VBusTransactorWrapper.dir
                    ${CMAKE_CURRENT_SOURCE_DIR}/../../simulator/include)
