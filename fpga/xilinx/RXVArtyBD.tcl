
################################################################
# This is a generated script based on design: RXVArty
#
# Though there are limitations about the generated script,
# the main purpose of this utility is to make learning
# IP Integrator Tcl commands easier.
################################################################

namespace eval _tcl {
proc get_script_folder {} {
   set script_path [file normalize [info script]]
   set script_folder [file dirname $script_path]
   return $script_folder
}
}
variable script_folder
set script_folder [_tcl::get_script_folder]

################################################################
# START
################################################################

# To test this script, run the following commands from Vivado Tcl console:
# source RXVArty_script.tcl


# The design that will be created by this Tcl script contains the following 
# module references:
# RXVCLINT, RXVCoreAXISynthTop

# Please add the sources of those modules before sourcing this Tcl script.

# If there is no project opened, this script will create a
# project, but make sure you do not have an existing project
# <./myproj/project_1.xpr> in the current working folder.

set list_projs [get_projects -quiet]
if { $list_projs eq "" } {
   create_project project_1 myproj -part xc7s50csga324-2
}


# CHANGE DESIGN NAME HERE
variable design_name
set design_name RXVArty

# If you do not already have an existing IP Integrator design open,
# you can create a design using the following command:
#    create_bd_design $design_name

# Creating design if needed
set errMsg ""
set nRet 0

set cur_design [current_bd_design -quiet]
set list_cells [get_bd_cells -quiet]

if { ${design_name} eq "" } {
   # USE CASES:
   #    1) Design_name not set

   set errMsg "Please set the variable <design_name> to a non-empty value."
   set nRet 1

} elseif { ${cur_design} ne "" && ${list_cells} eq "" } {
   # USE CASES:
   #    2): Current design opened AND is empty AND names same.
   #    3): Current design opened AND is empty AND names diff; design_name NOT in project.
   #    4): Current design opened AND is empty AND names diff; design_name exists in project.

   if { $cur_design ne $design_name } {
      common::send_gid_msg -ssname BD::TCL -id 2001 -severity "INFO" "Changing value of <design_name> from <$design_name> to <$cur_design> since current design is empty."
      set design_name [get_property NAME $cur_design]
   }
   common::send_gid_msg -ssname BD::TCL -id 2002 -severity "INFO" "Constructing design in IPI design <$cur_design>..."

} elseif { ${cur_design} ne "" && $list_cells ne "" && $cur_design eq $design_name } {
   # USE CASES:
   #    5) Current design opened AND has components AND same names.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 1
} elseif { [get_files -quiet ${design_name}.bd] ne "" } {
   # USE CASES: 
   #    6) Current opened design, has components, but diff names, design_name exists in project.
   #    7) No opened design, design_name exists in project.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 2

} else {
   # USE CASES:
   #    8) No opened design, design_name not in project.
   #    9) Current opened design, has components, but diff names, design_name not in project.

   common::send_gid_msg -ssname BD::TCL -id 2003 -severity "INFO" "Currently there is no design <$design_name> in project, so creating one..."

   create_bd_design $design_name

   common::send_gid_msg -ssname BD::TCL -id 2004 -severity "INFO" "Making design <$design_name> as current_bd_design."
   current_bd_design $design_name

}

common::send_gid_msg -ssname BD::TCL -id 2005 -severity "INFO" "Currently the variable <design_name> is equal to \"$design_name\"."

if { $nRet != 0 } {
   catch {common::send_gid_msg -ssname BD::TCL -id 2006 -severity "ERROR" $errMsg}
   return $nRet
}

set bCheckIPsPassed 1
##################################################################
# CHECK IPs
##################################################################
set bCheckIPs 1
if { $bCheckIPs == 1 } {
   set list_check_ips "\ 
xilinx.com:ip:axi_intc:4.1\
xilinx.com:ip:axi_quad_spi:3.2\
xilinx.com:ip:axi_uart16550:2.0\
xilinx.com:ip:axi_bram_ctrl:4.1\
xilinx.com:ip:proc_sys_reset:5.0\
xilinx.com:ip:smartconnect:1.0\
xilinx.com:ip:xlconcat:2.1\
"

   set list_ips_missing ""
   common::send_gid_msg -ssname BD::TCL -id 2011 -severity "INFO" "Checking if the following IPs exist in the project's IP catalog: $list_check_ips ."

   foreach ip_vlnv $list_check_ips {
      set ip_obj [get_ipdefs -all $ip_vlnv]
      if { $ip_obj eq "" } {
         lappend list_ips_missing $ip_vlnv
      }
   }

   if { $list_ips_missing ne "" } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2012 -severity "ERROR" "The following IPs are not found in the IP Catalog:\n  $list_ips_missing\n\nResolution: Please add the repository containing the IP(s) to the project." }
      set bCheckIPsPassed 0
   }

}

##################################################################
# CHECK Modules
##################################################################
set bCheckModules 1
if { $bCheckModules == 1 } {
   set list_check_mods "\ 
RXVCLINT\
RXVCoreAXISynthTop\
"

   set list_mods_missing ""
   common::send_gid_msg -ssname BD::TCL -id 2020 -severity "INFO" "Checking if the following modules exist in the project's sources: $list_check_mods ."

   foreach mod_vlnv $list_check_mods {
      if { [can_resolve_reference $mod_vlnv] == 0 } {
         lappend list_mods_missing $mod_vlnv
      }
   }

   if { $list_mods_missing ne "" } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2021 -severity "ERROR" "The following module(s) are not found in the project: $list_mods_missing" }
      common::send_gid_msg -ssname BD::TCL -id 2022 -severity "INFO" "Please add source files for the missing module(s) above."
      set bCheckIPsPassed 0
   }
}

if { $bCheckIPsPassed != 1 } {
  common::send_gid_msg -ssname BD::TCL -id 2023 -severity "WARNING" "Will not continue with creation of design due to the error(s) above."
  return 3
}





##################################################################
# DESIGN PROCs
##################################################################



# Procedure to create entire design; Provide argument to make
# procedure reusable. If parentCell is "", will use root.
proc create_root_design { parentCell } {

  variable script_folder
  variable design_name

  if { $parentCell eq "" } {
     set parentCell [get_bd_cells /]
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj


  # Create interface ports
  set bootrom_bram [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:bram_rtl:1.0 bootrom_bram ]
  set_property -dict [ list \
   CONFIG.MASTER_TYPE {BRAM_CTRL} \
   CONFIG.READ_WRITE_MODE {READ_WRITE} \
   ] $bootrom_bram

  set uart_rtl_0 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:uart_rtl:1.0 uart_rtl_0 ]


  # Create ports
  # The DDR3 controller is outside of the block design (native MIG interface)
  # and provides the system clock and calibration status.
  set ui_clk [ create_bd_port -dir I -type clk -freq_hz 81247969 ui_clk ]
  set clint_refclk [ create_bd_port -dir I -type clk -freq_hz 10140625 clint_refclk ]
  set ddr_ready [ create_bd_port -dir I ddr_ready ]
  set ddr_calib_complete [ create_bd_port -dir I ddr_calib_complete ]
  set ddr_app_addr [ create_bd_port -dir O -from 27 -to 0 ddr_app_addr ]
  set ddr_app_cmd [ create_bd_port -dir O -from 2 -to 0 ddr_app_cmd ]
  set ddr_app_en [ create_bd_port -dir O ddr_app_en ]
  set ddr_app_rdy [ create_bd_port -dir I ddr_app_rdy ]
  set ddr_app_wdf_data [ create_bd_port -dir O -from 127 -to 0 ddr_app_wdf_data ]
  set ddr_app_wdf_mask [ create_bd_port -dir O -from 15 -to 0 ddr_app_wdf_mask ]
  set ddr_app_wdf_wren [ create_bd_port -dir O ddr_app_wdf_wren ]
  set ddr_app_wdf_end [ create_bd_port -dir O ddr_app_wdf_end ]
  set ddr_app_wdf_rdy [ create_bd_port -dir I ddr_app_wdf_rdy ]
  set ddr_app_rd_data [ create_bd_port -dir I -from 127 -to 0 ddr_app_rd_data ]
  set ddr_app_rd_data_valid [ create_bd_port -dir I ddr_app_rd_data_valid ]
  set ddr_app_rd_data_end [ create_bd_port -dir I ddr_app_rd_data_end ]
  set eth_int [ create_bd_port -dir I -type intr eth_int ]
  set_property -dict [ list \
   CONFIG.SENSITIVITY {EDGE_FALLING} \
 ] $eth_int
  set reset_rtl_0 [ create_bd_port -dir I -type rst reset_rtl_0 ]
  set_property -dict [ list \
   CONFIG.POLARITY {ACTIVE_HIGH} \
 ] $reset_rtl_0
  set spi_miso [ create_bd_port -dir I -type data spi_miso ]
  set spi_mosi [ create_bd_port -dir O -type data spi_mosi ]
  set spi_ncs [ create_bd_port -dir O -from 1 -to 0 spi_ncs ]
  set spi_sck [ create_bd_port -dir O -type clk spi_sck ]
  set mmio_rst [ create_bd_port -dir O -type data mmio_rst ]

  # Create instance: RXVCLINT_0, and set properties
  set block_name RXVCLINT
  set block_cell_name RXVCLINT_0
  if { [catch {set RXVCLINT_0 [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $RXVCLINT_0 eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: RXVCoreAXISynthTop_0, and set properties
  set block_name RXVCoreAXISynthTop
  set block_cell_name RXVCoreAXISynthTop_0
  if { [catch {set RXVCoreAXISynthTop_0 [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $RXVCoreAXISynthTop_0 eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: axi_intc_0, and set properties
  set axi_intc_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_intc:4.1 axi_intc_0 ]
  set_property -dict [ list \
   CONFIG.C_IRQ_CONNECTION {1} \
 ] $axi_intc_0

  # Create instance: axi_quad_spi_0, and set properties
  set axi_quad_spi_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_quad_spi:3.2 axi_quad_spi_0 ]
  set_property -dict [ list \
   CONFIG.C_BYTE_LEVEL_INTERRUPT_EN {0} \
   CONFIG.C_FIFO_DEPTH {256} \
   CONFIG.C_NUM_SS_BITS {2} \
   CONFIG.C_NUM_TRANSFER_BITS {8} \
   CONFIG.C_SCK_RATIO {4} \
   CONFIG.C_SPI_MODE {0} \
   CONFIG.C_TYPE_OF_AXI4_INTERFACE {0} \
   CONFIG.C_USE_STARTUP {0} \
   CONFIG.C_USE_STARTUP_INT {0} \
   CONFIG.C_XIP_MODE {0} \
   CONFIG.Multiples16 {1} \
 ] $axi_quad_spi_0

  # Create instance: axi_uart16550_0, and set properties
  set axi_uart16550_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_uart16550:2.0 axi_uart16550_0 ]

  # Create instance: bootrom_ctrl, and set properties
  set bootrom_ctrl [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 bootrom_ctrl ]
  set_property -dict [ list \
   CONFIG.DATA_WIDTH {32} \
   CONFIG.SINGLE_PORT_BRAM {1} \
 ] $bootrom_ctrl

  # Create instance: rst_clk_wiz_100M, and set properties
  set rst_clk_wiz_100M [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_clk_wiz_100M ]

  # Create instance: smartconnect_0, and set properties
  set smartconnect_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_0 ]
  set_property -dict [ list \
   CONFIG.ADVANCED_PROPERTIES {\
     __view__ {functional { S01_Entry { SUPPORTS_WRAP 0 } S00_Buffer { AR_SIZE 32\
AW_SIZE 32 B_SIZE 32 R_SIZE 32 W_SIZE 32 } M01_Buffer { AR_SIZE 32\
AW_SIZE 32 B_SIZE 32 R_SIZE 32 W_SIZE 32 } S01_Buffer { AR_SIZE 32\
AW_SIZE 32 B_SIZE 32 R_SIZE 32 W_SIZE 32 } M00_Buffer { AR_SIZE 32\
AW_SIZE 32 B_SIZE 32 R_SIZE 32 W_SIZE 32 } S00_Entry { SUPPORTS_WRAP 0\
} }}\
   } \
   CONFIG.NUM_MI {5} \
 ] $smartconnect_0

 set_property -dict [ list CONFIG.ADVANCED_PROPERTIES { __experimental_features__ {disable_low_area_mode 1 }} ] [get_bd_cells smartconnect_0]

  # Create instance: xlconcat_0, and set properties
  set xlconcat_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 xlconcat_0 ]
  set_property -dict [ list \
   CONFIG.NUM_PORTS {3} \
 ] $xlconcat_0

  # Create interface connections
  connect_bd_intf_net -intf_net RXVCoreAXISynthTop_0_m_d_axi [get_bd_intf_pins RXVCoreAXISynthTop_0/m_d_axi] [get_bd_intf_pins smartconnect_0/S00_AXI]
  connect_bd_intf_net -intf_net RXVCoreAXISynthTop_0_m_i_axi [get_bd_intf_pins RXVCoreAXISynthTop_0/m_i_axi] [get_bd_intf_pins smartconnect_0/S01_AXI]
  connect_bd_intf_net -intf_net axi_uart16550_0_UART [get_bd_intf_ports uart_rtl_0] [get_bd_intf_pins axi_uart16550_0/UART]
  connect_bd_intf_net -intf_net bootrom_ctrl_BRAM_PORTA [get_bd_intf_ports bootrom_bram] [get_bd_intf_pins bootrom_ctrl/BRAM_PORTA]
  connect_bd_intf_net -intf_net smartconnect_0_M00_AXI [get_bd_intf_pins axi_uart16550_0/S_AXI] [get_bd_intf_pins smartconnect_0/M00_AXI]
  connect_bd_intf_net -intf_net smartconnect_0_M01_AXI [get_bd_intf_pins bootrom_ctrl/S_AXI] [get_bd_intf_pins smartconnect_0/M01_AXI]
  connect_bd_intf_net -intf_net smartconnect_0_M02_AXI [get_bd_intf_pins axi_quad_spi_0/AXI_LITE] [get_bd_intf_pins smartconnect_0/M02_AXI]
  connect_bd_intf_net -intf_net smartconnect_0_M03_AXI [get_bd_intf_pins RXVCLINT_0/s_axi] [get_bd_intf_pins smartconnect_0/M03_AXI]
  connect_bd_intf_net -intf_net smartconnect_0_M04_AXI [get_bd_intf_pins axi_intc_0/s_axi] [get_bd_intf_pins smartconnect_0/M04_AXI]

  # Create port connections
  connect_bd_net -net RXVCLINT_0_mtime [get_bd_pins RXVCLINT_0/mtime] [get_bd_pins RXVCoreAXISynthTop_0/mtime]
  connect_bd_net -net RXVCLINT_0_mtime_irq [get_bd_pins RXVCLINT_0/mtime_irq] [get_bd_pins RXVCoreAXISynthTop_0/mtime_irq]
  connect_bd_net -net axi_intc_0_irq [get_bd_pins RXVCoreAXISynthTop_0/ext_irq] [get_bd_pins axi_intc_0/irq]
  connect_bd_net -net axi_quad_spi_0_io0_o [get_bd_ports spi_mosi] [get_bd_pins axi_quad_spi_0/io0_o]
  connect_bd_net -net axi_quad_spi_0_ip2intc_irpt [get_bd_pins axi_quad_spi_0/ip2intc_irpt] [get_bd_pins xlconcat_0/In0]
  connect_bd_net -net axi_quad_spi_0_sck_o [get_bd_ports spi_sck] [get_bd_pins axi_quad_spi_0/sck_o]
  connect_bd_net -net axi_quad_spi_0_ss_o [get_bd_ports spi_ncs] [get_bd_pins axi_quad_spi_0/ss_o]
  connect_bd_net -net axi_uart16550_0_ip2intc_irpt [get_bd_pins axi_uart16550_0/ip2intc_irpt] [get_bd_pins xlconcat_0/In1]
  connect_bd_net -net eth_int_1 [get_bd_ports eth_int] [get_bd_pins xlconcat_0/In2]
  connect_bd_net -net clint_refclk_1 [get_bd_ports clint_refclk] [get_bd_pins RXVCLINT_0/refclk]
  connect_bd_net -net ui_clk_1 [get_bd_ports ui_clk] [get_bd_pins RXVCLINT_0/s_axi_aclk] [get_bd_pins RXVCoreAXISynthTop_0/clk] [get_bd_pins axi_intc_0/s_axi_aclk] [get_bd_pins axi_quad_spi_0/ext_spi_clk] [get_bd_pins axi_quad_spi_0/s_axi_aclk] [get_bd_pins axi_uart16550_0/s_axi_aclk] [get_bd_pins bootrom_ctrl/s_axi_aclk] [get_bd_pins rst_clk_wiz_100M/slowest_sync_clk] [get_bd_pins smartconnect_0/aclk]
  connect_bd_net -net ddr_ready_1 [get_bd_ports ddr_ready] [get_bd_pins rst_clk_wiz_100M/dcm_locked]
  foreach pin {ddr_calib_complete ddr_app_addr ddr_app_cmd ddr_app_en ddr_app_rdy \
               ddr_app_wdf_data ddr_app_wdf_mask ddr_app_wdf_wren ddr_app_wdf_end \
               ddr_app_wdf_rdy ddr_app_rd_data ddr_app_rd_data_valid ddr_app_rd_data_end} {
    connect_bd_net -net ${pin}_1 [get_bd_ports $pin] [get_bd_pins RXVCoreAXISynthTop_0/$pin]
  }
  connect_bd_net -net mmio_rst_1 [get_bd_ports mmio_rst] [get_bd_pins RXVCLINT_0/sys_reset]
  connect_bd_net -net reset_rtl_0_1 [get_bd_ports reset_rtl_0] [get_bd_pins rst_clk_wiz_100M/ext_reset_in]
  connect_bd_net -net rst_clk_wiz_100M_interconnect_aresetn [get_bd_pins rst_clk_wiz_100M/interconnect_aresetn] [get_bd_pins smartconnect_0/aresetn]
  connect_bd_net -net rst_clk_wiz_100M_peripheral_aresetn [get_bd_pins RXVCLINT_0/s_axi_aresetn] [get_bd_pins axi_intc_0/s_axi_aresetn] [get_bd_pins axi_quad_spi_0/s_axi_aresetn] [get_bd_pins axi_uart16550_0/s_axi_aresetn] [get_bd_pins bootrom_ctrl/s_axi_aresetn] [get_bd_pins rst_clk_wiz_100M/peripheral_aresetn]
  connect_bd_net -net rst_clk_wiz_100M_peripheral_reset [get_bd_pins RXVCoreAXISynthTop_0/reset] [get_bd_pins rst_clk_wiz_100M/peripheral_reset]
  connect_bd_net -net spi_miso_1 [get_bd_ports spi_miso] [get_bd_pins axi_quad_spi_0/io1_i]
  connect_bd_net -net xlconcat_0_dout [get_bd_pins axi_intc_0/intr] [get_bd_pins xlconcat_0/dout]

  # Create address segments
  assign_bd_address -offset 0xF0000000 -range 0x00010000 -target_address_space [get_bd_addr_spaces RXVCoreAXISynthTop_0/m_d_axi] [get_bd_addr_segs RXVCLINT_0/s_axi/reg0] -force
  assign_bd_address -offset 0xFFFD0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces RXVCoreAXISynthTop_0/m_d_axi] [get_bd_addr_segs axi_intc_0/S_AXI/Reg] -force
  assign_bd_address -offset 0xFFFE0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces RXVCoreAXISynthTop_0/m_d_axi] [get_bd_addr_segs axi_quad_spi_0/AXI_LITE/Reg] -force
  assign_bd_address -offset 0xFFFF0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces RXVCoreAXISynthTop_0/m_d_axi] [get_bd_addr_segs axi_uart16550_0/S_AXI/Reg] -force
  assign_bd_address -offset 0x40000000 -range 0x00010000 -target_address_space [get_bd_addr_spaces RXVCoreAXISynthTop_0/m_d_axi] [get_bd_addr_segs bootrom_ctrl/S_AXI/Mem0] -force
  assign_bd_address -offset 0x40000000 -range 0x00010000 -target_address_space [get_bd_addr_spaces RXVCoreAXISynthTop_0/m_i_axi] [get_bd_addr_segs bootrom_ctrl/S_AXI/Mem0] -force

  # Exclude Address Segments
  exclude_bd_addr_seg -offset 0xF0000000 -range 0x00010000 -target_address_space [get_bd_addr_spaces RXVCoreAXISynthTop_0/m_i_axi] [get_bd_addr_segs RXVCLINT_0/s_axi/reg0]
  exclude_bd_addr_seg -offset 0xFFFD0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces RXVCoreAXISynthTop_0/m_i_axi] [get_bd_addr_segs axi_intc_0/S_AXI/Reg]
  exclude_bd_addr_seg -offset 0xFFFE0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces RXVCoreAXISynthTop_0/m_i_axi] [get_bd_addr_segs axi_quad_spi_0/AXI_LITE/Reg]
  exclude_bd_addr_seg -offset 0xFFFF0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces RXVCoreAXISynthTop_0/m_i_axi] [get_bd_addr_segs axi_uart16550_0/S_AXI/Reg]


  # Restore current instance
  current_bd_instance $oldCurInst

  validate_bd_design
  save_bd_design
}
# End of create_root_design()


##################################################################
# MAIN FLOW
##################################################################

create_root_design ""


