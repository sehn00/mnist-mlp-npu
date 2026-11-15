`timescale 1ns / 1ps
// ============================================================================
// npu_top : 최상위 (조원4)
// 스펙 v0.2 3절 탑 입출력 + NPU_naming_rules(11/12) 3절 연결선 이름 기준
//
//   u_D npu_ctrl      : FSM, 주소/제어 신호
//   u_B npu_mem_ctrl  : 메모리 + 외부 인터페이스 (현재는 조원2 memory_controller 를 감싼 임시 어댑터)
//   u_C npu_pe_array  : 곱셈 4개 + 덧셈 트리 + 누산기
//   u_A npu_postproc  : bias, ReLU, shift, 포화, 4개 묶기
//
// RD_LAT = 1 : 과제 가이드 p.9 "Primitives Output Register should be disabled" -> BMEM 읽기 지연 1클럭.
//              조원2의 11/12 IP(WMEM/BMEM 출력 레지스터 ON, 폐기된 구성)를 그대로 쓸 때만 2로 바꿈.
//
// 바깥에서 쓰는 순서: IMEM_A 에 이미지 쓰기 -> i_start 1클럭 -> o_done == 1 기다리기 -> 결과 읽기
//   (o_done 은 마지막 OMEM 쓰기가 끝나고 o_busy 가 0 이 되는 엣지에 올라감. o_busy = 1 인 동안의 외부 접근과 i_start 는 무시됨)
// 연결선 waddr(단일 WMEM 기준 주소)는 u_B 로 가지 않음: B 가 4뱅크 구조라 wbank_addr / wbank_sel 을 씀
// ============================================================================
module npu_top #(
    parameter RD_LAT = 1    // BMEM 읽기 지연 (위 주석 참고)
)(
    input  wire        i_clk,
    input  wire        i_rstn,
    // 외부 SRAM 접근 (o_busy = 0 일 때만. o_busy = 1 이면 무시됨)
    input  wire        i_cen,
    input  wire        i_wen,
    input  wire [19:0] i_addr,
    input  wire [31:0] i_din,
    output wire [31:0] o_dout,
    // 연산 제어
    input  wire        i_start,
    output wire        o_busy,
    output wire        o_done
);

    // ---- 블록 사이 연결선 (이름 = 보내는 쪽 출력 이름에서 o_ 뺀 것) ----
    wire [31:0] x, w, bias, acc, wdata;
    wire        we;
    wire        valid, acc_clr, bias_we, go, relu_en, fc3, rd_en, busy;
    wire [1:0]  lane, layer, wbank_sel;
    wire [4:0]  shift;
    wire [16:0] waddr;
    wire [14:0] wbank_addr;
    wire [7:0]  xaddr, oaddr;
    wire [9:0]  baddr;

    assign o_busy = busy;

    npu_ctrl #(.RD_LAT(RD_LAT)) u_D (
        .i_clk(i_clk), .i_rstn(i_rstn),
        .i_start(i_start), .o_busy(busy), .o_done(o_done),
        .o_rd_en(rd_en), .o_waddr(waddr), .o_wbank_addr(wbank_addr), .o_wbank_sel(wbank_sel),
        .o_xaddr(xaddr), .o_baddr(baddr), .o_oaddr(oaddr), .o_layer(layer),
        .o_valid(valid), .o_acc_clr(acc_clr),
        .o_bias_we(bias_we), .o_go(go), .o_lane(lane),
        .o_relu_en(relu_en), .o_shift(shift), .o_fc3(fc3)
    );

    npu_mem_ctrl #(.RD_LAT(RD_LAT)) u_B (
        .i_clk(i_clk), .i_rstn(i_rstn),
        .i_cen(i_cen), .i_wen(i_wen), .i_addr(i_addr), .i_din(i_din), .o_dout(o_dout),
        .i_busy(busy), .i_rd_en(rd_en),
        .i_wbank_addr(wbank_addr), .i_wbank_sel(wbank_sel),
        .i_xaddr(xaddr), .i_baddr(baddr), .i_oaddr(oaddr), .i_layer(layer),
        .i_we(we), .i_wdata(wdata),
        .o_x(x), .o_w(w), .o_bias(bias)
    );

    npu_pe_array u_C (
        .i_clk(i_clk), .i_rstn(i_rstn),
        .i_x(x), .i_w(w), .i_valid(valid), .i_acc_clr(acc_clr),
        .o_acc(acc)
    );

    npu_postproc u_A (
        .i_clk(i_clk), .i_rstn(i_rstn),
        .i_bias_we(bias_we), .i_bias(bias), .i_go(go), .i_acc(acc),
        .i_lane(lane), .i_relu_en(relu_en), .i_shift(shift), .i_fc3(fc3),
        .o_we(we), .o_wdata(wdata)
    );

endmodule
