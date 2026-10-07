# Copyright 2026 Jamie Iles
# SPDX-License-Identifier: Apache-2.0
#
# Build the DE0-CV bitstream from an empty directory, e.g.
#
#   mkdir -p _build/fpga/intel/de0-cv/hw && cd _build/fpga/intel/de0-cv/hw
#   quartus_sh -t ../../../../../fpga/intel/de0-cv/de0cv.tcl
#
# The boot ROM is initialised from _build/fpga/intel/de0-cv/bootrom/bootrom.hex,
# built in the rxv-dev container.

package require ::quartus::project
package require ::quartus::flow

set script_dir [file dirname [file normalize [info script]]]
set origin_dir [file normalize "${script_dir}/../../.."]

project_new -overwrite DE0CVTop

set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE 5CEBA4F23C7
set_global_assignment -name TOP_LEVEL_ENTITY DE0CVTop
set_global_assignment -name NUM_PARALLEL_PROCESSORS ALL
set_global_assignment -name SEARCH_PATH "${origin_dir}/rtl/lib"
set_global_assignment -name SDC_FILE "${script_dir}/DE0CVTop.sdc"
set_global_assignment -name STRATIX_DEVICE_IO_STANDARD "3.3-V LVTTL"
set_global_assignment -name OPTIMIZATION_MODE "AGGRESSIVE PERFORMANCE"
set_global_assignment -name PHYSICAL_SYNTHESIS_COMBO_LOGIC ON
set_global_assignment -name PHYSICAL_SYNTHESIS_REGISTER_RETIMING ON
set_global_assignment -name PHYSICAL_SYNTHESIS_REGISTER_DUPLICATION ON
set_global_assignment -name ROUTER_TIMING_OPTIMIZATION_LEVEL MAXIMUM
set_global_assignment -name TIMEQUEST_MULTICORNER_ANALYSIS ON
set_global_assignment -name ON_CHIP_BITSTREAM_DECOMPRESSION OFF
set_global_assignment -name GENERATE_RBF_FILE ON

set bootrom_hex "${origin_dir}/_build/fpga/intel/de0-cv/bootrom/bootrom.hex"
if {[file exists $bootrom_hex]} {
    set_parameter -name bootrom_init $bootrom_hex
} else {
    puts "WARNING: ${bootrom_hex} not found, the boot ROM will be empty"
}

# Sources: the core packages first
foreach f {lib/RXVTypes.sv lib/RXVTrace.sv lib/RXVCSR.sv lib/RXVMMU.sv} {
    set_global_assignment -name SYSTEMVERILOG_FILE "${origin_dir}/rtl/${f}"
}
foreach f [concat [glob ${origin_dir}/rtl/RXV*.sv] [glob ${origin_dir}/rtl/lib/*.sv]] {
    set name [file tail $f]
    if {[lsearch {RXVTypes.sv RXVTrace.sv RXVCSR.sv RXVMMU.sv RAMBE.sv} $name] >= 0} { continue }
    if {[string match "*_formal.sv" $name]} { continue }
    set_global_assignment -name SYSTEMVERILOG_FILE $f
}
# The byte enable RAM for the caches as an altsyncram
set_global_assignment -name SYSTEMVERILOG_FILE "${origin_dir}/fpga/virtual/RAMBE.sv"
foreach f [concat [glob ${origin_dir}/fpga/common/*.sv] [glob ${origin_dir}/fpga/common/sdram/*.sv] \
               [glob ${origin_dir}/fpga/common/ps2/*.sv] [glob ${origin_dir}/fpga/common/video/*.sv] \
               [glob ${origin_dir}/fpga/common/sdhci/SD*.sv]] {
    set_global_assignment -name SYSTEMVERILOG_FILE $f
}
set_global_assignment -name VERILOG_FILE "${origin_dir}/fpga/common/RXVCLINT.v"
set_global_assignment -name VERILOG_FILE "${script_dir}/DE0CVPLL.v"
set_global_assignment -name SYSTEMVERILOG_FILE "${script_dir}/DE0CVSoC.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "${script_dir}/DE0CVTop.sv"

# ------------------------------------------------------------------
# Pins
# ------------------------------------------------------------------
proc pins {names locations} {
    foreach n $names l $locations { set_location_assignment PIN_$l -to $n }
}
proc bus {name locations} {
    set i 0
    foreach l $locations { set_location_assignment PIN_$l -to "${name}\[$i\]"; incr i }
}

pins {CLOCK_50 RESET_N} {M9 P22}

pins {DRAM_CLK DRAM_CKE DRAM_CS_N DRAM_RAS_N DRAM_CAS_N DRAM_WE_N DRAM_LDQM DRAM_UDQM} \
     {AB11 R6 U6 AB6 V6 AB5 U12 N8}
bus DRAM_BA {T7 AB7}
bus DRAM_ADDR {W8 T8 U11 Y10 N6 AB10 P12 P7 P8 R5 U8 P6 R7}
bus DRAM_DQ {Y9 T10 R9 Y11 R10 R11 R12 AA12 AA9 AB8 AA8 AA7 V10 V9 U10 T9}

# microSD.  DAT1 and DAT2 are from the DE0-CV manual, the other designs on
# this board have used the card in SPI mode.
pins {SD_CLK SD_CMD} {H11 B11}
bus SD_DATA {K9 D12 E12 C11}

pins {PS2_CLK PS2_DAT PS2_CLK2 PS2_DAT2} {D3 G2 E2 G1}

bus VGA_R {A9 B10 C9 A5}
bus VGA_G {L7 K7 J7 J8}
bus VGA_B {B6 B7 A8 A7}
pins {VGA_HS VGA_VS} {H8 G8}

bus LEDR {AA2 AA1 W2 Y3 N2 N1 U2 U1 L2 L1}
bus HEX0 {U21 V21 W22 W21 Y22 Y21 AA22}
bus HEX1 {AA20 AB20 AA19 AA18 AB18 AA17 U22}
bus HEX2 {Y19 AB17 AA10 Y14 V14 AB22 AB21}
bus HEX3 {Y16 W16 Y17 V16 U17 V18 V19}
bus HEX4 {U20 Y20 V20 U16 U15 Y15 P9}
bus HEX5 {N9 M8 T14 P14 C1 C2 W19}

# ------------------------------------------------------------------
# I/O
# ------------------------------------------------------------------
foreach p {DRAM_CKE DRAM_CS_N DRAM_RAS_N DRAM_CAS_N DRAM_WE_N DRAM_LDQM DRAM_UDQM DRAM_BA DRAM_ADDR DRAM_DQ} {
    set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to $p
    set_instance_assignment -name CURRENT_STRENGTH_NEW "MAXIMUM CURRENT" -to $p
}
set_instance_assignment -name FAST_OUTPUT_ENABLE_REGISTER ON -to DRAM_DQ
set_instance_assignment -name FAST_INPUT_REGISTER ON -to DRAM_DQ
set_instance_assignment -name CURRENT_STRENGTH_NEW "MAXIMUM CURRENT" -to DRAM_CLK

# The SDHCI registers are packed into the I/O cells, as on the Arty.
foreach p {SD_CLK SD_CMD SD_DATA} {
    set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to $p
}
foreach p {SD_CMD SD_DATA} {
    set_instance_assignment -name FAST_OUTPUT_ENABLE_REGISTER ON -to $p
    set_instance_assignment -name FAST_INPUT_REGISTER ON -to $p
    set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to $p
}

foreach p {PS2_CLK PS2_DAT PS2_CLK2 PS2_DAT2} {
    set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to $p
}

export_assignments

execute_flow -compile

project_close
