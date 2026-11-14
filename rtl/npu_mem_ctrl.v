`timescale 1ns / 1ps
// ============================================================================
// npu_mem_ctrl : B 블록 "임시 어댑터" (작성: 조원4, 통합 리허설용 · 2026-11-14)
//
// 왜 필요한가
//   조원2의 memory_controller.v는 메모리 10개를 각자 포트로 그대로 꺼내 놓은 형태라서
//   스펙 v0.2 4절의 npu_mem_ctrl(외부 인터페이스 + busy MUX + 읽기 MUX) 역할이 비어 있음.
//   memory_controller.v 는 한 줄도 고치지 않고, 이 파일이 바깥에서 감싸서
//   D/A/C 와 탑 외부 포트에 맞게 연결만 해 줌. 조원2가 정식 npu_mem_ctrl 을 만들면 교체.
//
// 조원2 메모리의 실제 모양 (.xci 확인 결과)
//   WMEM  : 4뱅크 x (32b x 29,280), 뱅크 i = (n % 4 == i) 뉴런들의 가중치, 출력 레지스터 ON -> 지연 2
//   BMEM  : 128b x 163, 한 줄에 bias 4개 ([31:0]=bias 4m, ... [127:96]=bias 4m+3), 출력 레지스터 ON -> 지연 2
//   IMEM_A: 32b x 196 (FC1 입력), ACT_A: 32b x 128 (FC1 출력 = FC2 입력)
//   ACT_B : 32b x 32 (FC2 출력 = FC3 입력), OMEM: 32b x 10 (FC3 점수), 출력 레지스터 OFF -> 지연 1
//   -> 과제 가이드 p.9: "Primitives Output Register should be disabled" -> 출력 레지스터 OFF(RD_LAT=1)가 규칙.
//      RD_LAT=2는 조원2의 11/12 IP(ON)로 돌릴 때만 사용. top 의 RD_LAT 과 반드시 같은 값.
//
// 외부 포트 (스펙 3절과 같은 이름, 주소 맵은 임시: 조원2 메모리 구성 기준)
//   i_addr[19:17] = 0 WMEM, 1 BIAS : COE 로 초기화 (memory_controller 가 wea=0 고정) -> 외부 쓰기 무시
//                   2 IMEM_A (입력 이미지, 쓰기/읽기, 줄 0~195)
//                   3 ACT_A  (FC1 출력, 읽기, 줄 0~127)
//                   4 ACT_B  (FC2 출력, 읽기, 줄 0~31)
//                   5 OMEM   (FC3 점수, 읽기, 0~9)
//   o_dout 은 주소 준 다음 클럭에 나옴. i_busy = 1 이면 외부 접근 무시.
// ============================================================================
module npu_mem_ctrl #(
    parameter RD_LAT = 1            // BMEM 읽기 지연: 1 = 출력 레지스터 OFF (과제 가이드 p.9 규칙), 2 = ON
)(
    input  wire        i_clk,
    input  wire        i_rstn,

    // ---- 탑 외부 포트 ----
    input  wire        i_cen,         // 0 이면 접근
    input  wire        i_wen,         // 0 쓰기, 1 읽기
    input  wire [19:0] i_addr,        // [19:17] SRAM 선택, [16:0] 줄 주소
    input  wire [31:0] i_din,
    output reg  [31:0] o_dout,

    // ---- D (npu_ctrl) ----
    input  wire        i_busy,        // 1: 내부(D)가 SRAM 사용
    input  wire        i_rd_en,       // ISSUE 클럭
    input  wire [14:0] i_wbank_addr,
    input  wire [1:0]  i_wbank_sel,
    input  wire [7:0]  i_xaddr,
    input  wire [9:0]  i_baddr,
    input  wire [7:0]  i_oaddr,
    input  wire [1:0]  i_layer,       // 0 FC1, 1 FC2, 2 FC3

    // ---- A (npu_postproc) ----
    input  wire        i_we,          // A o_we
    input  wire [31:0] i_wdata,       // A o_wdata

    // ---- C, A 로 가는 읽기 데이터 (주소 뒤 RD_LAT 클럭) ----
    output wire [31:0] o_x,
    output wire [31:0] o_w,
    output wire [31:0] o_bias
);

    // ------------------------------------------------------------------
    // 외부 접근 디코드
    // ------------------------------------------------------------------
    wire [2:0] w_ext_sel = i_addr[19:17];
    wire       w_ext_en  = !i_busy && !i_cen;
    wire       w_ext_we  = w_ext_en && !i_wen;

    // ------------------------------------------------------------------
    // 내부 읽기/쓰기 대상
    //   읽기: FC1 IMEM_A, FC2 ACT_A, FC3 ACT_B
    //   쓰기: FC1 ACT_A,  FC2 ACT_B, FC3 OMEM   (읽는 곳과 쓰는 곳이 항상 달라서 충돌 없음)
    // ------------------------------------------------------------------
    wire w_rd_imem = i_busy && i_rd_en && (i_layer == 2'd0);
    wire w_rd_acta = i_busy && i_rd_en && (i_layer == 2'd1);
    wire w_rd_actb = i_busy && i_rd_en && (i_layer == 2'd2);
    wire w_wr_acta = i_busy && i_we    && (i_layer == 2'd0);
    wire w_wr_actb = i_busy && i_we    && (i_layer == 2'd1);
    wire w_wr_omem = i_busy && i_we    && (i_layer == 2'd2);

    // ---- 메모리별 포트 (busy 로 내부/외부 선택) ----
    wire        w_imem_req  = i_busy ? w_rd_imem : (w_ext_en && w_ext_sel == 3'd2);
    wire        w_imem_we   = i_busy ? 1'b0      : (w_ext_we && w_ext_sel == 3'd2);
    wire [7:0]  w_imem_addr = i_busy ? i_xaddr   : i_addr[7:0];

    wire        w_acta_req  = i_busy ? (w_rd_acta | w_wr_acta) : (w_ext_en && w_ext_sel == 3'd3);
    wire        w_acta_we   = i_busy ? w_wr_acta               : (w_ext_we && w_ext_sel == 3'd3);
    wire [6:0]  w_acta_addr = i_busy ? (w_wr_acta ? i_oaddr[6:0] : i_xaddr[6:0]) : i_addr[6:0];
    wire [31:0] w_acta_din  = i_busy ? i_wdata : i_din;

    wire        w_actb_req  = i_busy ? (w_rd_actb | w_wr_actb) : (w_ext_en && w_ext_sel == 3'd4);
    wire        w_actb_we   = i_busy ? w_wr_actb               : (w_ext_we && w_ext_sel == 3'd4);
    wire [4:0]  w_actb_addr = i_busy ? (w_wr_actb ? i_oaddr[4:0] : i_xaddr[4:0]) : i_addr[4:0];
    wire [31:0] w_actb_din  = i_busy ? i_wdata : i_din;

    wire        w_omem_req  = i_busy ? w_wr_omem   : (w_ext_en && w_ext_sel == 3'd5);
    wire        w_omem_we   = i_busy ? w_wr_omem   : (w_ext_we && w_ext_sel == 3'd5);
    wire [3:0]  w_omem_addr = i_busy ? i_oaddr[3:0] : i_addr[3:0];
    wire [31:0] w_omem_din  = i_busy ? i_wdata : i_din;

    // ------------------------------------------------------------------
    // 조원2 memory_controller (수정 없이 그대로 사용)
    // ------------------------------------------------------------------
    wire [31:0]  w_wd0, w_wd1, w_wd2, w_wd3;
    wire [127:0] w_bias128;
    wire [31:0]  w_imem_dout, w_acta_dout, w_actb_dout, w_omem_dout, w_imemb_dout;
    wire         w_unused_v0, w_unused_v1, w_unused_v2, w_unused_v3, w_unused_v4, w_unused_v5, w_unused_v6;

    memory_controller u_mem (
        .clk(i_clk), .rst(~i_rstn),
        .weight_req(i_rd_en), .weight_addr(i_wbank_addr),
        .weight_data0(w_wd0), .weight_data1(w_wd1), .weight_data2(w_wd2), .weight_data3(w_wd3),
        .weight_valid(w_unused_v0),
        .bias_req(i_busy), .bias_addr(i_baddr[9:2]), .bias_data(w_bias128), .bias_valid(w_unused_v1),
        .act_a_req(w_acta_req), .act_a_we(w_acta_we), .act_a_addr(w_acta_addr),
        .act_a_din(w_acta_din), .act_a_dout(w_acta_dout), .act_a_valid(w_unused_v2),
        .act_b_req(w_actb_req), .act_b_we(w_actb_we), .act_b_addr(w_actb_addr),
        .act_b_din(w_actb_din), .act_b_dout(w_actb_dout), .act_b_valid(w_unused_v3),
        .imem_a_req(w_imem_req), .imem_a_we(w_imem_we), .imem_a_addr(w_imem_addr),
        .imem_a_din(i_din), .imem_a_dout(w_imem_dout), .imem_a_valid(w_unused_v4),
        .imem_b_req(1'b0), .imem_b_we(1'b0), .imem_b_addr(8'd0),      // IMEM_B: 더블 버퍼용, 지금은 안 씀
        .imem_b_din(32'd0), .imem_b_dout(w_imemb_dout), .imem_b_valid(w_unused_v5),
        .omem_req(w_omem_req), .omem_we(w_omem_we), .omem_addr(w_omem_addr),
        .omem_din(w_omem_din), .omem_dout(w_omem_dout), .omem_valid(w_unused_v6)
    );

    // ------------------------------------------------------------------
    // 읽기 데이터 정렬: 선택 신호를 데이터 지연만큼 같이 늦춤
    //   RD_LAT = 1 (가이드 규칙, 출력 레지스터 OFF): 모든 SRAM 지연 1
    //       -> 선택 신호 1클럭 지연, x/w/bias 모두 주소 뒤 1클럭
    //   RD_LAT = 2 (조원2 11/12 IP, WMEM/BMEM 출력 레지스터 ON): WMEM/BMEM 지연 2, IMEM/ACT 지연 1
    //       -> WMEM/BMEM 선택 신호 2클럭 지연, IMEM/ACT 데이터는 레지스터로 1클럭 더 늦춤
    // ------------------------------------------------------------------
    reg [1:0]  r_wsel_d1, r_wsel_d2;
    reg [1:0]  r_bsel_d1, r_bsel_d2;
    reg [1:0]  r_xsel_d1;
    reg [31:0] r_x;
    reg [31:0] w_x_mux;                       // IMEM/ACT 읽기 데이터 중 이번 레이어 입력 고르기
    always @(*) begin
        case (r_xsel_d1)
            2'd0:    w_x_mux = w_imem_dout;
            2'd1:    w_x_mux = w_acta_dout;
            default: w_x_mux = w_actb_dout;
        endcase
    end

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            r_wsel_d1 <= 2'd0; r_wsel_d2 <= 2'd0;
            r_bsel_d1 <= 2'd0; r_bsel_d2 <= 2'd0;
            r_xsel_d1 <= 2'd0; r_x       <= 32'd0;
        end else begin
            r_wsel_d1 <= i_wbank_sel;  r_wsel_d2 <= r_wsel_d1;
            r_bsel_d1 <= i_baddr[1:0]; r_bsel_d2 <= r_bsel_d1;
            r_xsel_d1 <= i_layer;
            r_x       <= w_x_mux;
        end
    end

    wire [1:0] w_wsel = (RD_LAT == 2) ? r_wsel_d2 : r_wsel_d1;
    wire [1:0] w_bsel = (RD_LAT == 2) ? r_bsel_d2 : r_bsel_d1;

    assign o_x = (RD_LAT == 2) ? r_x : w_x_mux;
    assign o_w = (w_wsel == 2'd0) ? w_wd0 :
                 (w_wsel == 2'd1) ? w_wd1 :
                 (w_wsel == 2'd2) ? w_wd2 : w_wd3;
    assign o_bias = (w_bsel == 2'd0) ? w_bias128[31:0]  :
                    (w_bsel == 2'd1) ? w_bias128[63:32] :
                    (w_bsel == 2'd2) ? w_bias128[95:64] : w_bias128[127:96];

    // ------------------------------------------------------------------
    // 외부 읽기 데이터: 다음 클럭에 나옴 (선택 신호 1클럭 늦춤)
    // ------------------------------------------------------------------
    reg [2:0] r_ext_sel_d1;
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) r_ext_sel_d1 <= 3'd0;
        else         r_ext_sel_d1 <= w_ext_sel;
    end
    always @(*) begin
        case (r_ext_sel_d1)
            3'd2:    o_dout = w_imem_dout;
            3'd3:    o_dout = w_acta_dout;
            3'd4:    o_dout = w_actb_dout;
            3'd5:    o_dout = w_omem_dout;
            default: o_dout = 32'd0;
        endcase
    end

endmodule
