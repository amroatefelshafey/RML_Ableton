# Platform Designer component for the IDS-CNN1D engine on the HPS-to-FPGA bridge.
# Add fpga_ids_core/hps to Tools > Options > IP Search Paths (soc_system.tcl
# does this for you). The component appears under "IDS" in the IP Catalog.
# Connect s0 to hps_0.h2f_axi_master and irq to hps_0.f2h_irq0.
package require -exact qsys 16.1

set_module_property NAME          ids_cnn1d_hps_avmm
set_module_property VERSION       1.0
set_module_property GROUP         IDS
set_module_property DISPLAY_NAME  "IDS-CNN1D Engine (HPS Avalon-MM)"
set_module_property DESCRIPTION   "Bit-exact IDS-CNN1D-S engine; result in one 32-bit register read"
set_module_property EDITABLE      false
set_module_property AUTHOR        ""

add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL ids_cnn1d_hps_avmm
add_fileset_file ids_cnn1d_weights.sv  SYSTEM_VERILOG PATH ../ids_cnn1d_weights.sv
add_fileset_file ids_cnn1d_engine.sv   SYSTEM_VERILOG PATH ../ids_cnn1d_engine.sv
add_fileset_file ids_cnn1d_hps_avmm.sv SYSTEM_VERILOG PATH ids_cnn1d_hps_avmm.sv TOP_LEVEL_FILE

add_fileset SIM_VERILOG SIM_VERILOG "" ""
set_fileset_property SIM_VERILOG TOP_LEVEL ids_cnn1d_hps_avmm
add_fileset_file ids_cnn1d_weights.sv  SYSTEM_VERILOG PATH ../ids_cnn1d_weights.sv
add_fileset_file ids_cnn1d_engine.sv   SYSTEM_VERILOG PATH ../ids_cnn1d_engine.sv
add_fileset_file ids_cnn1d_hps_avmm.sv SYSTEM_VERILOG PATH ids_cnn1d_hps_avmm.sv

add_interface clock clock end
set_interface_property clock clockRate 0
add_interface_port clock clk clk Input 1

add_interface reset reset end
set_interface_property reset associatedClock clock
set_interface_property reset synchronousEdges DEASSERT
add_interface_port reset rst_n reset_n Input 1

add_interface s0 avalon end
set_interface_property s0 addressUnits                   WORDS
set_interface_property s0 associatedClock                clock
set_interface_property s0 associatedReset                reset
set_interface_property s0 bitsPerSymbol                  8
set_interface_property s0 readLatency                    1
set_interface_property s0 readWaitTime                   0
set_interface_property s0 writeWaitTime                  0
set_interface_property s0 maximumPendingReadTransactions 0
set_interface_property s0 explicitAddressSpan            128
add_interface_port s0 avs_address    address    Input  5
add_interface_port s0 avs_read       read       Input  1
add_interface_port s0 avs_write      write      Input  1
add_interface_port s0 avs_writedata  writedata  Input  32
add_interface_port s0 avs_byteenable byteenable Input  4
add_interface_port s0 avs_readdata   readdata   Output 32

add_interface irq interrupt end
set_interface_property irq associatedAddressablePoint s0
set_interface_property irq associatedClock            clock
set_interface_property irq associatedReset            reset
add_interface_port irq irq irq Output 1

add_interface status conduit end
set_interface_property status associatedClock clock
add_interface_port status coe_class  class  Output 3
add_interface_port status coe_attack attack Output 1
add_interface_port status coe_busy   busy   Output 1
add_interface_port status coe_valid  valid  Output 1
