# Copyright 2026 Jamie Iles
# SPDX-License-Identifier: Apache-2.0
#
# Print the DE0-CV console UART's output over JTAG:
#
#   quartus_stp -t fpga/intel/de0-cv/jtag-console.tcl [follow]
#
# Prints what is in the 8KB buffer, then with "follow" keeps printing new
# output until interrupted.
set follow [expr {$argc > 0 && [lindex $argv 0] eq "follow"}]
set buf_size 8192

set hw [lindex [get_hardware_names] 0]
set dev [lindex [get_device_names -hardware_name $hw] 0]
set idx -1
foreach inst [get_insystem_source_probe_instance_info -device_name $dev -hardware_name $hw] {
    if {[lindex $inst 3] eq "CON"} { set idx [lindex $inst 0] }
}
if {$idx < 0} { error "no CON probe instance, is the bitstream loaded?" }
start_insystem_source_probe -device_name $dev -hardware_name $hw

# The byte count and the 8 bytes at line addr of the buffer
proc read_line {addr} {
    global idx
    write_source_data -instance_index $idx -value [format %03x $addr] -value_in_hex
    set v [format %024s [read_probe_data -instance_index $idx -value_in_hex]]
    scan [string range $v 0 7] %x count
    set bytes {}
    for {set b 0} {$b < 8} {incr b} {
        scan [string range $v [expr {22 - 2 * $b}] [expr {23 - 2 * $b}]] %x c
        lappend bytes $c
    }
    return [list $count $bytes]
}

proc print_range {from to} {
    global buf_size
    set out ""
    for {set pos [expr {$from & ~7}]} {$pos < $to} {incr pos 8} {
        set bytes [lindex [read_line [expr {($pos % $buf_size) / 8}]] 1]
        for {set b 0} {$b < 8} {incr b} {
            set p [expr {$pos + $b}]
            if {$p < $from || $p >= $to} { continue }
            set c [lindex $bytes $b]
            if {$c == 10 || ($c >= 32 && $c < 127)} { append out [format %c $c] }
        }
    }
    puts -nonewline $out
    flush stdout
}

set count [lindex [read_line 0] 0]
set from [expr {$count > $buf_size ? $count - $buf_size : 0}]
print_range $from $count

while {$follow} {
    after 250
    set now [lindex [read_line 0] 0]
    if {$now != $count} {
        set from [expr {$now - $count > $buf_size ? $now - $buf_size : $count}]
        print_range $from $now
        set count $now
    }
}

end_insystem_source_probe
