set(CMAKE_SYSTEM_NAME none)
set(CMAKE_SYSTEM_PROCESSOR riscv)
set(CMAKE_C_COMPILER riscv64-unknown-elf-gcc)
set(CMAKE_ASM_COMPILER riscv64-unknown-elf-gcc)

set(CMAKE_C_FLAGS "-Wall -Werror -ffreestanding -nostdlib -O2 -ggdb3 -std=gnu99 -mabi=ilp32 -march=rv32ima")
set(CMAKE_ASM_FLAGS "-I${CMAKE_CURRENT_SOURCE_DIR} -mabi=ilp32 -march=rv32ima -ffreestanding -nostdlib")

add_executable(sim-bootrom entry.S)
target_link_options(sim-bootrom PRIVATE "SHELL:-T${CMAKE_CURRENT_SOURCE_DIR}/bootrom.x")

add_custom_command(OUTPUT sim-bootrom.bin
		   COMMAND riscv64-unknown-elf-objcopy sim-bootrom sim-bootrom.bin -O binary
		   DEPENDS sim-bootrom)
