# ============================================================================
# Minimal DE1-SoC Platform Designer system: HPS + IDS-CNN1D engine.
#   qsys-script --script=soc_system.tcl     (writes soc_system.qsys)
#
#   hps_0.h2f_axi_master (32-bit, HPS 0xC000_0000) -> ids_0.s0 at offset 0x0
#   ids_0.irq -> hps_0.f2h_irq0, IRQ 0 (GIC SPI 40)
#   clk_0 (50 MHz CLOCK_50) clocks the bridge and the engine
#
# Only the FPGA side is configured: no HPS I/O peripherals are muxed here.
# Run it on the SD-card Linux image you already have; that image's preloader
# sets up DDR3, pins and clocks. If you need a new preloader, add
# ids_cnn1d_hps_avmm to Terasic's DE1_SoC_GHRD soc_system.qsys the same way
# instead. The DDR3 values below describe the DE1-SoC's 2x MT41K256M16
# (1 GB, 32-bit, 400 MHz) with conservative timings.
# ============================================================================
package require -exact qsys 16.1

set_module_property NAME soc_system
set_project_property DEVICE_FAMILY {Cyclone V}
set_project_property DEVICE 5CSEMA5F31C6

# --- clock / reset ---------------------------------------------------------
add_instance clk_0 clock_source
set_instance_parameter_value clk_0 clockFrequency        50000000.0
set_instance_parameter_value clk_0 clockFrequencyKnown   true
set_instance_parameter_value clk_0 resetSynchronousEdges NONE

# --- HPS ---------------------------------------------------------------------
add_instance hps_0 altera_hps
# FPGA interfaces
set_instance_parameter_value hps_0 S2F_Width            1      ;# HPS-to-FPGA bridge, 32-bit
set_instance_parameter_value hps_0 F2S_Width            0      ;# FPGA-to-HPS bridge unused
set_instance_parameter_value hps_0 LWH2F_Enable         false
set_instance_parameter_value hps_0 F2SINTERRUPT_Enable  true
set_instance_parameter_value hps_0 F2SDRAM_Type         {}
set_instance_parameter_value hps_0 F2SDRAM_Width        {}
# DDR3: DE1-SoC, 2x Micron MT41K256M16HA-125 at 400 MHz
set_instance_parameter_value hps_0 MEM_VENDOR           {Micron}
set_instance_parameter_value hps_0 MEM_FORMAT           {DISCRETE}
set_instance_parameter_value hps_0 MEM_VOLTAGE          {1.5V DDR3}
set_instance_parameter_value hps_0 MEM_CLK_FREQ         400.0
set_instance_parameter_value hps_0 MEM_CLK_FREQ_MAX     800.0
set_instance_parameter_value hps_0 MEM_DQ_WIDTH         32
set_instance_parameter_value hps_0 MEM_DQ_PER_DQS       8
set_instance_parameter_value hps_0 MEM_ROW_ADDR_WIDTH   15
set_instance_parameter_value hps_0 MEM_COL_ADDR_WIDTH   10
set_instance_parameter_value hps_0 MEM_BANKADDR_WIDTH   3
set_instance_parameter_value hps_0 MEM_CK_WIDTH         1
set_instance_parameter_value hps_0 MEM_IF_DM_PINS_EN    true
set_instance_parameter_value hps_0 MEM_TCL              7
set_instance_parameter_value hps_0 MEM_WTCL_INT         7
set_instance_parameter_value hps_0 MEM_DRV_STR          {RZQ/6}
set_instance_parameter_value hps_0 MEM_RTT_NOM          {RZQ/6}
set_instance_parameter_value hps_0 MEM_RTT_WR           {Dynamic ODT off}
set_instance_parameter_value hps_0 TIMING_TIS           180
set_instance_parameter_value hps_0 TIMING_TIH           140
set_instance_parameter_value hps_0 TIMING_TDS           30
set_instance_parameter_value hps_0 TIMING_TDH           45
set_instance_parameter_value hps_0 TIMING_TDQSQ         125
set_instance_parameter_value hps_0 TIMING_TQH           0.38
set_instance_parameter_value hps_0 TIMING_TDQSCK        255
set_instance_parameter_value hps_0 TIMING_TDQSS         0.25
set_instance_parameter_value hps_0 TIMING_TQSH          0.4
set_instance_parameter_value hps_0 TIMING_TDSH          0.2
set_instance_parameter_value hps_0 TIMING_TDSS          0.2
set_instance_parameter_value hps_0 MEM_TINIT_US         500
set_instance_parameter_value hps_0 MEM_TMRD_CK          4
set_instance_parameter_value hps_0 MEM_TRAS_NS          35.0
set_instance_parameter_value hps_0 MEM_TRCD_NS          13.75
set_instance_parameter_value hps_0 MEM_TRP_NS           13.75
set_instance_parameter_value hps_0 MEM_TREFI_US         7.8
set_instance_parameter_value hps_0 MEM_TRFC_NS          260.0
set_instance_parameter_value hps_0 MEM_TWR_NS           15.0
set_instance_parameter_value hps_0 MEM_TWTR             4
set_instance_parameter_value hps_0 MEM_TFAW_NS          40.0
set_instance_parameter_value hps_0 MEM_TRRD_NS          10.0
set_instance_parameter_value hps_0 MEM_TRTP_NS          7.5

# --- IDS engine --------------------------------------------------------------
add_instance ids_0 ids_cnn1d_hps_avmm

# --- connections -------------------------------------------------------------
add_connection clk_0.clk       hps_0.h2f_axi_clock
add_connection clk_0.clk       ids_0.clock
add_connection clk_0.clk_reset ids_0.reset
add_connection hps_0.h2f_reset ids_0.reset

add_connection hps_0.h2f_axi_master ids_0.s0
set_connection_parameter_value hps_0.h2f_axi_master/ids_0.s0 baseAddress 0x00000000

add_connection hps_0.f2h_irq0 ids_0.irq
set_connection_parameter_value hps_0.f2h_irq0/ids_0.irq irqNumber 0

# --- exports -----------------------------------------------------------------
set_interface_property clk        EXPORT_OF clk_0.clk_in
set_interface_property reset      EXPORT_OF clk_0.clk_in_reset
set_interface_property memory     EXPORT_OF hps_0.memory
set_interface_property ids_status EXPORT_OF ids_0.status

save_system soc_system.qsys
