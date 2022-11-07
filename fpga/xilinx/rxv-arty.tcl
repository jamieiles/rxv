set script_dir [file dirname [file normalize [info script]]]
set origin_dir "${script_dir}/../.."

create_project -in_memory -part xc7s50csga324-2 RXVArty

set_property source_mgmt_mode All [current_project]

add_files "${origin_dir}/_build/fpga/xilinx/bootrom/bootrom.mem"

read_verilog -sv "${origin_dir}/rtl/lib/RXV.svh"
set_property is_global_include true [get_files "${origin_dir}/rtl/lib/RXV.svh"]

read_verilog -sv "${origin_dir}/rtl/lib/RXVTypes.sv"
read_verilog -sv "${origin_dir}/rtl/lib/RXVTrace.sv"
read_verilog -sv "${origin_dir}/rtl/lib/RXVCSR.sv"
read_verilog -sv "${origin_dir}/rtl/lib/RXVMMU.sv"
read_verilog -sv "${origin_dir}/fpga/xilinx/AXIAdapter.sv"
read_verilog -sv "${origin_dir}/fpga/xilinx/RAMBE.sv"
read_verilog "${origin_dir}/fpga/xilinx/RXVCLINT.v"
read_verilog "${origin_dir}/fpga/xilinx/RXVCoreAXISynthTop.v"
read_verilog "${origin_dir}/fpga/xilinx/Top.v"
read_verilog -sv "${origin_dir}/rtl/RXVALU.sv"
read_verilog -sv "${origin_dir}/rtl/RXVBranchPredictor.sv"
read_verilog -sv "${origin_dir}/rtl/RXVCommitBuffer.sv"
read_verilog -sv "${origin_dir}/rtl/RXVCommitter.sv"
read_verilog -sv "${origin_dir}/rtl/RXVCore.sv"
read_verilog -sv "${origin_dir}/rtl/RXVCSRALU.sv"
read_verilog -sv "${origin_dir}/rtl/RXVCSRFile.sv"
read_verilog -sv "${origin_dir}/rtl/RXVDCacheArb.sv"
read_verilog -sv "${origin_dir}/rtl/RXVDCache.sv"
read_verilog -sv "${origin_dir}/rtl/RXVDecode.sv"
read_verilog -sv "${origin_dir}/rtl/RXVDivExec.sv"
read_verilog -sv "${origin_dir}/rtl/RXVDiv.sv"
read_verilog -sv "${origin_dir}/rtl/RXVEventCounter.sv"
read_verilog -sv "${origin_dir}/rtl/RXVFetch.sv"
read_verilog -sv "${origin_dir}/rtl/RXVICache.sv"
read_verilog -sv "${origin_dir}/rtl/RXVIntExec.sv"
read_verilog -sv "${origin_dir}/rtl/RXVLSU.sv"
read_verilog -sv "${origin_dir}/rtl/RXVMMUTop.sv"
read_verilog -sv "${origin_dir}/rtl/RXVMulExec.sv"
read_verilog -sv "${origin_dir}/rtl/RXVMul.sv"
read_verilog -sv "${origin_dir}/rtl/RXVPMP.sv"
read_verilog -sv "${origin_dir}/rtl/RXVPMU.sv"
read_verilog -sv "${origin_dir}/rtl/RXVPTWalker.sv"
read_verilog -sv "${origin_dir}/rtl/RXVRegisterAllocator.sv"
read_verilog -sv "${origin_dir}/rtl/RXVRegisterFileBanked.sv"
read_verilog -sv "${origin_dir}/rtl/RXVRegisterFileDFF.sv"
read_verilog -sv "${origin_dir}/rtl/RXVRegisterFile.sv"
read_verilog -sv "${origin_dir}/rtl/RXVRenameFile.sv"
read_verilog -sv "${origin_dir}/rtl/RXVScheduler.sv"
read_verilog -sv "${origin_dir}/rtl/RXVScoreboard.sv"
read_verilog -sv "${origin_dir}/rtl/RXVTLB.sv"
read_verilog -sv "${origin_dir}/rtl/lib/BitPLRU.sv"
read_verilog -sv "${origin_dir}/rtl/lib/BitSync.sv"
read_verilog -sv "${origin_dir}/rtl/lib/BusAdapter.sv"
read_verilog -sv "${origin_dir}/rtl/lib/DPRAM_formal.sv"
read_verilog -sv "${origin_dir}/rtl/lib/DPRAM.sv"
read_verilog -sv "${origin_dir}/rtl/lib/Fifo.sv"
read_verilog -sv "${origin_dir}/rtl/lib/MCP.sv"
read_verilog -sv "${origin_dir}/rtl/lib/MemInterface.sv"
read_verilog -sv "${origin_dir}/rtl/lib/OneHotDecode.sv"
read_verilog -sv "${origin_dir}/rtl/lib/OneHotEncode.sv"
read_verilog -sv "${origin_dir}/rtl/lib/PosedgeDetect.sv"
read_verilog -sv "${origin_dir}/rtl/lib/RAM_formal.sv"
read_verilog -sv "${origin_dir}/rtl/lib/RAM.sv"
read_verilog -sv "${origin_dir}/rtl/lib/RXVAssert.sv"
read_verilog -sv "${origin_dir}/rtl/lib/RXVCountdown.sv"
read_verilog -sv "${origin_dir}/rtl/lib/RXVDFFPipe.sv"
read_verilog -sv "${origin_dir}/rtl/lib/RXVADFF.sv"
read_verilog -sv "${origin_dir}/rtl/lib/RXVDFF.sv"
read_verilog -sv "${origin_dir}/rtl/lib/RXVTrace_cpp.svh"
read_verilog -sv "${origin_dir}/rtl/lib/StaticArbiter.sv"
read_verilog -sv "${origin_dir}/rtl/lib/SyncPulse.sv"
read_verilog -sv "${origin_dir}/rtl/lib/TLBPLRU.sv"
read_verilog -sv "${origin_dir}/rtl/lib/CacheRAM.sv"

source "${origin_dir}/fpga/xilinx/RXVArtyBD.tcl"

set_property source_mgmt_mode All [current_project]

read_xdc "${origin_dir}/fpga/xilinx/RXVArty.xdc"

generate_target all [get_files RXVArty.bd]

update_compile_order -fileset sources_1

read_verilog ./.gen/sources_1/bd/RXVArty/hdl/RXVArty_wrapper.v

synth_design -top Top -flatten_hierarchy rebuilt -bufg 12 -keep_equivalent_registers -fsm_extraction one_hot -retiming -resource_sharing off -directive PerformanceOptimized -control_set_opt_threshold auto -no_lc -verilog_define vivado=1 -verilog_define sg15E=1 -verilog_define den2048Mb=1

write_checkpoint -force post_synth
report_timing_summary -file post_synth_timing_summary.rpt
report_power -file post_synth_power.rpt

opt_design -directive ExploreWithRemap
opt_design -srl_remap_modes {{min_depth_ffs_to_srl 5}{max_depth_srl_to_ffs 8}}
power_opt_design
place_design -directive ExtraTimingOpt
phys_opt_design -directive AggressiveExplore
write_checkpoint -force post_place
report_timing_summary -file post_place_timing_summary.rpt

route_design -directive Explore
phys_opt_design -directive AggressiveExplore
write_checkpoint -force post_route
report_timing_summary -file post_route_timing_summary.rpt
report_timing -file post_route_timing.rpt -sort_by group -max_paths 100 -path_type summary
report_clock_utilization -file clock_util.rpt
report_utilization -file post_route_util.rpt
report_power -file post_route_power.rpt
report_drc -file post_imp_drc.rpt
report_qor_suggestions -file qor_suggestions.rpt

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
write_bitstream -force RXVArty.bit -bin_file

exit
