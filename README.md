RISC-V soft core.  Copyright Jamie Iles 2019-2022.

Proprietary and confidential.

Building OpenSBI:

make PLATFORM_RISCV_ABI=ilp32 PLATFORM_RISCV_ISA=rv32ima \
    PLATFORM_RISCV_XLEN=32 PLATFORM=generic CROSS_COMPILE=riscv64-unknown-elf- \
    FW_PAYLOAD_PATH=<PATH_TO_LINUX_IMAGE> \
    FW_FDT_PATH=<PATH_TO_DTB>
