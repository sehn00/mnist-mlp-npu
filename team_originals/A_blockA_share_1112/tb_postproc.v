`timescale 1ns / 1ps
// ============================================================================
// tb_postproc : npu_postproc 단독 테스트벤치 (블록 A)
// golden_v2/out/stages 의 단계별 정답 hex 와 비교 (shift FC1 11, FC2 7)
//   fcL_2 = acc+bias, fcL_3 = ReLU, fcL_4 = >>shift, fcL_5 = 포화, fcL_6 = 패킹
//   fc3_2 = FC3 점수
// 단계 2~5 는 DUT 안의 wire 를 계층 이름(dut.w_sum 등)으로 직접 들여다봄 (TB 에서만 가능)
// 실행: iverilog -g2005 -o tb_postproc npu_postproc.v tb_postproc.v && vvp tb_postproc
// 파형: tb_postproc.vcd (GTKWave 나 Vivado 에서 열기)
// ============================================================================
// 정답 hex 폴더. Vivado 시뮬레이션은 실행 폴더가 달라서 절대 경로로 바꿔 쓰는 게 편함
//   예) `define STAGE_DIR "C:/npu/golden/out/stages/"   (끝에 / 필수, 윈도우도 / 사용)
`ifndef STAGE_DIR
`define STAGE_DIR "../golden_v2/out/stages/"
`endif

module tb_postproc;
    // ---- DUT 입력은 reg (TB 가 값을 넣음), 출력은 wire ----
    reg         clk = 1'b0, rstn = 1'b0;
    reg         bias_we = 1'b0, go = 1'b0;
    reg  [31:0] bias = 32'd0, acc = 32'd0;
    reg  [1:0]  lane = 2'd0;
    reg         relu_en = 1'b0, fc3 = 1'b0;
    reg  [4:0]  shift = 5'd0;
    wire        we;
    wire [31:0] wdata;

    always #5 clk = ~clk;   // 10ns 주기 = 100MHz

    npu_postproc dut (
        .i_clk(clk), .i_rstn(rstn),
        .i_bias_we(bias_we), .i_bias(bias),
        .i_go(go), .i_acc(acc),
        .i_lane(lane), .i_relu_en(relu_en), .i_shift(shift), .i_fc3(fc3),
        .o_we(we), .o_wdata(wdata)
    );

    // ---- 정답 hex 를 담을 배열 (최대 512개) ----
    reg [31:0] g_acc [0:511], g_bias[0:511];
    reg [31:0] g_s2  [0:511], g_s3  [0:511], g_s4[0:511], g_s5[0:511];
    reg [31:0] g_s6  [0:127];

    integer err [2:6];      // 단계별 오류 개수 (2~6)
    integer total_err, n, i;

    // 한 레이어 돌리기: N 뉴런, shift, relu_en, fc3 모드
    task run_layer(input integer N, input [4:0] sh, input re, input f3);
    begin
        for (n = 0; n < N; n = n + 1) begin
            // 클럭 1: bias 저장
            @(negedge clk);
            bias_we = 1'b1; bias = g_bias[n];
            // 클럭 2: go, 누산값 입력 -> 조합 결과 확인
            @(negedge clk);
            bias_we = 1'b0;
            go = 1'b1; acc = g_acc[n]; lane = n % 4;
            relu_en = re; shift = sh; fc3 = f3;
            #1;
            if (dut.w_sum !== g_s2[n]) err[2] = err[2] + 1;
            if (!f3) begin
                if (dut.w_relu !== g_s3[n])        err[3] = err[3] + 1;
                if (dut.w_shr  !== g_s4[n])        err[4] = err[4] + 1;
                if (dut.w_sat  !== g_s5[n][7:0])   err[5] = err[5] + 1;
            end
            // 클럭 3: go 다음 클럭에 o_we / o_wdata 확인
            @(negedge clk);
            go = 1'b0;
            if (f3) begin
                if (we !== 1'b1 || wdata !== g_s2[n]) err[6] = err[6] + 1;
            end else if (n % 4 == 3) begin
                if (we !== 1'b1 || wdata !== g_s6[n/4]) begin
                    err[6] = err[6] + 1;
                    if (err[6] <= 3) $display("  row %0d: expect %h, got %h (we=%b)", n/4, g_s6[n/4], wdata, we);
                end
            end else begin
                if (we !== 1'b0) err[6] = err[6] + 1;   // 4개 모이기 전엔 쓰면 안 됨
            end
        end
    end
    endtask

    // 경계값 1개 확인: bias 0, shift 10, ReLU 켬, lane 0
    task corner(input [31:0] a, input [7:0] expect);
    begin
        @(negedge clk);
        bias_we = 1'b1; bias = 32'd0;
        @(negedge clk);
        bias_we = 1'b0; go = 1'b1; acc = a; lane = 2'd0;
        relu_en = 1'b1; shift = 5'd10; fc3 = 1'b0;
        #1;
        if (dut.w_sat !== expect) begin
            err[5] = err[5] + 1;
            $display("  corner acc=%0d: expect %0d, got %0d", $signed(a), expect, dut.w_sat);
        end
        @(negedge clk);
        go = 1'b0;
    end
    endtask

    task report(input [8*4-1:0] name);
    begin
        $display("%s  errors: +bias %0d | ReLU %0d | shift %0d | sat %0d | write %0d",
                 name, err[2], err[3], err[4], err[5], err[6]);
        total_err = total_err + err[2] + err[3] + err[4] + err[5] + err[6];
        for (i = 2; i <= 6; i = i + 1) err[i] = 0;
    end
    endtask

    initial begin
        $dumpfile("tb_postproc.vcd");
        $dumpvars(0, tb_postproc);
        total_err = 0;
        for (i = 2; i <= 6; i = i + 1) err[i] = 0;

        #22 rstn = 1'b1;    // 리셋 해제

        // ---- FC1: 512 뉴런, >>11, ReLU (골든 v2, 학습셋 기준) ----
        $readmemh({`STAGE_DIR, "fc1_1.hex"}, g_acc);
        $readmemh({`STAGE_DIR, "bias_fc1.hex"}, g_bias);
        $readmemh({`STAGE_DIR, "fc1_2.hex"}, g_s2);
        $readmemh({`STAGE_DIR, "fc1_3.hex"}, g_s3);
        $readmemh({`STAGE_DIR, "fc1_4.hex"}, g_s4);
        $readmemh({`STAGE_DIR, "fc1_5.hex"}, g_s5);
        $readmemh({`STAGE_DIR, "fc1_6.hex"}, g_s6);
        run_layer(512, 5'd11, 1'b1, 1'b0);
        report("FC1");

        // ---- FC2: 128 뉴런, >>7, ReLU ----
        $readmemh({`STAGE_DIR, "fc2_1.hex"}, g_acc, 0, 127);
        $readmemh({`STAGE_DIR, "bias_fc2.hex"}, g_bias, 0, 127);
        $readmemh({`STAGE_DIR, "fc2_2.hex"}, g_s2, 0, 127);
        $readmemh({`STAGE_DIR, "fc2_3.hex"}, g_s3, 0, 127);
        $readmemh({`STAGE_DIR, "fc2_4.hex"}, g_s4, 0, 127);
        $readmemh({`STAGE_DIR, "fc2_5.hex"}, g_s5, 0, 127);
        $readmemh({`STAGE_DIR, "fc2_6.hex"}, g_s6, 0, 31);
        run_layer(128, 5'd7, 1'b1, 1'b0);
        report("FC2");

        // ---- FC3: 10 뉴런, 32b 점수 그대로 ----
        $readmemh({`STAGE_DIR, "fc3_1.hex"}, g_acc, 0, 9);
        $readmemh({`STAGE_DIR, "bias_fc3.hex"}, g_bias, 0, 9);
        $readmemh({`STAGE_DIR, "fc3_2.hex"}, g_s2, 0, 9);
        run_layer(10, 5'd0, 1'b0, 1'b1);
        report("FC3");

        // ---- 경계값 테스트: 실제 데이터에선 포화가 거의 안 일어나서 직접 넣어봄 ----
        //      (acc, 기대 8b 결과)  bias = 0, shift = 10, ReLU 켬
        corner(32'sd130048,     8'd127);   // 127 << 10        -> 127 (딱 맞음)
        corner(32'sd131071,     8'd127);   // (127 << 10) + 1023 -> 127 (버림)
        corner(32'sd131072,     8'd127);   // 128 << 10        -> 128 -> 포화 127
        corner(32'sd1073741824, 8'd127);   // 아주 큰 값        -> 포화 127
        corner(32'sd1023,       8'd0);     // 1023 >> 10 = 0   (버림)
        corner(32'sd1024,       8'd1);     // 1024 >> 10 = 1
        corner(-32'sd5,         8'd0);     // 음수              -> ReLU 0
        corner(-32'sd1073741824,8'd0);     // 아주 작은 음수    -> ReLU 0
        $display("CORNER errors: %0d / 8", err[5]);
        total_err = total_err + err[5]; err[5] = 0;

        if (total_err == 0) $display("PASS: all stages match golden");
        else                $display("FAIL: %0d errors", total_err);
        $finish;
    end
endmodule
