package require -exact qsys 15.0
set_module_property NAME ids_cnn1d_early_di
set_module_property VERSION 1.0
set_module_property INTERNAL false
set_module_property GROUP oneAPI
set_module_property DISPLAY_NAME ids_cnn1d_early_di
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property EDITABLE true
set_module_property SUPPORTED_DEVICE_FAMILIES {"Cyclone V"}
#### Synthesis fileset
add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL ids_cnn1d_early_di
set_fileset_property QUARTUS_SYNTH ENABLE_RELATIVE_INCLUDE_PATHS false
add_fileset_file "ids_cnn1d_early_di.sv" SYSTEM_VERILOG PATH "./ids_cnn1d_early_di.sv"
add_fileset_file "cra_ring_node.sv" SYSTEM_VERILOG PATH "./ip/cra_ring_node.sv"
add_fileset_file "cra_ring_root.sv" SYSTEM_VERILOG PATH "./ip/cra_ring_root.sv"
add_fileset_file "cra_ring_rom.sv" SYSTEM_VERILOG PATH "./ip/cra_ring_rom.sv"
add_fileset_file "acl_reset_handler.sv" SYSTEM_VERILOG PATH "./ip/acl_reset_handler.sv"
add_fileset_file "acl_ecc_pkg.sv" SYSTEM_VERILOG PATH "./ip/acl_ecc_pkg.sv"
add_fileset_file "acl_rom_module.sv" SYSTEM_VERILOG PATH "./ip/acl_rom_module.sv"
add_fileset_file "acl_clock_enable_gating.sv" SYSTEM_VERILOG PATH "./ip/acl_clock_enable_gating.sv"
add_fileset_file "acl_altera_syncram_wrapped.sv" SYSTEM_VERILOG PATH "./ip/acl_altera_syncram_wrapped.sv"
add_fileset_file "acl_ecc_encoder.sv" SYSTEM_VERILOG PATH "./ip/acl_ecc_encoder.sv"
add_fileset_file "acl_ecc_decoder.sv" SYSTEM_VERILOG PATH "./ip/acl_ecc_decoder.sv"
#### Simulation fileset
add_fileset SIM_VERILOG SIM_VERILOG "" ""
set_fileset_property SIM_VERILOG TOP_LEVEL ids_cnn1d_early_di
set_fileset_property SIM_VERILOG ENABLE_RELATIVE_INCLUDE_PATHS false
add_fileset_file "ids_cnn1d_early_di.sv" SYSTEM_VERILOG PATH "./ids_cnn1d_early_di.sv"
add_fileset_file "cra_ring_node.sv" SYSTEM_VERILOG PATH "./ip/cra_ring_node.sv"
add_fileset_file "cra_ring_root.sv" SYSTEM_VERILOG PATH "./ip/cra_ring_root.sv"
add_fileset_file "cra_ring_rom.sv" SYSTEM_VERILOG PATH "./ip/cra_ring_rom.sv"
add_fileset_file "acl_reset_handler.sv" SYSTEM_VERILOG PATH "./ip/acl_reset_handler.sv"
add_fileset_file "acl_ecc_pkg.sv" SYSTEM_VERILOG PATH "./ip/acl_ecc_pkg.sv"
add_fileset_file "acl_rom_module.sv" SYSTEM_VERILOG PATH "./ip/acl_rom_module.sv"
add_fileset_file "acl_clock_enable_gating.sv" SYSTEM_VERILOG PATH "./ip/acl_clock_enable_gating.sv"
add_fileset_file "acl_altera_syncram_wrapped.sv" SYSTEM_VERILOG PATH "./ip/acl_altera_syncram_wrapped.sv"
add_fileset_file "acl_ecc_encoder.sv" SYSTEM_VERILOG PATH "./ip/acl_ecc_encoder.sv"
add_fileset_file "acl_ecc_decoder.sv" SYSTEM_VERILOG PATH "./ip/acl_ecc_decoder.sv"
#### Primary clock for the component
add_interface clock clock end
set_interface_property clock ENABLED true
add_interface_port clock clock clk input 1

#### resetn
add_interface resetn reset end
set_interface_property resetn associatedClock clock
set_interface_property resetn synchronousEdges BOTH
add_interface_port resetn resetn reset_n input 1

####  freeze
add_interface freeze conduit end
set_interface_property freeze ENABLED true
add_interface_port freeze freeze freeze input 1

####  device_exception_bus
add_interface device_exception_bus conduit end
set_interface_property device_exception_bus ENABLED true
set_interface_property device_exception_bus associatedClock clock
set_interface_property device_exception_bus associatedReset resetn
add_interface_port device_exception_bus device_exception_bus data output 64

#### Quartus settings (QIP strings)
set_qip_strings { "set_instance_assignment -entity \"%entityName%\" -library \"%libraryName%\" -name AUTO_SHIFT_REGISTER_RECOGNITION OFF -to *_NO_SHIFT_REG*"  }
