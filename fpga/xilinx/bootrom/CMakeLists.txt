set(CMAKE_SYSTEM_NAME none)
set(CMAKE_SYSTEM_PROCESSOR riscv)
set(CMAKE_C_COMPILER riscv64-unknown-elf-gcc)
set(CMAKE_ASM_COMPILER riscv64-unknown-elf-gcc)

set(BOOTROM_COMMON ${CMAKE_CURRENT_SOURCE_DIR}/../../common/bootrom)

set(CMAKE_C_FLAGS "-Wall -Werror -ffreestanding -nostdlib -O2 -ggdb3 -std=gnu99 -mabi=ilp32 -march=rv32ima_zifencei_zicsr")
set(CMAKE_ASM_FLAGS "-I${BOOTROM_COMMON} -mabi=ilp32 -march=rv32ima")

add_executable(bootrom
	       ${BOOTROM_COMMON}/disk.c
	       ${BOOTROM_COMMON}/fat.c
	       ${BOOTROM_COMMON}/entry.S
	       ${BOOTROM_COMMON}/root.c
	       ${BOOTROM_COMMON}/printk.c
	       ${BOOTROM_COMMON}/sdhci.c
	       ${BOOTROM_COMMON}/tinflate.c
	       ${BOOTROM_COMMON}/progress.c
	       ${BOOTROM_COMMON}/string.c
	       uart.c)
target_include_directories(bootrom PRIVATE ${CMAKE_CURRENT_SOURCE_DIR} ${BOOTROM_COMMON})
target_link_options(bootrom PRIVATE "SHELL:-T${CMAKE_CURRENT_SOURCE_DIR}/bootrom.x")

add_custom_command(OUTPUT bootrom.bin
		   COMMAND riscv64-unknown-elf-objcopy bootrom bootrom.bin -O binary
		   DEPENDS bootrom)
add_custom_command(OUTPUT bootrom.mem
		   COMMAND xxd -e -c 4 -g4 ${CMAKE_CURRENT_BINARY_DIR}/bootrom.bin | awk \'{print $$2}\' > ${CMAKE_CURRENT_BINARY_DIR}/bootrom.mem
		   DEPENDS bootrom.bin)
add_custom_target(bootrom_mem ALL
		  DEPENDS bootrom.mem)
