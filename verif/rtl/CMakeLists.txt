include(Verilator)

set_source_files_properties(${VERILATED_DPI_CPP} PROPERTIES COMPILE_FLAGS "-Wno-unused-parameter -Wno-error")
set_source_files_properties(${VERILATED_CPP} PROPERTIES COMPILE_FLAGS "-Wno-unused-parameter -Wno-error")
add_library(verilator SHARED ${VERILATOR_LIB_SOURCES})

verilate(TOPLEVEL RegFile
         VERILOG_SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/../../rtl/RegFile.sv)

add_executable(rtl-unittest
               TestRegisterFile.cpp
               main.cpp)
target_link_libraries(rtl-unittest
                      gtest
                      verilator
                      VRegFile)
add_test(rtl-unittest rtl-unittest)