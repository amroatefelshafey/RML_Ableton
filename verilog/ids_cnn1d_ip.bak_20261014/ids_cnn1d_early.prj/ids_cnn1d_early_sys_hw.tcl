package require -exact qsys 14.0
set_module_property NAME ids_cnn1d_early_sys
set_module_property VERSION 14.0
set_module_property INTERNAL false
set_module_property GROUP Accelerators
set_module_property DISPLAY_NAME ids_cnn1d_early_sys
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property EDITABLE true

set_module_assignment ipa.mangled.names { }
set_module_assignment ipa.report.names { }

####  freeze
add_interface freeze conduit end
set_interface_property freeze ENABLED true
add_interface_port freeze freeze freeze input 1

add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL ids_cnn1d_early_sys
set_fileset_property QUARTUS_SYNTH ENABLE_RELATIVE_INCLUDE_PATHS false
add_fileset_file "ids_cnn1d_early_di.sv" SYSTEM_VERILOG PATH "ids_cnn1d_early_di.sv" TOP_LEVEL_FILE
add_fileset_file "ids_cnn1d_early_sys.sv" SYSTEM_VERILOG PATH "ids_cnn1d_early_sys.sv" TOP_LEVEL_FILE


add_fileset SIM_VERILOG SIM_VERILOG "" ""
set_fileset_property SIM_VERILOG TOP_LEVEL ids_cnn1d_early_sys
add_fileset_file "ids_cnn1d_early_di.sv" SYSTEM_VERILOG PATH "ids_cnn1d_early_di.sv" TOP_LEVEL_FILE
add_fileset_file "ids_cnn1d_early_sys.sv" SYSTEM_VERILOG PATH "ids_cnn1d_early_sys.sv" TOP_LEVEL_FILE
