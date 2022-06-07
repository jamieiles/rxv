set_property PACKAGE_PIN R2 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rtl_0_rxd]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rtl_0_txd]
set_property PACKAGE_PIN R12 [get_ports uart_rtl_0_txd]
set_property PACKAGE_PIN V12 [get_ports uart_rtl_0_rxd]
set_property IOSTANDARD SSTL135 [get_ports clk]

create_clock -period 10.000 -name clk -waveform {0.000 5.000} [get_ports clk]

set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]

set_property INTERNAL_VREF 0.675 [get_iobanks 34]

set_property PACKAGE_PIN U18 [get_ports sd_sck]
set_property PACKAGE_PIN U17 [get_ports sd_miso]
set_property PACKAGE_PIN V16 [get_ports sd_mosi]
set_property PACKAGE_PIN U15 [get_ports sd_ncs]
set_property IOSTANDARD LVCMOS33 [get_ports sd_sck]
set_property IOSTANDARD LVCMOS33 [get_ports sd_miso]
set_property IOSTANDARD LVCMOS33 [get_ports sd_mosi]
set_property IOSTANDARD LVCMOS33 [get_ports sd_ncs]

set_property PACKAGE_PIN V15 [get_ports eth_int]
set_property PACKAGE_PIN R11 [get_ports eth_sck]
set_property PACKAGE_PIN U11 [get_ports eth_miso]
set_property PACKAGE_PIN T11 [get_ports eth_mosi]
set_property PACKAGE_PIN T13 [get_ports eth_ncs]
set_property PACKAGE_PIN V13 [get_ports eth_reset]
set_property IOSTANDARD LVCMOS33 [get_ports eth_int]
set_property IOSTANDARD LVCMOS33 [get_ports eth_sck]
set_property IOSTANDARD LVCMOS33 [get_ports eth_miso]
set_property IOSTANDARD LVCMOS33 [get_ports eth_mosi]
set_property IOSTANDARD LVCMOS33 [get_ports eth_ncs]
set_property IOSTANDARD LVCMOS33 [get_ports eth_reset]

set_property PACKAGE_PIN C18 [get_ports ext_reset]
set_property IOSTANDARD LVCMOS33 [get_ports ext_reset]


set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property CONFIG_MODE SPIx4 [current_design]

set_property IOSTANDARD LVCMOS33 [get_ports sd_busy]
set_property PACKAGE_PIN E18 [get_ports sd_busy]
