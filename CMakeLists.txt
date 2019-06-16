cmake_minimum_required(VERSION 3.0.2)
include(ExternalProject)
include(CTest)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(UPDATE_DISCONNECTED true CACHE BOOL "Don't update external git repos during build")

add_subdirectory(simulator)