`timescale 1ns/1ps
// ============================================================================
// tb_pe_array : C 블록 단위 테스트 (이미지 0, FC1 512 + FC2 128 + FC3 10 뉴런)
// 뉴런마다: acc_clr 1클럭 -> (입력 1줄, 가중치 1줄) 을 L 클럭 동안 valid=1 로 넣기
//           -> 2클럭 기다렸다가 o_acc 를 golden 의 bias 더하기 전 값과 비교
// Vivado: 이 파일 + hex/ 폴더 7개를 Simulation Sources 로 추가 -> Run Simulation -> run all
// ============================================================================
module tb_pe_array;
    reg         clk = 0, rstn = 0;
    reg  [31:0] i_x = 0, i_w = 0;
    reg         i_valid = 0, i_acc_clr = 0;
    wire [31:0] o_acc;

    npu_pe_array dut (.clk(clk), .rstn(rstn), .i_x(i_x), .i_w(i_w),
                      .i_valid(i_valid), .i_acc_clr(i_acc_clr), .o_acc(o_acc));

    always #5 clk = ~clk;   // 100 MHz

    reg [31:0] wmem [0:117055];
    reg [31:0] in1  [0:195];   // FC1 입력 (사진 0)
    reg [31:0] in2  [0:127];   // FC2 입력 = FC1 결과
    reg [31:0] in3  [0:31];    // FC3 입력 = FC2 결과
    reg [31:0] e1 [0:511];  reg [31:0] e2 [0:127];  reg [31:0] e3 [0:9];

    integer nerr, n, k;
    reg [31:0] expv;

    task neuron(input integer L, input integer layer, input integer wbase, input integer idx);
    begin
        @(negedge clk); i_acc_clr = 1;  i_valid = 0;            // 새 뉴런: 누산기 0
        @(negedge clk); i_acc_clr = 0;
        for (k = 0; k < L; k = k + 1) begin
            case (layer) 1: i_x = in1[k]; 2: i_x = in2[k]; default: i_x = in3[k]; endcase
            i_w = wmem[wbase + idx*L + k];
            i_valid = 1;
            @(negedge clk);
        end
        i_valid = 0;
        repeat (2) @(negedge clk);                              // 파이프라인 2클럭
        case (layer) 1: expv = e1[idx]; 2: expv = e2[idx]; default: expv = e3[idx]; endcase
        if (o_acc !== expv) begin
            nerr = nerr + 1;
            if (nerr <= 10) $display("  FC%0d neuron %0d: got %0d, expected %0d", layer, idx, $signed(o_acc), $signed(expv));
        end
    end
    endtask

    task run_layer(input integer layer, input integer N, input integer L, input integer wbase);
    begin
        nerr = 0;
        for (n = 0; n < N; n = n + 1) neuron(L, layer, wbase, n);
        $display("FC%0d: %0d neurons, mismatch = %0d  %s", layer, N, nerr, nerr == 0 ? "PASS" : "FAIL");
    end
    endtask

    initial begin
        $readmemh("wmem.hex", wmem);
        $readmemh("in_img0.hex", in1); $readmemh("fc1_out_img0.hex", in2); $readmemh("fc2_out_img0.hex", in3);
        $readmemh("fc1_acc_img0.hex", e1); $readmemh("fc2_acc_img0.hex", e2); $readmemh("fc3_acc_img0.hex", e3);
        repeat (3) @(negedge clk); rstn = 1;

        run_layer(1, 512, 196, 0);        // FC1: 가중치 0번 줄부터
        run_layer(2, 128, 128, 100352);   // FC2: 100,352번 줄부터
        run_layer(3,  10,  32, 116736);   // FC3: 116,736번 줄부터
        $finish;
    end
endmodule
