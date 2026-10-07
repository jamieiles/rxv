# Copyright 2026 Jamie Iles
# SPDX-License-Identifier: Apache-2.0
#
# Sample the DE0-CV debug probe over JTAG:
#
#   quartus_stp -t fpga/intel/de0-cv/debug-probe.tcl [samples]
#
# Each sample is the PC in execute, the privilege level (0 U, 1 S, 3 M),
# the interrupt lines, the last device bus address, the bus request
# counts, mcause, mepc, mtval and the PC of the last call.
set samples [expr {$argc > 0 ? [lindex $argv 0] : 8}]

set hw [lindex [get_hardware_names] 0]
set dev [lindex [get_device_names -hardware_name $hw] 0]
set idx -1
foreach inst [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw] {
    if {[lindex $inst 3] eq "RXV"} { set idx [lindex $inst 0] }
}
if {$idx < 0} { error "no RXV probe instance, is the bitstream loaded?" }
start_insystem_source_probe -device_name $dev -hardware_name $hw

for {set i 0} {$i < $samples} {incr i} {
    set v [read_probe_data -instance_index $idx -value_in_hex]
    set v [format %064s $v]
    scan [string range $v 0 7] %x call
    scan [string range $v 8 15] %x mtval
    scan [string range $v 16 23] %x mepc
    scan [string range $v 24 31] %x mcause
    scan [string range $v 32 35] %x d_req
    scan [string range $v 36 39] %x i_req
    scan [string range $v 40 47] %x dev
    scan [string range $v 48 55] %x irqs
    scan [string range $v 56 63] %x pcpriv
    puts [format "pc %08x priv %d irqs %02x dev %08x ireq %5d dreq %5d mcause %08x mepc %08x mtval %08x call %08x" \
        [expr {$pcpriv & ~3}] [expr {$pcpriv & 3}] $irqs $dev $i_req $d_req $mcause $mepc $mtval $call]
    after 100
}

end_insystem_source_probe
