cmake_minimum_required(VERSION 2.8)
find_package(Boost COMPONENTS program_options REQUIRED)
include_directories(${Boost_INCLUDE_DIR})

add_executable(rxv-simulator
               Simulator.cpp)
target_link_libraries(rxv-simulator
                      ${Boost_LIBRARIES})
