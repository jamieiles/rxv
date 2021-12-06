find_package(Quartus REQUIRED)
include(Quartus)
include(ProcessorCount)

ProcessorCount(NPROCS)

configure_file(RXVCoreSynthTop.qsf RXVCoreSynthTop.qsf)
configure_file(RXVCoreSynthTop.srf RXVCoreSynthTop.srf)

set(CORE_SOURCES
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
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVICache.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVIntExec.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVRegisterAllocator.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVRegisterFile.sv
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RXVRenameFile.sv
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
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/lib/RAMBE.sv)
set(FPGA_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/SysPLL.v
    ${CMAKE_CURRENT_SOURCE_DIR}/RXVCoreSynthTop.sv)

set(ALL_SOURCES ${CORE_SOURCES} ${FPGA_SOURCES})

add_fpga(PROJECT RXVCoreSynthTop
         FAMILY "Cyclone V"
         PART "5CEFA2F23C6"
         SOURCES ${ALL_SOURCES})

add_custom_target(virtual-fpga DEPENDS RXVCoreSynthTop.sta.rpt)
