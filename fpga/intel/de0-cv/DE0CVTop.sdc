# Copyright 2026 Jamie Iles
# SPDX-License-Identifier: Apache-2.0

set_time_format -unit ns -decimal_places 3

create_clock -period 20.000 -name clock_50 [get_ports CLOCK_50]
derive_pll_clocks
derive_clock_uncertainty

set pll       "pll|altera_pll_i|general"
set sys_clk   "${pll}[0].gpll~PLL_OUTPUT_COUNTER|divclk"
set sdram_pll "${pll}[1].gpll~PLL_OUTPUT_COUNTER|divclk"
set vga_clk   "${pll}[2].gpll~PLL_OUTPUT_COUNTER|divclk"
set clint_clk "${pll}[3].gpll~PLL_OUTPUT_COUNTER|divclk"

# The VGA pixel clock and mtime reference only cross into the system clock
# through synchronisers (the line requests and line buffer RAM, the CLINT
# reference edge).
set_clock_groups -asynchronous \
    -group [get_clocks $sys_clk] \
    -group [get_clocks $vga_clk] \
    -group [get_clocks $clint_clk]

# ------------------------------------------------------------------
# SDRAM: IS42S16320D-7 at CAS latency 2, relative to the clock at the
# SDRAM's clock pin.
# ------------------------------------------------------------------
create_generated_clock -name sdram_clk -source $sdram_pll [get_ports DRAM_CLK]
set_clock_groups -asynchronous -group [get_clocks sdram_clk] -group [get_clocks $vga_clk]
set_clock_groups -asynchronous -group [get_clocks sdram_clk] -group [get_clocks $clint_clk]

set sdram_tsu     1.5
set sdram_th      0.8
set sdram_tac     6.0
set sdram_toh     2.5
# Board trace delay
set sdram_board   0.5

set sdram_outputs [get_ports {DRAM_CKE DRAM_CS_N DRAM_RAS_N DRAM_CAS_N DRAM_WE_N
                              DRAM_BA[*] DRAM_ADDR[*] DRAM_LDQM DRAM_UDQM DRAM_DQ[*]}]
set_output_delay -clock sdram_clk -max [expr {$sdram_tsu + $sdram_board}] $sdram_outputs
set_output_delay -clock sdram_clk -min [expr {-$sdram_th + $sdram_board}] $sdram_outputs

set_input_delay -clock sdram_clk -max [expr {$sdram_tac + 2 * $sdram_board}] [get_ports {DRAM_DQ[*]}]
set_input_delay -clock sdram_clk -min [expr {$sdram_toh + 2 * $sdram_board}] [get_ports {DRAM_DQ[*]}]

# Read data is captured on the system clock edge after the SDRAM clock edge
# that launches it (SDRAMController read_latency = CAS latency + 1), which is
# the second system clock edge after the launch as the SDRAM clock is
# shifted earlier.
set_multicycle_path -setup -end -from [get_clocks sdram_clk] -to [get_clocks $sys_clk] 2

# ------------------------------------------------------------------
# Asynchronous and slow I/O
# ------------------------------------------------------------------
set_false_path -from [get_ports RESET_N]
# The SD bus is driven and sampled from registers in the I/O cells on
# strobes from the SDHCI clock generator, SDCLK is at most 30MHz.
set_false_path -to [get_ports {SD_CLK SD_CMD SD_DATA[*]}]
set_false_path -from [get_ports {SD_CMD SD_DATA[*]}]
set_false_path -to [get_ports {PS2_CLK PS2_DAT PS2_CLK2 PS2_DAT2}]
set_false_path -from [get_ports {PS2_CLK PS2_DAT PS2_CLK2 PS2_DAT2}]
set_false_path -to [get_ports {VGA_R[*] VGA_G[*] VGA_B[*] VGA_HS VGA_VS}]
set_false_path -to [get_ports {LEDR[*] HEX0[*] HEX1[*] HEX2[*] HEX3[*] HEX4[*] HEX5[*]}]
