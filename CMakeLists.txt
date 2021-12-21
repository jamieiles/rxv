cmake_minimum_required(VERSION 3.11)
project(RXV C CXX ASM)
set(CMAKE_CONFIGURATION_TYPES "Release;Debug")

set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} "${CMAKE_SOURCE_DIR}/CMake/")

set(CMAKE_CXX_FLAGS "-std=c++2a ${CMAKE_CXX_FLAGS}")
set(CMAKE_CXX_FLAGS_DEBUG "-DDEBUG -ggdb3 -O0 ${CMAKE_CXX_FLAGS_DEBUG}")

include(ExternalProject)
include(CTest)

set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} "${CMAKE_SOURCE_DIR}/CMake/")

find_program(CCACHE_FOUND ccache)
if(CCACHE_FOUND)
    set_property(GLOBAL PROPERTY RULE_LAUNCH_COMPILE ccache)
    set_property(GLOBAL PROPERTY RULE_LAUNCH_LINK ccache)
endif(CCACHE_FOUND)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(UPDATE_DISCONNECTED true CACHE BOOL "Don't update external git repos during build")

add_subdirectory(tools)
add_subdirectory(vendor/googletest)
add_subdirectory(vendor/ELFIO)
add_subdirectory(verif/rtl)
add_subdirectory(simulator)
add_subdirectory(fpga/virtual)
