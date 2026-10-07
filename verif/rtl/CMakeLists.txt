find_package(verilator HINTS $ENV{VERILATOR_ROOT})
include(Yosys)

include_directories(../../vendor/googletest/googletest/include)
include_directories(../../vendor/googletest/googlemock/include)
include_directories(../../simulator)
include_directories(../../simulator/include)
include_directories(${CMAKE_CURRENT_BINARY_DIR}/../../simulator)
include_directories(${CMAKE_CURRENT_BINARY_DIR}/../../tools)

set(CMAKE_CXX_FLAGS "-Wno-bool-operation -Wno-maybe-uninitialized -Wno-unused-parameter -Wno-error=unused-parameter -Wno-unused-variable -Wno-error=stringop-overread ${CMAKE_CXX_FLAGS}")
set(VERILATOR_FLAGS --quiet-stats -Wall -Wpedantic --x-assign fast --x-initial fast --report-unoptflat --assert)
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

foreach(sdhci_top SDClockGen SDCmdEngine SDDataEngine SDDataFifo SDHCIRegs SDHCIDMA)
    ys_formal(TOP ${sdhci_top}
              DEPTH 2
              SKIP 0
              DEFINES "FORMAL_${sdhci_top}"
              INCLUDES ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
              SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/sdhci/${sdhci_top}.sv
              ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv)
endforeach()

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
    TestStaticArbiter.cpp
    TestMIGFrontend.cpp
    TestSDRAMFrontend.cpp
    TestPLIC.cpp
    TestAltPS2.cpp
    TestVGAScanout.cpp
    TestDE0CVSoC.cpp
    TestDE0CVBoot.cpp
    TestSDHCI.cpp
    fixtures/SDCardModel.cpp)
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
    VERILATOR_ARGS ${VERILATOR_FLAGS} -DRXV_TRACE -CFLAGS "-Wno-stringop-overread -fno-var-tracking-assignments"
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

verilate(rtl-unittest
    VERILATOR_ARGS ${VERILATOR_FLAGS}
    PREFIX VMIGFrontendWrapper
    SOURCES
    fixtures/MIGFrontendWrapper.sv
    fixtures/MIGFrontendTestDevice.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTypes.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTrace.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/MemInterface.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/BusAdapter.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVAssert.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/MemSplit.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/xilinx/MIGFrontend.sv
    INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
    INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
    TOP_MODULE MIGFrontendWrapper
    TRACE_FST TRACE_STRUCTS)

verilate(rtl-unittest
    VERILATOR_ARGS ${VERILATOR_FLAGS}
    PREFIX VSDRAMFrontendWrapper
    SOURCES
    fixtures/SDRAMFrontendWrapper.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTypes.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVTrace.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/MemInterface.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/BusAdapter.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVAssert.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/sdram/SDRAMController.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/sdram/SDRAMFrontend.sv
    INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
    INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
    TOP_MODULE SDRAMFrontendWrapper
    TRACE_FST TRACE_STRUCTS)

verilate(rtl-unittest
    VERILATOR_ARGS ${VERILATOR_FLAGS}
    PREFIX VPLIC
    SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/PLIC.sv
    INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
    TOP_MODULE PLIC
    TRACE_FST TRACE_STRUCTS)

verilate(rtl-unittest
    VERILATOR_ARGS ${VERILATOR_FLAGS}
    PREFIX VAltPS2
    SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVADFF.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/BitSync.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/ps2/PS2Host.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/ps2/AltPS2.sv
    INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
    TOP_MODULE AltPS2
    TRACE_FST TRACE_STRUCTS)

verilate(rtl-unittest
    VERILATOR_ARGS ${VERILATOR_FLAGS}
    PREFIX VVGAScanoutWrapper
    SOURCES
    fixtures/VGAScanoutWrapper.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/MemInterface.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVADFF.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/BitSync.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/video/VGAScanout.sv
    INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
    INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
    TOP_MODULE VGAScanoutWrapper
    TRACE_FST TRACE_STRUCTS)

# A test program for the DE0-CV boot ROM
add_custom_command(OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/soctest.hex
    COMMAND riscv64-unknown-elf-gcc -march=rv32ima_zicsr_zifencei_zicbom -mabi=ilp32
            -nostdlib -T ${CMAKE_CURRENT_SOURCE_DIR}/de0cv/soctest.x
            -o ${CMAKE_CURRENT_BINARY_DIR}/soctest.elf
            ${CMAKE_CURRENT_SOURCE_DIR}/de0cv/soctest.S
    COMMAND riscv64-unknown-elf-objcopy -O binary ${CMAKE_CURRENT_BINARY_DIR}/soctest.elf
            ${CMAKE_CURRENT_BINARY_DIR}/soctest.bin
    COMMAND xxd -e -c 4 -g4 ${CMAKE_CURRENT_BINARY_DIR}/soctest.bin | awk \'{print $$2}\'
            > ${CMAKE_CURRENT_BINARY_DIR}/soctest.hex
    DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/de0cv/soctest.S ${CMAKE_CURRENT_SOURCE_DIR}/de0cv/soctest.x)
add_custom_target(soctest_hex DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/soctest.hex)
add_dependencies(rtl-unittest soctest_hex)

verilate(rtl-unittest
    VERILATOR_ARGS ${VERILATOR_FLAGS}
        "-Gbootrom_init=\"${CMAKE_CURRENT_BINARY_DIR}/soctest.hex\""
        -Gsdram_init_wait_ns=2000
    PREFIX VDE0CVSoC
    SOURCES
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
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/BitSync.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVADFF.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/MemSplit.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/BootROM.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/BootROMPort.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/AXILiteDecoder.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/AXILiteRegs.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/RXVCLINT.v
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/PLIC.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/DebugRegs.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/ConsoleUART.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/ps2/PS2Host.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/ps2/AltPS2.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/video/VGAScanout.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/sdram/SDRAMController.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/sdram/SDRAMFrontend.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/sdhci/SDHCI.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/sdhci/SDHCIRegs.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/sdhci/SDClockGen.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/sdhci/SDCmdEngine.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/sdhci/SDDataEngine.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/sdhci/SDDataFifo.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/sdhci/SDHCIDMA.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/intel/de0-cv/DE0CVSoC.sv
    INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl
    INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
    TOP_MODULE DE0CVSoC
    THREADS 1
    OPT_GLOBAL "-O3"
    TRACE_FST TRACE_STRUCTS)

# The DE0-CV boot ROM loading a payload from the SD card
add_custom_command(OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/payload.bin
    COMMAND riscv64-unknown-elf-gcc -march=rv32ima_zicsr_zifencei -mabi=ilp32
            -nostdlib -T ${CMAKE_CURRENT_SOURCE_DIR}/de0cv/payload.x
            -o ${CMAKE_CURRENT_BINARY_DIR}/payload.elf
            ${CMAKE_CURRENT_SOURCE_DIR}/de0cv/payload.S
    COMMAND riscv64-unknown-elf-objcopy -O binary ${CMAKE_CURRENT_BINARY_DIR}/payload.elf
            ${CMAKE_CURRENT_BINARY_DIR}/payload.bin
    DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/de0cv/payload.S ${CMAKE_CURRENT_SOURCE_DIR}/de0cv/payload.x)
add_custom_target(payload_bin DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/payload.bin)
add_dependencies(rtl-unittest payload_bin bootrom_de0cv_hex)
target_compile_definitions(rtl-unittest PRIVATE
    DE0CV_PAYLOAD="${CMAKE_CURRENT_BINARY_DIR}/payload.bin")

verilate(rtl-unittest
    VERILATOR_ARGS ${VERILATOR_FLAGS}
        "-Gbootrom_init=\"${CMAKE_BINARY_DIR}/fpga/intel/de0-cv/bootrom/bootrom.hex\""
        -Gsdram_init_wait_ns=2000
    PREFIX VDE0CVBoot
    SOURCES
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
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/BitSync.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVADFF.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/MemSplit.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/BootROM.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/BootROMPort.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/AXILiteDecoder.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/AXILiteRegs.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/RXVCLINT.v
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/PLIC.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/DebugRegs.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/ConsoleUART.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/ps2/PS2Host.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/ps2/AltPS2.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/video/VGAScanout.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/sdram/SDRAMController.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/sdram/SDRAMFrontend.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/sdhci/SDHCI.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/sdhci/SDHCIRegs.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/sdhci/SDClockGen.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/sdhci/SDCmdEngine.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/sdhci/SDDataEngine.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/sdhci/SDDataFifo.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/sdhci/SDHCIDMA.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/intel/de0-cv/DE0CVSoC.sv
    INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl
    INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
    TOP_MODULE DE0CVSoC
    THREADS 1
    OPT_GLOBAL "-O3"
    TRACE_FST TRACE_STRUCTS)

verilate(rtl-unittest
         VERILATOR_ARGS ${VERILATOR_FLAGS}
         PREFIX VSDHCIWrapper
         SOURCES
         ${CMAKE_CURRENT_SOURCE_DIR}/fixtures/SDHCIWrapper.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/sdhci/SDHCI.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/sdhci/SDHCIRegs.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/sdhci/SDClockGen.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/sdhci/SDCmdEngine.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/sdhci/SDDataEngine.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/sdhci/SDDataFifo.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../fpga/common/sdhci/SDHCIDMA.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/BitSync.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVADFF.sv
         ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RXVDFF.sv
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures
         INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib
         TOP_MODULE SDHCIWrapper
         TRACE_FST TRACE_STRUCTS)
