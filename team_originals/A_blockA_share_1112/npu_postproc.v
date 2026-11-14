`timescale 1ns / 1ps
// ============================================================================
// npu_postproc : 후처리 유닛 (블록 A, 담당 조원1)
// 스펙 v0.2 4절 A 포트, 6-3/6-4절 타이밍 기준
//
// 하는 일 (뉴런 1개마다)
//   1) i_bias_we 클럭에 이번 뉴런의 bias 를 레지스터 r_bias 에 잡아둠
//   2) i_go 클럭에 i_acc(C 의 누산값)를 받아 아래를 조합 회로로 한 번에 계산
//        sum  = acc + bias                      (s32)
//        relu = sum < 0 ? 0 : sum               (i_relu_en = 1 일 때만)
//        shr  = relu >>> shift                  (산술 오른쪽 시프트 = 버림)
//        sat  = shr > 127 ? 127 : shr           (0~127 포화, 8b)
//   3) 8b 결과를 패킹 레지스터의 레인(i_lane) 자리에 넣음 (레인 j = 비트 [8j+7:8j])
//   4) i_go 다음 클럭에 o_we 를 1클럭 1로
//        FC1·FC2 : lane == 3 일 때만 (결과 4개가 모였을 때) o_wdata = 4개 묶음
//        FC3     : 매 뉴런, o_wdata = sum (32b 점수 그대로)
// ============================================================================
module npu_postproc (
    input              i_clk,
    input              i_rstn,      // 0 이면 리셋 (active-low)
    // ---- bias (B 에서 값, D 에서 저장 신호) ----
    input              i_bias_we,   // 1: 이번 클럭의 i_bias 를 저장
    input      [31:0]  i_bias,      // int32 bias
    // ---- 누산값 (C) ----
    input              i_go,        // 1: 이번 클럭 i_acc 가 최종값, 처리 시작
    input      [31:0]  i_acc,       // int32 누산값
    // ---- 레이어 설정 (D) ----
    input      [1:0]   i_lane,      // 뉴런 번호 mod 4
    input              i_relu_en,   // 1: ReLU 적용 (FC1, FC2)
    input      [4:0]   i_shift,     // 오른쪽 시프트 양 (골든 v2: FC1 11, FC2 7, FC3 0. 값은 D 가 넣어줌)
    input              i_fc3,       // 1: FC3 모드 (32b 점수 그대로, 매 뉴런 쓰기)
    // ---- 결과 쓰기 (B) ----
    output reg         o_we,        // 1: 이번 클럭 o_wdata 를 메모리에 씀
    output reg [31:0]  o_wdata      // FC1/FC2: int8 4개 묶음, FC3: int32 점수
);

    // ------------------------------------------------------------------
    // 1) bias 레지스터: i_bias_we 가 1 인 클럭 끝에 값을 저장
    // ------------------------------------------------------------------
    reg signed [31:0] r_bias;
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn)        r_bias <= 32'sd0;
        else if (i_bias_we) r_bias <= i_bias;
    end

    // ------------------------------------------------------------------
    // 2) 조합 회로: acc + bias -> ReLU -> >>> shift -> 포화
    //    wire 는 "항상 이 식의 결과"인 선. 클럭과 상관없이 바로 바뀜
    // ------------------------------------------------------------------
    wire signed [31:0] w_sum  = $signed(i_acc) + r_bias;            // s32 (넘칠 일 없음)
    wire signed [31:0] w_relu = (i_relu_en && w_sum[31]) ? 32'sd0   // 맨 위 비트 1 = 음수
                                                          : w_sum;
    wire signed [31:0] w_shr  = w_relu >>> i_shift;                 // >>> : 부호 유지 시프트
    wire        [7:0]  w_sat  = (w_shr > 32'sd127) ? 8'd127         // 127 넘으면 127
                                                   : w_shr[7:0];    // ReLU 뒤라 음수 없음

    // ------------------------------------------------------------------
    // 3) 패킹: 지금까지 모은 4개 묶음에서 이번 레인 자리만 w_sat 로 바꾼 값
    // ------------------------------------------------------------------
    reg [31:0] r_pack;          // 앞 뉴런들의 결과를 모아두는 레지스터
    reg [31:0] w_pack_next;     // always @(*) 안에서 계산하는 조합 값
    always @(*) begin
        w_pack_next = r_pack;
        case (i_lane)
            2'd0: w_pack_next[ 7: 0] = w_sat;
            2'd1: w_pack_next[15: 8] = w_sat;
            2'd2: w_pack_next[23:16] = w_sat;
            2'd3: w_pack_next[31:24] = w_sat;
        endcase
    end

    // ------------------------------------------------------------------
    // 4) 출력 레지스터: go 클럭 끝에 값이 들어가서 go 다음 클럭에 보임
    // ------------------------------------------------------------------
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            r_pack  <= 32'd0;
            o_we    <= 1'b0;
            o_wdata <= 32'd0;
        end else begin
            o_we <= 1'b0;                          // 기본은 0, 아래 조건일 때만 1클럭 1
            if (i_go) begin
                r_pack <= w_pack_next;
                if (i_fc3) begin
                    o_we    <= 1'b1;               // FC3: 매 뉴런 32b 점수 쓰기
                    o_wdata <= w_sum;
                end else if (i_lane == 2'd3) begin
                    o_we    <= 1'b1;               // FC1/FC2: 4개 모였을 때만 쓰기
                    o_wdata <= w_pack_next;
                end
            end
        end
    end

endmodule
