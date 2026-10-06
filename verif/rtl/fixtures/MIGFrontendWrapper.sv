// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
`include "RXV.svh"

module MIGFrontendWrapper (
    input  logic         clk,
    input  logic         reset,
    // Instruction port manager
    input  logic         i_valid,
    input  logic [ 31:2] i_address,
    input  logic [  3:0] i_len,
    output logic         i_complete,
    output logic [ 31:0] i_rdata,
    output logic         i_beat_ack,
    output logic [  3:0] i_beat_num,
    // Data port manager
    input  logic         d_valid,
    input  logic [ 31:2] d_address,
    input  logic [  3:0] d_len,
    input  logic         d_wren,
    input  logic [ 31:0] d_wdata,
    input  logic [  3:0] d_bytesel,
    output logic         d_complete,
    output logic [ 31:0] d_rdata,
    output logic         d_beat_ack,
    output logic [  3:0] d_beat_num,
    // MIG native interface
    input  logic         init_calib_complete,
    output logic [ 27:0] app_addr,
    output logic [  2:0] app_cmd,
    output logic         app_en,
    input  logic         app_rdy,
    output logic [127:0] app_wdf_data,
    output logic [ 15:0] app_wdf_mask,
    output logic         app_wdf_wren,
    output logic         app_wdf_end,
    input  logic         app_wdf_rdy,
    input  logic [127:0] app_rd_data,
    input  logic         app_rd_data_valid,
    input  logic         app_rd_data_end,
    // Device side of the data port split
    output logic [ 31:0] dev_last_waddr,
    output logic [ 31:0] dev_last_wdata,
    output logic [  3:0] dev_last_wstb,
    output logic [  7:0] dev_write_count
);

    MemInterface i_bus ();
    MemInterface d_bus ();
    MemInterface i_dram ();
    MemInterface d_dram ();
    MemInterface i_dev ();
    MemInterface d_dev ();

    // verilator lint_off UNUSED
    logic [ 3:0] i_beat_num_next;
    logic [ 3:0] d_beat_num_next;
    logic [31:0] i_dev_last_waddr;
    logic [31:0] i_dev_last_wdata;
    logic [ 3:0] i_dev_last_wstb;
    logic [ 7:0] i_dev_write_count;
    // verilator lint_on UNUSED

    BusAdapter i_adapter (
        .clk          (clk),
        .reset        (reset),
        .bus          (i_bus.Manager),
        .valid        (i_valid),
        .complete     (i_complete),
        .address      (i_address),
        .wdata        (32'b0),
        .wren         (1'b0),
        .bytesel      (4'b0),
        .rdata        (i_rdata),
        .len          (i_len),
        .beat_num     (i_beat_num),
        .beat_num_next(i_beat_num_next),
        .beat_ack     (i_beat_ack)
    );

    BusAdapter d_adapter (
        .clk          (clk),
        .reset        (reset),
        .bus          (d_bus.Manager),
        .valid        (d_valid),
        .complete     (d_complete),
        .address      (d_address),
        .wdata        (d_wdata),
        .wren         (d_wren),
        .bytesel      (d_bytesel),
        .rdata        (d_rdata),
        .len          (d_len),
        .beat_num     (d_beat_num),
        .beat_num_next(d_beat_num_next),
        .beat_ack     (d_beat_ack)
    );

    MemSplit i_split (
        .upstream(i_bus.Subordinate),
        .match   (i_dram.Manager),
        .other   (i_dev.Manager)
    );

    MemSplit d_split (
        .upstream(d_bus.Subordinate),
        .match   (d_dram.Manager),
        .other   (d_dev.Manager)
    );

    MIGFrontendTestDevice i_device (
        .clk        (clk),
        .reset      (reset),
        .bus        (i_dev.Subordinate),
        .last_waddr (i_dev_last_waddr),
        .last_wdata (i_dev_last_wdata),
        .last_wstb  (i_dev_last_wstb),
        .write_count(i_dev_write_count)
    );

    MIGFrontendTestDevice d_device (
        .clk        (clk),
        .reset      (reset),
        .bus        (d_dev.Subordinate),
        .last_waddr (dev_last_waddr),
        .last_wdata (dev_last_wdata),
        .last_wstb  (dev_last_wstb),
        .write_count(dev_write_count)
    );

    MIGFrontend #(
        .line_size_bytes(64),
        .app_addr_width (28)
    ) frontend (
        .clk                (clk),
        .reset              (reset),
        .ibus               (i_dram.Subordinate),
        .dbus               (d_dram.Subordinate),
        .init_calib_complete(init_calib_complete),
        .app_addr           (app_addr),
        .app_cmd            (app_cmd),
        .app_en             (app_en),
        .app_rdy            (app_rdy),
        .app_wdf_data       (app_wdf_data),
        .app_wdf_mask       (app_wdf_mask),
        .app_wdf_wren       (app_wdf_wren),
        .app_wdf_end        (app_wdf_end),
        .app_wdf_rdy        (app_wdf_rdy),
        .app_rd_data        (app_rd_data),
        .app_rd_data_valid  (app_rd_data_valid),
        .app_rd_data_end    (app_rd_data_end)
    );

endmodule
