
`timescale 1ns / 1ps

module memory_controller (
    input wire clk,
    input wire rst,

    // ========================================
    // WMEM: 4-Bank, 32bit x 29280 each
    // ========================================
    input wire weight_req,
    input wire [14:0] weight_addr,

    output wire [31:0] weight_data0,
    output wire [31:0] weight_data1,
    output wire [31:0] weight_data2,
    output wire [31:0] weight_data3,

    output reg weight_valid,

    // ========================================
    // BMEM: 128bit x 163
    input wire bias_req,
    input wire [7:0] bias_addr,
    output wire [127:0] bias_data,
    output reg bias_valid,

    // ========================================
    // ACT_A: 32bit x 128
    // ========================================
    input wire act_a_req,
    input wire act_a_we,
    input wire [6:0] act_a_addr,
    input wire [31:0] act_a_din,
    output wire [31:0] act_a_dout,
    output reg act_a_valid,

    // ========================================
    // ACT_B: 32bit x 32
    // ========================================
    input wire act_b_req,
    input wire act_b_we,
    input wire [4:0] act_b_addr,
    input wire [31:0] act_b_din,
    output wire [31:0] act_b_dout,
    output reg act_b_valid,

    // ========================================
    // IMEM_A: 32bit x 196
    // ========================================
    input wire imem_a_req,
    input wire imem_a_we,
    input wire [7:0] imem_a_addr,
    input wire [31:0] imem_a_din,
    output wire [31:0] imem_a_dout,
    output reg imem_a_valid,

    // ========================================
    // IMEM_B: 32bit x 196
    // ========================================
    input wire imem_b_req,
    input wire imem_b_we,
    input wire [7:0] imem_b_addr,
    input wire [31:0] imem_b_din,
    output wire [31:0] imem_b_dout,
    output reg imem_b_valid,

    // ========================================
    // OMEM: 32bit x 10
    // ========================================
    input wire omem_req,
    input wire omem_we,
    input wire [3:0] omem_addr,
    input wire [31:0] omem_din,
    output wire [31:0] omem_dout,
    output reg omem_valid
);

    // ========================================
    // Weight Memory: 4-Bank
    // ========================================

    // Bank 0 -> PE0
    wmem_bank0 u_wmem_bank0 (
        .clka(clk),
        .ena(1'b1),
        .wea(1'b0),
        .addra(weight_addr),
        .dina(32'b0),
        .douta(weight_data0)
    );

    // Bank 1 -> PE1
    wmem_bank1 u_wmem_bank1 (
        .clka(clk),
        .ena(1'b1),
        .wea(1'b0),
        .addra(weight_addr),
        .dina(32'b0),
        .douta(weight_data1)
    );

    // Bank 2 -> PE2
    wmem_bank2 u_wmem_bank2 (
        .clka(clk),
        .ena(1'b1),
        .wea(1'b0),
        .addra(weight_addr),
        .dina(32'b0),
        .douta(weight_data2)
    );

    // Bank 3 -> PE3
    wmem_bank3 u_wmem_bank3 (
        .clka(clk),
        .ena(1'b1),
        .wea(1'b0),
        .addra(weight_addr),
        .dina(32'b0),
        .douta(weight_data3)
    );

    // ========================================
    // Bias Memory: 128bit x 163
    bmem_128 u_bmem (
        .clka(clk),
        .ena(1'b1),
        .wea(1'b0),
        .addra(bias_addr),
        .dina(128'b0),
        .douta(bias_data)
    );


    // ========================================
    // Activation Memory A
    // ========================================
    act_a_bram u_act_a (
        .clka(clk),
        .ena(act_a_req),
        .wea(act_a_we),
        .addra(act_a_addr),
        .dina(act_a_din),
        .douta(act_a_dout)
    );

    // ========================================
    // Activation Memory B
    // ========================================
    act_b_bram u_act_b (
        .clka(clk),
        .ena(act_b_req),
        .wea(act_b_we),
        .addra(act_b_addr),
        .dina(act_b_din),
        .douta(act_b_dout)
    );

    // ========================================
    // Input Memory A
    // ========================================
    imem_a_bram u_imem_a (
        .clka(clk),
        .ena(imem_a_req),
        .wea(imem_a_we),
        .addra(imem_a_addr),
        .dina(imem_a_din),
        .douta(imem_a_dout)
    );

    // ========================================
    // Input Memory B
    // ========================================
    imem_b_bram u_imem_b (
        .clka(clk),
        .ena(imem_b_req),
        .wea(imem_b_we),
        .addra(imem_b_addr),
        .dina(imem_b_din),
        .douta(imem_b_dout)
    );

    // ========================================
    // Output Memory
    // ========================================
    omem_bram u_omem (
        .clka(clk),
        .ena(omem_req),
        .wea(omem_we),
        .addra(omem_addr),
        .dina(omem_din),
        .douta(omem_dout)
    );

    // ========================================
    // Read Valid Signals
    // ========================================
    reg weight_req_d1;
    reg bias_req_d1;
    always @(posedge clk) begin
        if (rst) begin
            weight_req_d1 <= 1'b0;
            weight_valid <= 1'b0;
            bias_valid   <= 1'b0;
            bias_req_d1 <= 1'b0;
            act_a_valid  <= 1'b0;
            act_b_valid  <= 1'b0;
            imem_a_valid <= 1'b0;
            imem_b_valid <= 1'b0;
            omem_valid   <= 1'b0;
        end
        else begin
            weight_req_d1 <= weight_req;
            weight_valid  <= weight_req_d1;
            bias_req_d1 <= bias_req;
            bias_valid  <= bias_req_d1;
            act_a_valid <= act_a_req && !act_a_we;
            act_b_valid <= act_b_req && !act_b_we;

            imem_a_valid <= imem_a_req && !imem_a_we;
            imem_b_valid <= imem_b_req && !imem_b_we;

            omem_valid <= omem_req && !omem_we;
        end
    end

endmodule
