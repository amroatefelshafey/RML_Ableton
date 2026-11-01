# 50 MHz board oscillator: clocks the engine and the FPGA side of the
# HPS-to-FPGA bridge. The HPS DDR3 constraints come from soc_system.qip.
create_clock -name CLOCK_50 -period 20.000 [get_ports CLOCK_50]
derive_pll_clocks
derive_clock_uncertainty

set_false_path -from [get_ports {KEY[*]}]
set_false_path -to   [get_ports {LEDR[*] HEX0[*] HEX1[*]}]
