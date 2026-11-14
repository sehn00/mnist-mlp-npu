`timescale 1ns / 1ps
// ============================================================================
// npu_ctrl : 제어기 (블록 D, 담당 조원4)
// 스펙 v0.2 6-2절 FSM(상태 6개) + handoff_D_1112 레이어 설정표(golden v2) 기준
//
// 하는 일: 아래 3중 for 문을 FSM으로 돌리면서 주소와 제어 신호만 낸다 (계산은 안 함)
//   for layer in FC1, FC2, FC3
//     for n in 0..N-1                  (출력 뉴런, 시간 순서)
//       for k in 0..L-1                (입력 줄 = 입력 4개, 1클럭에 한 줄)
//         WMEM[w_base + n*L + k], 입력메모리[k] 읽기 -> C
//       (RD_LAT + 1)클럭 기다림 -> GO: A에 go, C에 acc_clr
//
// 상태: IDLE -> ISSUE(L클럭) -> WAIT(RD_LAT+1클럭) -> GO(1클럭) -> 다음 뉴런 ISSUE
//        레이어 마지막 뉴런 GO 다음은 LAYER(1클럭), FC3 마지막 뉴런 GO 다음은 DONE
//
// RD_LAT : SRAM 읽기 지연 클럭 수
//   1 = 스펙 v0.2 (BMEM 출력 레지스터 끔). 뉴런 하나 = L + 3클럭, 전체 약 119,010클럭
//   2 = 현재 조원2 IP (WMEM, BMEM 출력 레지스터 켬). 뉴런 하나 = L + 4클럭
//
// 레이어 설정표 (golden v2, handoff_D_1112 5절)
//   레이어  L    N    w_base   b_base  wbank_base  shift relu fc3  입력     출력(주소)
//   FC1    196  512  0        0       0           11    1    0    IMEM_A   ACT_A (n/4)
//   FC2    128  128  100352   512     25088       7     1    0    ACT_A    ACT_B (n/4)
//   FC3    32   10   116736   640     29184       0     0    1    ACT_B    OMEM  (n)
//
// o_waddr      : 스펙대로 WMEM 하나(32b x 117,056)를 볼 때의 주소 = w_base + n*L + k
// o_wbank_addr : 조원2 WMEM 4뱅크 구조용 주소 = wbank_base + (n/4)*L + k
// o_wbank_sel  : 4뱅크 중 어느 뱅크인지 = n % 4  (뱅크 i = n%4==i 인 뉴런들의 가중치)
//   -> 곱셈/나눗셈 없이 포인터를 +1씩 올리고, 뉴런이 끝날 때 lane != 3 이면 L만큼 되돌림
// ============================================================================
module npu_ctrl #(
    parameter RD_LAT = 1                 // SRAM 읽기 지연 (1 또는 2)
)(
    input  wire        i_clk,
    input  wire        i_rstn,
    input  wire        i_start,          // 1클럭 1이면 FC1~FC3 시작
    output wire        o_busy,           // 연산 중 1 (IDLE 이외)
    output reg         o_done,           // 끝나면 1, 다음 i_start 까지 유지

    // ---- B (메모리) ----
    output wire        o_rd_en,          // 1: 이번 클럭에 입력/가중치 읽기 (ISSUE 상태)
    output wire [16:0] o_waddr,          // WMEM 줄 주소 (단일 WMEM 기준, 최대 117,055)
    output wire [14:0] o_wbank_addr,     // WMEM 4뱅크 기준 주소 (최대 29,279)
    output wire [1:0]  o_wbank_sel,      // 4뱅크 중 선택 = n % 4
    output wire [7:0]  o_xaddr,          // 입력 메모리 줄 주소 = k (최대 195)
    output wire [9:0]  o_baddr,          // BIAS 주소 = b_base + n (최대 649)
    output wire [7:0]  o_oaddr,          // 결과 쓸 줄 = n/4 (FC3는 n). A의 o_we 와 같은 클럭에 유효
    output wire [1:0]  o_layer,          // 0 FC1, 1 FC2, 2 FC3

    // ---- C (PE 배열) ----
    output wire        o_valid,          // ISSUE를 RD_LAT 클럭 늦춘 것
    output wire        o_acc_clr,        // GO 클럭

    // ---- A (후처리) ----
    output wire        o_bias_we,        // k=0 ISSUE를 RD_LAT 클럭 늦춘 것
    output wire        o_go,             // GO 클럭 (마지막 valid 2클럭 뒤)
    output wire [1:0]  o_lane,           // n % 4
    output wire        o_relu_en,        // FC1, FC2 = 1
    output wire [4:0]  o_shift,          // FC1 11, FC2 7, FC3 0
    output wire        o_fc3             // FC3 = 1
);

    // ------------------------------------------------------------------
    // 상태 정의
    // ------------------------------------------------------------------
    localparam [2:0] S_IDLE  = 3'd0,
                     S_ISSUE = 3'd1,
                     S_WAIT  = 3'd2,
                     S_GO    = 3'd3,
                     S_LAYER = 3'd4,
                     S_DONE  = 3'd5;

    reg [2:0]  r_state;
    reg [1:0]  r_layer;      // 0 FC1, 1 FC2, 2 FC3
    reg [9:0]  r_n;          // 출력 뉴런 번호 (최대 511)
    reg [7:0]  r_k;          // 입력 줄 번호 (최대 195)
    reg [16:0] r_w_ptr;      // WMEM 주소 (단일 기준)
    reg [14:0] r_wb_ptr;     // WMEM 주소 (4뱅크 기준)
    reg [9:0]  r_b_ptr;      // BIAS 주소
    reg [1:0]  r_wait_cnt;   // WAIT 상태 클럭 카운터 (0 ~ RD_LAT)
    reg [7:0]  r_oaddr;      // GO에서 계산해서 다음 클럭(A의 o_we)에 내보냄

    // ------------------------------------------------------------------
    // 레이어 설정표 (조합 회로): 현재 레이어 -> L, N, shift, relu, fc3
    // ------------------------------------------------------------------
    reg [7:0]  w_L;
    reg [9:0]  w_N;
    reg [4:0]  w_shift;
    reg        w_relu, w_fc3;
    always @(*) begin
        case (r_layer)
            2'd0:    begin w_L = 8'd196; w_N = 10'd512; w_shift = 5'd11; w_relu = 1'b1; w_fc3 = 1'b0; end
            2'd1:    begin w_L = 8'd128; w_N = 10'd128; w_shift = 5'd7;  w_relu = 1'b1; w_fc3 = 1'b0; end
            default: begin w_L = 8'd32;  w_N = 10'd10;  w_shift = 5'd0;  w_relu = 1'b0; w_fc3 = 1'b1; end
        endcase
    end

    // 다음 레이어의 시작 주소 (LAYER 상태에서 로드). 포인터가 이어져서 사실상 같은 값이지만
    // 혹시 모를 실수를 막으려고 표 값으로 다시 넣어줌
    reg [16:0] w_next_wbase;
    reg [14:0] w_next_wbbase;
    reg [9:0]  w_next_bbase;
    always @(*) begin
        case (r_layer)
            2'd0:    begin w_next_wbase = 17'd100352; w_next_wbbase = 15'd25088; w_next_bbase = 10'd512; end // -> FC2
            default: begin w_next_wbase = 17'd116736; w_next_wbbase = 15'd29184; w_next_bbase = 10'd640; end // -> FC3
        endcase
    end

    wire w_last_k      = (r_k == w_L - 8'd1);
    wire w_last_n      = (r_n == w_N - 10'd1);
    wire w_wait_end    = (r_wait_cnt == RD_LAT);

    // ------------------------------------------------------------------
    // FSM + 카운터
    // ------------------------------------------------------------------
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            r_state    <= S_IDLE;
            r_layer    <= 2'd0;
            r_n        <= 10'd0;
            r_k        <= 8'd0;
            r_w_ptr    <= 17'd0;
            r_wb_ptr   <= 15'd0;
            r_b_ptr    <= 10'd0;
            r_wait_cnt <= 2'd0;
            r_oaddr    <= 8'd0;
            o_done     <= 1'b0;
        end else begin
            case (r_state)
                S_IDLE: begin
                    if (i_start) begin
                        r_state  <= S_ISSUE;
                        r_layer  <= 2'd0;
                        r_n      <= 10'd0;
                        r_k      <= 8'd0;
                        r_w_ptr  <= 17'd0;
                        r_wb_ptr <= 15'd0;
                        r_b_ptr  <= 10'd0;
                        o_done   <= 1'b0;
                    end
                end

                S_ISSUE: begin                       // 줄 k 주소를 내는 중
                    r_w_ptr  <= r_w_ptr + 17'd1;
                    r_wb_ptr <= r_wb_ptr + 15'd1;
                    if (w_last_k) begin
                        r_k        <= 8'd0;
                        r_wait_cnt <= 2'd0;
                        r_state    <= S_WAIT;
                    end else begin
                        r_k <= r_k + 8'd1;
                    end
                end

                S_WAIT: begin                        // SRAM -> REG1 -> ACC 파이프라인 끝날 때까지
                    if (w_wait_end) r_state <= S_GO;
                    else            r_wait_cnt <= r_wait_cnt + 2'd1;
                end

                S_GO: begin                          // o_go, o_acc_clr = 1 (아래 assign)
                    r_oaddr <= w_fc3 ? r_n[7:0] : {1'b0, r_n[8:2]};    // FC3는 n, 나머지는 n/4 (n 최대 511 -> 7비트)
                    r_b_ptr <= r_b_ptr + 10'd1;
                    // 4뱅크 주소: 같은 4개 묶음(n/4)의 다음 뉴런이면 묶음 시작으로 되돌림
                    if (r_n[1:0] != 2'd3)
                        r_wb_ptr <= r_wb_ptr - {7'd0, w_L};
                    if (w_last_n) begin
                        r_n     <= 10'd0;
                        r_state <= (r_layer == 2'd2) ? S_DONE : S_LAYER;
                        if (r_layer == 2'd2) o_done <= 1'b1;
                    end else begin
                        r_n     <= r_n + 10'd1;
                        r_state <= S_ISSUE;
                    end
                end

                S_LAYER: begin                       // 1클럭 빈칸: A가 레이어 마지막 줄을 씀
                    r_w_ptr  <= w_next_wbase;
                    r_wb_ptr <= w_next_wbbase;
                    r_b_ptr  <= w_next_bbase;
                    r_layer  <= r_layer + 2'd1;      // 이 클럭 끝에 바뀜 -> 쓰기는 이전 레이어로 감
                    r_n      <= 10'd0;
                    r_k      <= 8'd0;
                    r_state  <= S_ISSUE;
                end

                S_DONE: begin                        // A가 OMEM 9번에 점수 쓰는 클럭
                    r_state <= S_IDLE;
                end

                default: r_state <= S_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------------
    // RD_LAT 만큼 늦추는 시프트 레지스터 (valid, bias_we)
    //   bit 0 = 1클럭 지연, bit RD_LAT-1 = RD_LAT클럭 지연
    // ------------------------------------------------------------------
    wire w_issue    = (r_state == S_ISSUE);
    wire w_issue_k0 = w_issue && (r_k == 8'd0);

    reg [3:0] r_valid_sr, r_bwe_sr;
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            r_valid_sr <= 4'd0;
            r_bwe_sr   <= 4'd0;
        end else begin
            r_valid_sr <= {r_valid_sr[2:0], w_issue};
            r_bwe_sr   <= {r_bwe_sr[2:0],   w_issue_k0};
        end
    end

    // ------------------------------------------------------------------
    // 출력
    // ------------------------------------------------------------------
    assign o_busy       = (r_state != S_IDLE);
    assign o_rd_en      = w_issue;
    assign o_waddr      = r_w_ptr;
    assign o_wbank_addr = r_wb_ptr;
    assign o_wbank_sel  = r_n[1:0];
    assign o_xaddr      = r_k;
    assign o_baddr      = r_b_ptr;
    assign o_oaddr      = r_oaddr;
    assign o_layer      = r_layer;

    assign o_valid      = r_valid_sr[RD_LAT-1];
    assign o_acc_clr    = (r_state == S_GO);
    assign o_bias_we    = r_bwe_sr[RD_LAT-1];
    assign o_go         = (r_state == S_GO);
    assign o_lane       = r_n[1:0];
    assign o_relu_en    = w_relu;
    assign o_shift      = w_shift;
    assign o_fc3        = w_fc3;

endmodule
