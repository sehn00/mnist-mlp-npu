`timescale 1ns / 1ps
// ============================================================================
// bram_models.v : iverilog 시뮬레이션 전용 BRAM 행동 모델 (Vivado 에서는 넣지 말 것!)
// Vivado 에서는 조원2의 .xci (Block Memory Generator IP) 가 같은 이름으로 들어감.
// .xci 설정 그대로 흉내냄: Single Port, WRITE_FIRST, ENA 핀 사용,
//   WMEM/BMEM = 출력 레지스터 ON (읽기 지연 2), 나머지 = OFF (읽기 지연 1)
// ============================================================================
`ifndef HEX_DIR
  `define HEX_DIR "hex/"
`endif

module bram_sp_model #(
    parameter W = 32, D = 128, AW = 7, OREG = 0, INIT = ""
)(
    input  wire          clka,
    input  wire          ena,
    input  wire [0:0]    wea,
    input  wire [AW-1:0] addra,
    input  wire [W-1:0]  dina,
    output wire [W-1:0]  douta
);
    reg [W-1:0] mem [0:D-1];
    reg [W-1:0] r_q1, r_q2;
    integer i;
    initial begin
        for (i = 0; i < D; i = i + 1) mem[i] = {W{1'b0}};
        if (INIT != "") $readmemh(INIT, mem);
        r_q1 = {W{1'b0}}; r_q2 = {W{1'b0}};
    end
    always @(posedge clka) begin
        if (ena) begin
            if (wea[0]) begin mem[addra] <= dina; r_q1 <= dina; end   // WRITE_FIRST
            else        r_q1 <= mem[addra];
        end
        r_q2 <= r_q1;
    end
    assign douta = OREG ? r_q2 : r_q1;
endmodule

`define WBANK(name, file) \
module name (input wire clka, input wire ena, input wire [0:0] wea, input wire [14:0] addra, \
             input wire [31:0] dina, output wire [31:0] douta); \
    bram_sp_model #(.W(32), .D(29280), .AW(15), .OREG(1), .INIT({`HEX_DIR, file})) u_m \
        (.clka(clka), .ena(ena), .wea(wea), .addra(addra), .dina(dina), .douta(douta)); \
endmodule

`WBANK(wmem_bank0, "weight_bank0.mem")
`WBANK(wmem_bank1, "weight_bank1.mem")
`WBANK(wmem_bank2, "weight_bank2.mem")
`WBANK(wmem_bank3, "weight_bank3.mem")

module bmem_128 (input wire clka, input wire ena, input wire [0:0] wea, input wire [7:0] addra,
                 input wire [127:0] dina, output wire [127:0] douta);
    bram_sp_model #(.W(128), .D(163), .AW(8), .OREG(1), .INIT({`HEX_DIR, "bias_128bit.mem"})) u_m
        (.clka(clka), .ena(ena), .wea(wea), .addra(addra), .dina(dina), .douta(douta));
endmodule

module imem_a_bram (input wire clka, input wire ena, input wire [0:0] wea, input wire [7:0] addra,
                    input wire [31:0] dina, output wire [31:0] douta);
    bram_sp_model #(.W(32), .D(196), .AW(8)) u_m (.clka(clka), .ena(ena), .wea(wea), .addra(addra), .dina(dina), .douta(douta));
endmodule
module imem_b_bram (input wire clka, input wire ena, input wire [0:0] wea, input wire [7:0] addra,
                    input wire [31:0] dina, output wire [31:0] douta);
    bram_sp_model #(.W(32), .D(196), .AW(8)) u_m (.clka(clka), .ena(ena), .wea(wea), .addra(addra), .dina(dina), .douta(douta));
endmodule
module act_a_bram (input wire clka, input wire ena, input wire [0:0] wea, input wire [6:0] addra,
                   input wire [31:0] dina, output wire [31:0] douta);
    bram_sp_model #(.W(32), .D(128), .AW(7)) u_m (.clka(clka), .ena(ena), .wea(wea), .addra(addra), .dina(dina), .douta(douta));
endmodule
module act_b_bram (input wire clka, input wire ena, input wire [0:0] wea, input wire [4:0] addra,
                   input wire [31:0] dina, output wire [31:0] douta);
    bram_sp_model #(.W(32), .D(32), .AW(5)) u_m (.clka(clka), .ena(ena), .wea(wea), .addra(addra), .dina(dina), .douta(douta));
endmodule
module omem_bram (input wire clka, input wire ena, input wire [0:0] wea, input wire [3:0] addra,
                  input wire [31:0] dina, output wire [31:0] douta);
    bram_sp_model #(.W(32), .D(10), .AW(4)) u_m (.clka(clka), .ena(ena), .wea(wea), .addra(addra), .dina(dina), .douta(douta));
endmodule
