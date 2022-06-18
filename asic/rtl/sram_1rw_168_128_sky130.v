// OpenRAM SRAM model
// Words: 128
// Word size: 168
// Write size: 21

(* blackbox *)
module sram_1rw_168_128_sky130(
`ifdef USE_POWER_PINS
    vccd1,
    vssd1,
`endif
// Port 0: RW
    clk0,csb0,web0,wmask0,spare_wen0,addr0,din0,dout0
  );

  parameter NUM_WMASKS = 8 ;
  parameter DATA_WIDTH = 169 ;
  parameter ADDR_WIDTH = 8 ;
  parameter RAM_DEPTH = 1 << ADDR_WIDTH;
  // FIXME: This delay is arbitrary.
  parameter DELAY = 3 ;
  parameter VERBOSE = 1 ; //Set to 0 to only display warnings
  parameter T_HOLD = 1 ; //Delay to hold dout value after posedge. Value is arbitrary

`ifdef USE_POWER_PINS
    inout vccd1;
    inout vssd1;
`endif
  input  clk0; // clock
  input   csb0; // active low chip select
  input  web0; // active low write control
  input [ADDR_WIDTH-1:0]  addr0;
  input [NUM_WMASKS-1:0]   wmask0; // write mask
  input           spare_wen0; // spare mask
  input [DATA_WIDTH-1:0]  din0;
  output [DATA_WIDTH-1:0] dout0;

  reg  csb0_reg;
  reg  web0_reg;
  reg [NUM_WMASKS-1:0]   wmask0_reg;
  reg spare_wen0_reg;
  reg [ADDR_WIDTH-1:0]  addr0_reg;
  reg [DATA_WIDTH-1:0]  din0_reg;
  reg [DATA_WIDTH-1:0]  dout0;

  // All inputs are registers
  always @(posedge clk0)
  begin
    csb0_reg = csb0;
    web0_reg = web0;
    wmask0_reg = wmask0;
    spare_wen0_reg = spare_wen0;
    addr0_reg = addr0;
    din0_reg = din0;
    #(T_HOLD) dout0 = 168'bx;
    if ( !csb0_reg && web0_reg && VERBOSE ) 
      $display($time," Reading %m addr0=%b dout0=%b",addr0_reg,mem[addr0_reg]);
    if ( !csb0_reg && !web0_reg && VERBOSE )
      $display($time," Writing %m addr0=%b din0=%b wmask0=%b",addr0_reg,din0_reg,wmask0_reg);
  end

reg [DATA_WIDTH-1:0]    mem [0:RAM_DEPTH-1];

  // Memory Write Block Port 0
  // Write Operation : When web0 = 0, csb0 = 0
  always @ (negedge clk0)
  begin : MEM_WRITE0
    if ( !csb0_reg && !web0_reg ) begin
        if (wmask0_reg[0])
                mem[addr0_reg][20:0] = din0_reg[20:0];
        if (wmask0_reg[1])
                mem[addr0_reg][41:21] = din0_reg[41:21];
        if (wmask0_reg[2])
                mem[addr0_reg][62:42] = din0_reg[62:42];
        if (wmask0_reg[3])
                mem[addr0_reg][83:63] = din0_reg[83:63];
        if (wmask0_reg[4])
                mem[addr0_reg][104:84] = din0_reg[104:84];
        if (wmask0_reg[5])
                mem[addr0_reg][125:105] = din0_reg[125:105];
        if (wmask0_reg[6])
                mem[addr0_reg][146:126] = din0_reg[146:126];
        if (wmask0_reg[7])
                mem[addr0_reg][167:147] = din0_reg[167:147];
        if (spare_wen0_reg)
                mem[addr0_reg][168] = din0_reg[168];
    end
  end

  // Memory Read Block Port 0
  // Read Operation : When web0 = 1, csb0 = 0
  always @ (negedge clk0)
  begin : MEM_READ0
    if (!csb0_reg && web0_reg)
       dout0 <= #(DELAY) mem[addr0_reg];
  end

endmodule
