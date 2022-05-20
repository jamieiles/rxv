`include "RXV.svh"

module RXVMul (
    input  logic        clk,
    input  logic        reset,
    input  logic        signed_a,
    input  logic [31:0] a,
    input  logic        signed_b,
    input  logic [31:0] b,
    output logic [63:0] q
);

    typedef struct packed {
        logic [16:0] ah;
        logic [16:0] al;
        logic [16:0] bh;
        logic [16:0] bl;
    } mul_params;

    typedef struct packed {
        mul_params   p;
        logic [33:0] q;
    } mul_stage1;

    typedef struct packed {
        mul_params   p;
        logic [49:0] q;
    } mul_stage2;

    typedef struct packed {
        logic [16:0] ah;
        logic [16:0] bh;
        logic [50:0] q;
    } mul_stage3;

    mul_stage1        stage1_next;
    mul_stage1        stage1_reg;
    mul_stage2        stage2_next;
    mul_stage2        stage2_reg;
    mul_stage3        stage3_next;
    mul_stage3        stage3_reg;
    logic      [63:0] q_next;
    logic      [33:0] stage2_product;
    logic      [33:0] stage3_product;
    logic      [33:0] stage4_product;
    // verilator lint_off UNUSED
    logic      [65:0] result;
    // verilator lint_on UNUSED

    always_comb begin
        stage1_next.p = '{
            al: {1'b0, a[15:0]},
            ah: {signed_a & a[31], a[31:16]},
            bl: {1'b0, b[15:0]},
            bh: {signed_b & b[31], b[31:16]}
        };
        stage1_next.q = a[15:0] * b[15:0];
    end

    always_comb begin
        stage2_product = $signed(stage1_reg.p.bl) * $signed(stage1_reg.p.ah);
        stage2_next.p  = stage1_reg.p;
        stage2_next.q  = 50'($signed(stage1_reg.q)) + 50'($signed({stage2_product, 16'b0}));
    end

    always_comb begin
        stage3_product = $signed(stage2_reg.p.bh) * $signed(stage2_reg.p.al);
        stage3_next.bh = stage2_reg.p.bh;
        stage3_next.ah = stage2_reg.p.ah;
        stage3_next.q  = 51'($signed(stage2_reg.q)) + 51'($signed({stage3_product, 16'b0}));
    end

    always_comb begin
        stage4_product = $signed(stage3_reg.bh) * $signed(stage3_reg.ah);
        result         = 66'($signed(stage3_reg.q)) + 66'($signed({stage4_product, 32'b0}));
        q_next         = result[63:0];
    end

    RXVDFF #(
        .width($bits(mul_stage1))
    ) stage1_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (stage1_next),
        .q    (stage1_reg)
    );

    RXVDFF #(
        .width($bits(mul_stage2))
    ) stage2_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (stage2_next),
        .q    (stage2_reg)
    );

    RXVDFF #(
        .width($bits(mul_stage3))
    ) stage3_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (stage3_next),
        .q    (stage3_reg)
    );

    RXVDFF #(
        .width(64)
    ) q_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (q_next),
        .q    (q)
    );

endmodule
