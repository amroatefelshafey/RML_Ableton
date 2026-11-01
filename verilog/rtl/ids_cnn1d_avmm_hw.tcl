# Platform Designer (Qsys) component for the IDS-CNN1D accelerator.
# Add the rtl/ folder to Tools > Options > IP Search Paths, then the component
# appears under "IDS" in the IP Catalog. Connect s0 to h2f_lw_axi_master.
package require -exact qsys 16.1

set_module_property NAME          ids_cnn1d_avmm
set_module_property VERSION       1.0
set_module_property GROUP         IDS
set_module_property DISPLAY_NAME  "IDS-CNN1D Accelerator (Avalon-MM)"
set_module_property DESCRIPTION   "Bit-exact IDS-CNN1D-S inference engine with a 28-word register interface"
set_module_property EDITABLE      false
set_module_property AUTHOR        ""

add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL ids_cnn1d_avmm
add_fileset_file ids_cnn1d_weights_pkg.sv SYSTEM_VERILOG PATH src/ids_cnn1d_weights_pkg.sv
add_fileset_file adder_tree.sv            SYSTEM_VERILOG PATH src/adder_tree.sv
add_fileset_file ids_cnn1d_engine.sv      SYSTEM_VERILOG PATH src/ids_cnn1d_engine.sv
add_fileset_file ids_cnn1d_avmm.sv        SYSTEM_VERILOG PATH src/ids_cnn1d_avmm.sv TOP_LEVEL_FILE

add_interface clock clock end
add_interface_port clock clk clk Input 1

add_interface reset reset end
set_interface_property reset associatedClock clock
set_interface_property reset synchronousEdges DEASSERT
add_interface_port reset rst_n reset_n Input 1

add_interface s0 avalon end
set_interface_property s0 addressUnits                   WORDS
set_interface_property s0 associatedClock                clock
set_interface_property s0 associatedReset                reset
set_interface_property s0 readLatency                    1
set_interface_property s0 readWaitTime                   0
set_interface_property s0 writeWaitTime                  0
set_interface_property s0 maximumPendingReadTransactions 0
set_interface_property s0 explicitAddressSpan            128
add_interface_port s0 avs_address   address   Input  5
add_interface_port s0 avs_write     write     Input  1
add_interface_port s0 avs_writedata writedata Input  32
add_interface_port s0 avs_read      read      Input  1
add_interface_port s0 avs_readdata  readdata  Output 32
