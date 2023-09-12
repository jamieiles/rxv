set(CMAKE_FIND_PACKAGE_SORT_ORDER NATURAL)
set(CMAKE_FIND_PACKAGE_SORT_DIRECTION DEC)

set(Boost_NO_BOOST_CMAKE ON)
set(Boost_USE_MULTITHREADED TRUE)
find_package(FlatBuffers REQUIRED NAMES FlatBuffers Flatbuffers)
find_package(Boost 1.71.0 COMPONENTS program_options REQUIRED)
find_package(Clang REQUIRED)
include_directories(SYSTEM ${LLVM_INCLUDE_DIRS})
include_directories(SYSTEM ${Boost_INCLUDE_DIRS})
include_directories(${CMAKE_CURRENT_BINARY_DIR})
include_directories(${CMAKE_CURRENT_BINARY_DIR}/../simulator)
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/../simulator/include)

add_custom_command(OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/Trace_generated.h
                   COMMAND flatc --cpp ${CMAKE_CURRENT_SOURCE_DIR}/Trace.fbs
                   DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/Trace.fbs)
add_custom_target(gen_trace_h DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/Trace_generated.h)
add_executable(trace-decode
               TraceDecode.cpp)
target_link_libraries(trace-decode
                      ${Boost_LIBRARIES}
                      ${ZLIB_LIBRARIES}
                      clangTooling
                      fmt
                      elfio::elfio)
add_executable(make-core
               MakeCore.cpp)
target_link_libraries(make-core
                      ${Boost_LIBRARIES}
                      ${ZLIB_LIBRARIES}
                      fmt
                      elfio::elfio)