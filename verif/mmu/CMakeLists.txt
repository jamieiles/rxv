set(CMAKE_SYSTEM_NAME none)
set(CMAKE_SYSTEM_PROCESSOR riscv)
set(CMAKE_C_COMPILER riscv64-unknown-elf-gcc)
set(CMAKE_ASM_COMPILER riscv64-unknown-elf-gcc)

set(CMAKE_C_FLAGS "-Wall -Werror -ffreestanding -nostdlib -O2 -ggdb3 -std=gnu99 -mabi=ilp32 -march=rv32ima_zicsr")
set(CMAKE_ASM_FLAGS "-mabi=ilp32 -march=rv32ima_zicsr -ffreestanding -nostdlib")

add_executable(mmu-test entry.S mmu.c)
target_link_options(mmu-test PRIVATE "SHELL:-Wl,-N -Wl,--no-warn-rwx-segments -T${CMAKE_CURRENT_SOURCE_DIR}/mmu.x")

foreach(sim software rtl)
    add_test(NAME ${sim}-mmu
             COMMAND sh -c "rm -f mmu-${sim}.log; $<TARGET_FILE:rxv-simulator> ${sim} $<TARGET_FILE:mmu-test> --uart_log mmu-${sim}.log 0<>/dev/null; grep -q 'MMU TEST PASSED' mmu-${sim}.log")
    set_tests_properties(${sim}-mmu PROPERTIES TIMEOUT 300)
endforeach()
