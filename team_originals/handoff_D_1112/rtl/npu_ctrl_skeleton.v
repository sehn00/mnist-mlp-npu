// npu_ctrl_skeleton.v - D 블록 포트 예시 + TODO (조원4가 자유롭게 수정)
// 레이어 설정표와 타이밍 규칙은 00_먼저_읽어주세요.md 5, 6절 참고
module npu_ctrl (
    input  wire        i_clk,
    input  wire        i_rstn,
    input  wire        i_start,      // 사진 한 장 처리 시작
    output reg         o_done,       // FC3 끝

    // ---- B (메모리) : 조원2 포트 이름에 맞춰 수정 ----
    output reg  [16:0] o_waddr,      // WMEM 주소 = w_base + n*L + k  (최대 117,055)
    output reg  [7:0]  o_xaddr,      // 입력 메모리 주소 = k            (최대 195)
    output reg  [9:0]  o_baddr,      // BMEM 주소 = b_base + n          (최대 649)
    output reg  [7:0]  o_oaddr,      // 출력 메모리 주소 = n/4 (FC3는 n)
    output reg  [1:0]  o_layer,      // 0 FC1, 1 FC2, 2 FC3 (어느 메모리를 읽고 쓸지)

    // ---- C (PE 배열) ----
    output reg         o_valid,      // BRAM 지연(1클럭)만큼 주소보다 늦게
    output reg         o_acc_clr,

    // ---- A (후처리) ----
    output reg         o_bias_we,
    output reg         o_go,         // 마지막 valid + 2클럭
    output reg  [1:0]  o_lane,       // n % 4
    output reg         o_relu_en,    // FC1, FC2 = 1
    output reg  [4:0]  o_shift,      // FC1 11, FC2 7, FC3 0
    output reg         o_fc3
);
    // TODO 1: 상태 정의 (예: IDLE, CLR, MAC, WAIT, GO, NEXT, DONE)
    // TODO 2: 카운터 layer, n, k
    // TODO 3: 레이어별 L, N, w_base, b_base, shift 선택
    // TODO 4: 상태별 출력 신호
endmodule
