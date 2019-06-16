cmake_minimum_required(VERSION 2.8)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

find_package(Boost COMPONENTS program_options REQUIRED)
include_directories(${Boost_INCLUDE_DIR})

add_executable(rxv-simulator
               Simulator.cpp
               ComplianceTest.h
               RXVSim.cpp
               RXVSim.h
               RiscVELF.cpp
               RiscVELF.h)
target_link_libraries(rxv-simulator
                      ${Boost_LIBRARIES})
