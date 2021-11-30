`ifdef RXV_TRACE
`systemc_header
#include <memory>
#include "SimTracer.h"
`systemc_interface
std::unique_ptr<SimTracer> tracer;
`verilog
`endif // RXV_TRACE
