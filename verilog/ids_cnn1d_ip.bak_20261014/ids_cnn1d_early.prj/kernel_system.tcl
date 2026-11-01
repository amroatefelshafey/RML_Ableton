package require -exact qsys 12.1
set_validation_property AUTOMATIC_VALIDATION false

add_instance clk_1x altera_clock_bridge
set_instance_parameter_value clk_1x "EXPLICIT_CLOCK_RATE" "0"
set_instance_parameter_value clk_1x "NUM_CLOCK_OUTPUTS" "1"
add_interface clock_reset clock sink
set_interface_property clock_reset EXPORT_OF clk_1x.in_clk

add_instance reset altera_reset_bridge
set_instance_parameter_value reset "ACTIVE_LOW_RESET" "1"
set_instance_parameter_value reset "SYNCHRONOUS_EDGES" "deassert"
set_instance_parameter_value reset "NUM_RESET_OUTPUTS" "1"
add_interface clock_reset_reset reset sink
set_interface_property clock_reset_reset EXPORT_OF reset.in_reset
add_connection clk_1x.out_clk reset.clk

## Connect global memory hosts to memory interfaces
add_instance mem0 altera_avalon_mm_bridge
set_instance_parameter_value mem0 "DATA_WIDTH" "512"
set_instance_parameter_value mem0 "SYMBOL_WIDTH" "8"
set_instance_parameter_value mem0 "ADDRESS_WIDTH" "32"
set_instance_parameter_value mem0 "USE_AUTO_ADDRESS_WIDTH" "0"
set_instance_parameter_value mem0 "ADDRESS_UNITS" "SYMBOLS"
set_instance_parameter_value mem0 "MAX_BURST_SIZE" "16"
set_instance_parameter_value mem0 "MAX_PENDING_RESPONSES" "64"
set_instance_parameter_value mem0 "LINEWRAPBURSTS" "0"
set_instance_parameter_value mem0 "PIPELINE_COMMAND" "1"
set_instance_parameter_value mem0 "PIPELINE_RESPONSE" "1"
add_connection clk_1x.out_clk mem0.clk
add_connection reset.out_reset mem0.reset
add_interface mem0 avalon end
set_interface_property mem0 EXPORT_OF mem0.m0

## Connect external hosts to internal memory interfaces

## Connect streaming adapters

## Connect IRQ ports
add_instance kernel_irq altera_irq_bridge
set_instance_parameter_value kernel_irq "IRQ_WIDTH" "1"
set_instance_parameter_value kernel_irq "IRQ_N" "0"
add_interface kernel_irq irq sender
set_interface_property kernel_irq EXPORT_OF kernel_irq.sender0_irq
add_connection clk_1x.out_clk kernel_irq.clk
add_connection reset.out_reset kernel_irq.clk_reset


## Connect freeze port

## Connect board hosts
add_instance kernel_cra altera_avalon_mm_bridge
set_instance_parameter_value kernel_cra "DATA_WIDTH" "64"
set_instance_parameter_value kernel_cra "SYMBOL_WIDTH" "8"
set_instance_parameter_value kernel_cra "ADDRESS_WIDTH" "30"
set_instance_parameter_value kernel_cra "USE_AUTO_ADDRESS_WIDTH" "0"
set_instance_parameter_value kernel_cra "ADDRESS_UNITS" "SYMBOLS"
set_instance_parameter_value kernel_cra "MAX_BURST_SIZE" "1"
set_instance_parameter_value kernel_cra "MAX_PENDING_RESPONSES" "1"
set_instance_parameter_value kernel_cra "LINEWRAPBURSTS" "0"
set_instance_parameter_value kernel_cra "PIPELINE_COMMAND" "0"
set_instance_parameter_value kernel_cra "PIPELINE_RESPONSE" "0"
add_connection clk_1x.out_clk kernel_cra.clk
add_connection reset.out_reset kernel_cra.reset
add_interface avs_kernel_cra avalon end
set_interface_property kernel_cra EXPORT_OF kernel_cra.s0



source kernel_system_import.tcl
