// Example instance of the top level module for: 
//     ids_cnn1d_early_di
// To include this component in your design, include: 
//     ids_cnn1d_early_di.qsys
// in your Quartus project and follow the template 
// below to instantiate the IP.  Alternatively, the IP core 
// can be generated from a Qsys system.

ids_cnn1d_early_di ids_cnn1d_early_di_inst (
  // Interface: clock (clock end)
  .clock               ( ), // 1-bit clk input
  // Interface: resetn (reset end)
  .resetn              ( ), // 1-bit reset_n input
  // Interface: freeze (conduit end)
  .freeze              ( ), // 1-bit freeze input
  // Interface: device_exception_bus (conduit end)
  .device_exception_bus( )  // 64-bit data output
);
