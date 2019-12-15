file(READ "${PROJECT_SOURCE_DIR}/CMake/Yosys_sby.template" YOSYS_SBY_TEMPLATE)

function(ys_formal)
    set(options "")
    set(oneValueArgs TOP DEPTH SKIP)
    set(multiValueArgs SOURCES DEPENDS EXTRA_FILES DEFINES)
    cmake_parse_arguments(ys_formal "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    foreach(define ${ys_formal_DEFINES})
        string(APPEND ys_formal_DEFINE_LINES "read -define ${define}\n")
    endforeach(define)

    foreach(source ${ys_formal_SOURCES})
        list(APPEND SOURCE_ARGS --source=${source})
        string(APPEND ys_formal_SOURCE_LIST "${source} ")
        string(APPEND ys_formal_FILE_LIST "${source}\n")
        get_source_file_property(res ${source} COMPILE_FLAGS)
        if(NOT res STREQUAL "NOTFOUND")
            list(APPEND extra_compile_flags ${res})
        endif()
    endforeach(source)

    foreach(extra_file ${ys_formal_EXTRA_FILES})
        string(APPEND ys_formal_FILE_LIST "${extra_file}\n")
    endforeach(extra_file)

    string(CONFIGURE "${YOSYS_SBY_TEMPLATE}" YS_TEMPLATE)
    file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/${ys_formal_TOP}.sby" "${YS_TEMPLATE}")

    add_test(yosys-bmc-${ys_formal_TOP} sby -f ${CMAKE_CURRENT_BINARY_DIR}/${ys_formal_TOP}.sby bmc)
    add_test(yosys-cover-${ys_formal_TOP} sby -f ${CMAKE_CURRENT_BINARY_DIR}/${ys_formal_TOP}.sby cover)

endfunction()
