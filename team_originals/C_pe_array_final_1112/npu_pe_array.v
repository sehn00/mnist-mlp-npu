// ============================================================================
// npu_pe_array.v  -  C 블록: PE 배열 (조원3)
// AISSD Simple NPU Core / MNIST MLP 784-512-128-10, int8
//
// 입력 방향 타일링: 한 클럭에 "한 뉴런"의 입력 4개 x 가중치 4개를 처리
//   곱셈기 4개 (s8 x s8 -> s16)        REG1
//   덧셈 트리 3개 (s16 -> s17 -> s18)  조합
//   누산기 1개 (s32)                   REG2
//
// 타이밍
//   - i_acc_clr: 동기 클리어, i_valid보다 우선. 뉴런 시작 전 1클럭
//   - i_valid  : i_x / i_w가 유효한 클럭에 1 (FC1 196, FC2 128, FC3 32클럭)
//   - o_acc    : 마지막 i_valid 클럭 기준 2클럭 뒤에 최종값 (bias 더하기 전)
//
// 32b 워드 lane 배치: lane0 = [7:0], lane1 = [15:8], lane2 = [23:16], lane3 = [31:24]
// 검증: tb_pe_array.v, 사진 0 FC1 512 / FC2 128 / FC3 10 뉴런 golden 일치 (Vivado XSim)
// ============================================================================
module npu_pe_array (
    input  wire        clk,
    input  wire        rstn,       // active-low 비동기 리셋
    input  wire [31:0] i_x,        // 입력(activation) int8 x 4  <- B
    input  wire [31:0] i_w,        // 가중치 int8 x 4            <- B (WMEM)
    input  wire        i_valid,    // <- D
    input  wire        i_acc_clr,  // <- D
    output wire [31:0] o_acc       // 누산 결과 s32              -> A
);
    // 8비트씩 4개로 자르기 (부호 있는 수)
    wire signed [7:0] x0 = i_x[7:0],   w0 = i_w[7:0];
    wire signed [7:0] x1 = i_x[15:8],  w1 = i_w[15:8];
    wire signed [7:0] x2 = i_x[23:16], w2 = i_w[23:16];
    wire signed [7:0] x3 = i_x[31:24], w3 = i_w[31:24];

    // REG1: 곱셈 결과 (s16) + valid 1클럭 지연
    reg signed [15:0] p0, p1, p2, p3;
    reg               v1;

    // 덧셈 트리
    wire signed [16:0] s01 = p0 + p1;    // 1단 (s17)
    wire signed [16:0] s23 = p2 + p3;
    wire signed [17:0] s   = s01 + s23;  // 2단 (s18)

    // REG2: 누산기 (s32)
    reg signed [31:0] acc;
    assign o_acc = acc;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            p0 <= 16'sd0; p1 <= 16'sd0; p2 <= 16'sd0; p3 <= 16'sd0;
            v1 <= 1'b0;
            acc <= 32'sd0;
        end else begin
            p0 <= x0 * w0;  p1 <= x1 * w1;  p2 <= x2 * w2;  p3 <= x3 * w3;
            v1 <= i_valid;
            if (i_acc_clr) acc <= 32'sd0;        // 새 뉴런 시작 (우선)
            else if (v1)   acc <= acc + s;       // 유효 데이터만 누산
        end
    end
endmodule
