find_package(verilator HINTS $ENV{VERILATOR_ROOT})
include(Yosys)

include_directories(../../vendor/googletest/googletest/include)
include_directories(../../vendor/googletest/googlemock/include)
include_directories(../../simulator)
include_directories(../../simulator/include)
include_directories(${CMAKE_CURRENT_BINARY_DIR}/../../simulator)
include_directories(${CMAKE_CURRENT_BINARY_DIR}/../../tools)

set(CMAKE_CXX_FLAGS "-Wno-bool-operation -Wno-maybe-uninitialized -Wno-unused-parameter -Wno-error=unused-parameter -Wno-unused-variable ${CMAKE_CXX_FLAGS}")
set(VERILATOR_FLAGS -Wall -Wpedantic --report-unoptflat --assert)
add_definitions(-DVL_DPIDECL_dpi_set_bus_)
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
          INCLUDES ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
          SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTypes.sv
          SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVMMU.sv
          SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVCSR.sv
          ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVIntExec.sv
          ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVALU.sv
          ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVCSRALU.sv
          ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv)

add_executable(rtl-unittest
    main.cpp
    fixtures/BusTransactorDPI.cpp
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
    TestRXVPTWalker.cpp
    TestRXVTLB.cpp
    TestRXVPMP.cpp
    TestRXVMMUTop.cpp
    TestRXVICache.cpp
    TestRXVCoreEmulWrapper.cpp
    TestStaticArbiter.cpp)
target_link_libraries(rtl-unittest
                      PRIVATE gtest gmock RXVCoreEmul fmt)
add_test(rtl-unittest rtl-unittest)

verilate(rtl-unittest
    VERILATOR_ARGS ${VERILATOR_FLAGS}
    PREFIX VBusTransactorWrapper
    SOURCES
    fixtures/BusTransactorWrapper.sv
    fixtures/BusTransactor.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/MemInterface.sv
    INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
    TOP_MODULE BusTransactorWrapper
    TRACE_FST TRACE_STRUCTS)

verilate(rtl-unittest
    VERILATOR_ARGS ${VERILATOR_FLAGS}
    PREFIX VBitPLRU
    SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/BitPLRU.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv
    INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
    TOP_MODULE BitPLRU
    TRACE_FST TRACE_STRUCTS)

verilate(rtl-unittest
         VERILATOR_ARGS ${VERILATOR_FLAGS}
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
         TRACE_FST TRACE_STRUCTS)

verilate(rtl-unittest
    VERILATOR_ARGS ${VERILATOR_FLAGS}
    PREFIX VRXVICacheWrapper
    SOURCES
    fixtures/RXVICacheWrapper.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVICache.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/MemInterface.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/OneHotDecode.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RAM.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/BusAdapter.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/CacheRAM.sv
    INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
    INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
    TOP_MODULE RXVICacheWrapper
    TRACE_FST TRACE_STRUCTS)

verilate(rtl-unittest
         VERILATOR_ARGS ${VERILATOR_FLAGS}
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
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVCountdown.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/CacheRAM.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE RXVDCacheWrapper
         PREFIX VRXVDCacheWrapper
         TRACE_FST TRACE_STRUCTS)

verilate(rtl-unittest
    VERILATOR_ARGS ${VERILATOR_FLAGS}
    PREFIX VRXVPTWalkerWrapper
    SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTypes.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTrace.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVMMU.sv
    fixtures/RXVPTWalkerWrapper.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVPTWalker.sv
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
    TOP_MODULE RXVPTWalkerWrapper
    TRACE_FST TRACE_STRUCTS)

verilate(rtl-unittest
         VERILATOR_ARGS ${VERILATOR_FLAGS}
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVMMU.sv
         fixtures/RXVTLBWrapper.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTypes.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTrace.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVTLB.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVPTWalker.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVDCache.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVAssert.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/MemInterface.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/OneHotDecode.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RAM.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RAMBE.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/TLBPLRU.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/BusAdapter.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE RXVTLBWrapper
         PREFIX VRXVTLBWrapper
         TRACE_FST TRACE_STRUCTS)

verilate(rtl-unittest
         VERILATOR_ARGS ${VERILATOR_FLAGS}
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVMMU.sv
         fixtures/RXVMMUTopWrapper.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTypes.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTrace.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVTLB.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVPTWalker.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVDCache.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVMMUTop.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVAssert.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/MemInterface.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/OneHotDecode.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RAM.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RAMBE.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/TLBPLRU.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/BusAdapter.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/StaticArbiter.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE RXVMMUTopWrapper
         PREFIX VRXVMMUTopWrapper
         TRACE_FST TRACE_STRUCTS)

verilate(rtl-unittest
         VERILATOR_ARGS ${VERILATOR_FLAGS}
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
         TRACE_FST TRACE_STRUCTS)

verilate(rtl-unittest
         VERILATOR_ARGS ${VERILATOR_FLAGS}
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
         TRACE_FST TRACE_STRUCTS)

verilate(rtl-unittest
         VERILATOR_ARGS ${VERILATOR_FLAGS}
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTypes.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/fixtures/RXVBranchPredictorWrapper.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVBranchPredictor.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE RXVBranchPredictorWrapper
         PREFIX VRXVBranchPredictorWrapper
         TRACE_FST TRACE_STRUCTS)

verilate(rtl-unittest
         VERILATOR_ARGS ${VERILATOR_FLAGS}
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTypes.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTrace.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVMMU.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVCSR.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/fixtures/RXVFetchWrapper.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVFetch.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/PosedgeDetect.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE RXVFetchWrapper
         PREFIX VRXVFetchWrapper
         DEPENDS gen_trace_h
         TRACE_FST TRACE_STRUCTS)

verilate(rtl-unittest
    VERILATOR_ARGS ${VERILATOR_FLAGS}
    PREFIX VFifo
    SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/Fifo.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/OneHotEncode.sv
    INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
    INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
    TOP_MODULE Fifo
    TRACE_FST TRACE_STRUCTS)

verilate(rtl-unittest
         VERILATOR_ARGS ${VERILATOR_FLAGS}
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
         TRACE_FST TRACE_STRUCTS)

verilate(rtl-unittest
         VERILATOR_ARGS ${VERILATOR_FLAGS}
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTypes.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVScoreboard.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/OneHotEncode.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE RXVScoreboard
         PREFIX VRXVScoreboard
         TRACE_FST TRACE_STRUCTS)

verilate(rtl-unittest
         VERILATOR_ARGS ${VERILATOR_FLAGS}
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTypes.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVALU.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE RXVALU
         PREFIX VRXVALU
         TRACE_FST TRACE_STRUCTS)

verilate(rtl-unittest
         VERILATOR_ARGS ${VERILATOR_FLAGS}
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTypes.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTrace.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVScheduler.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE RXVScheduler
         PREFIX VRXVScheduler
         DEPENDS gen_trace_h
         TRACE_FST TRACE_STRUCTS)

verilate(rtl-unittest
         VERILATOR_ARGS ${VERILATOR_FLAGS}
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTypes.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTrace.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVMMU.sv
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
         TRACE_FST TRACE_STRUCTS)

verilate(rtl-unittest
         VERILATOR_ARGS ${VERILATOR_FLAGS}
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVMul.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE RXVMul
         PREFIX VRXVMul
         TRACE_FST TRACE_STRUCTS)

verilate(rtl-unittest
         VERILATOR_ARGS ${VERILATOR_FLAGS}
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTypes.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTrace.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVAssert.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVDiv.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE RXVDiv
         PREFIX VRXVDiv
         TRACE_FST TRACE_STRUCTS)

verilate(rtl-unittest
         VERILATOR_ARGS ${VERILATOR_FLAGS}
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTypes.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTrace.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVAssert.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/StaticArbiter.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE StaticArbiter
         PREFIX VStaticArbiter
         TRACE_FST TRACE_STRUCTS)

verilate(rtl-unittest
         VERILATOR_ARGS ${VERILATOR_FLAGS}
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTypes.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTrace.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVAssert.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVMMU.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVPMP.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE RXVPMP
         PREFIX VRXVPMP
         TRACE_FST TRACE_STRUCTS)

add_library(RXVCoreEmul SHARED
    fixtures/BusTransactorDPI.cpp
    fixtures/RXVTrace.cpp)
add_dependencies(rtl-unittest gen_trace_h)

verilate(RXVCoreEmul
    VERILATOR_ARGS ${VERILATOR_FLAGS} -DRXV_TRACE
    PREFIX VRXVCoreEmulWrapper
    SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/fixtures/RXVCoreEmulWrapper.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/fixtures/MtimeTransactor.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTypes.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTrace.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVMMU.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVCSR.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/StaticArbiter.sv
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
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVDCacheArb.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVDiv.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVDivExec.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVEventCounter.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVICache.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVIntExec.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVLSU.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVMMUTop.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVMul.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVMulExec.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVPMP.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVPMU.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVPTWalker.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVRegisterAllocator.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVRegisterFile.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVRegisterFileBanked.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVRegisterFileDFF.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVRenameFile.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVScheduler.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVScoreboard.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVTLB.sv
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
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/TLBPLRU.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/CacheRAM.sv
    INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
    INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl
    INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
    TOP_MODULE RXVCoreEmulWrapper
    THREADS 1
    OPT_GLOBAL "-O3"
    TRACE_FST TRACE_STRUCTS)

include_directories(${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/rtl-unittest.dir/VBusTransactorWrapper.dir
                    ${CMAKE_CURRENT_SOURCE_DIR}/../../simulator/include)
