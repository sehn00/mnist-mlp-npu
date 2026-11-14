`timescale 1ns / 1ps
// ============================================================================
// tb_npu_top : 통합 테스트벤치 (A + B + C + D, 스펙 6-1절 순서)
//
// 이미지마다
//   1) 외부 포트로 IMEM_A 0~195 줄에 입력 이미지 쓰기   (가중치/bias 는 COE 로 이미 들어 있음)
//   2) i_start 1클럭 -> o_done 기다리기
//   3) ACT_A 0~127 (FC1 출력), ACT_B 0~31 (FC2 출력), OMEM 0~9 (FC3 점수) 읽어서 golden v2 와 비교
//   4) 점수 10개 중 최댓값 번호(argmax) = 예측, labels.txt 와 비교
//
// golden 파일 (handoff_D_1112/golden, golden v2 와 비트 단위로 같음을 확인함)
//   input_act_a.hex      : 이미지 100장 x 196줄
//   fc1_out_act_b.hex    : FC1 출력 정답 100 x 128줄  (이름은 act_b 지만 지금 구성에선 ACT_A 에 들어감)
//   fc2_out_act_a196.hex : FC2 출력 정답 100 x 32줄   (지금 구성에선 ACT_B)
//   fc3_omem.hex         : FC3 점수 정답 100 x 10줄
//   labels.txt           : 실제 숫자 100개
//
// Vivado 에서 쓸 때: 아래 HEX_DIR 을 내 PC 의 hex 폴더 절대경로로 바꾸기 (끝에 / 필수, 역슬래시 X)
//   예) `define HEX_DIR "C:/aissd/aissd_D/hex/"
// 시뮬레이션 시간: 이미지 1장 약 1.2 ms -> 10장이면 run all (또는 run 15ms)
// ============================================================================
`ifndef HEX_DIR
  `define HEX_DIR "hex/"
`endif
`ifndef N_IMG
  `define N_IMG 10
`endif

module tb_npu_top;
    localparam N_IMG = `N_IMG;
    localparam [2:0] SEL_IMEM = 3'd2, SEL_ACTA = 3'd3, SEL_ACTB = 3'd4, SEL_OMEM = 3'd5;

    reg         i_clk = 1'b0, i_rstn = 1'b0;
    reg         i_cen = 1'b1, i_wen = 1'b1, i_start = 1'b0;
    reg  [19:0] i_addr = 20'd0;
    reg  [31:0] i_din = 32'd0;
    wire [31:0] o_dout;
    wire        o_busy, o_done;

`ifdef OREG_ON
    npu_top #(.RD_LAT(2)) u_top (   // 조원2 11/12 IP(출력 레지스터 ON) 구성
`else
    npu_top #(.RD_LAT(1)) u_top (   // 과제 가이드 규칙: 출력 레지스터 OFF
`endif
        .i_clk(i_clk), .i_rstn(i_rstn),
        .i_cen(i_cen), .i_wen(i_wen), .i_addr(i_addr), .i_din(i_din), .o_dout(o_dout),
        .i_start(i_start), .o_busy(o_busy), .o_done(o_done)
    );

    always #5 i_clk = ~i_clk;   // 100 MHz

    // ---- golden ----
    reg [31:0] g_in  [0:19599];
    reg [31:0] g_fc1 [0:12799];
    reg [31:0] g_fc2 [0:3199];
    reg [31:0] g_fc3 [0:999];
    reg [31:0] g_lab [0:99];

    // ---- 외부 포트 쓰기 / 읽기 (negedge 에 신호를 바꿔서 posedge 에 확실히 잡히게) ----
    task ext_write(input [2:0] sel, input [16:0] addr, input [31:0] data);
    begin
        @(negedge i_clk);
        i_cen = 1'b0; i_wen = 1'b0; i_addr = {sel, addr}; i_din = data;
        @(negedge i_clk);
        i_cen = 1'b1; i_wen = 1'b1;
    end endtask

    task ext_read(input [2:0] sel, input [16:0] addr, output [31:0] data);
    begin
        @(negedge i_clk);
        i_cen = 1'b0; i_wen = 1'b1; i_addr = {sel, addr};
        @(negedge i_clk);                  // posedge 에서 주소가 잡히고, 그 다음에 o_dout 이 나옴
        i_cen = 1'b1;
        data = o_dout;
    end endtask

    integer img, i, nerr_img, nerr_fc1, nerr_fc2, nerr_fc3, n_pass, n_correct, pred, t0, cycles;
    reg [31:0] rd;
    reg signed [31:0] best;

    initial begin
        $readmemh({`HEX_DIR, "input_act_a.hex"},      g_in);
        $readmemh({`HEX_DIR, "fc1_out_act_b.hex"},    g_fc1);
        $readmemh({`HEX_DIR, "fc2_out_act_a196.hex"}, g_fc2);
        $readmemh({`HEX_DIR, "fc3_omem.hex"},         g_fc3);
        $readmemh({`HEX_DIR, "labels.txt"},           g_lab);

        n_pass = 0; n_correct = 0;
        repeat (5) @(posedge i_clk);
        i_rstn = 1'b1;
        repeat (5) @(posedge i_clk);

        for (img = 0; img < N_IMG; img = img + 1) begin
            nerr_fc1 = 0; nerr_fc2 = 0; nerr_fc3 = 0;

            // 1) 입력 이미지 쓰기
            for (i = 0; i < 196; i = i + 1) ext_write(SEL_IMEM, i, g_in[img*196 + i]);

            // 2) start -> done
            @(negedge i_clk) i_start = 1'b1;
            t0 = $time;
            @(negedge i_clk) i_start = 1'b0;
            wait (o_busy == 1'b0 && o_done == 1'b1);
            cycles = ($time - t0) / 10;

            // 3) 결과 읽고 비교
            for (i = 0; i < 128; i = i + 1) begin
                ext_read(SEL_ACTA, i, rd);
                if (rd !== g_fc1[img*128 + i]) begin
                    if (nerr_fc1 < 3) $display("  [img %0d] FC1 line %0d : got %h exp %h", img, i, rd, g_fc1[img*128 + i]);
                    nerr_fc1 = nerr_fc1 + 1;
                end
            end
            for (i = 0; i < 32; i = i + 1) begin
                ext_read(SEL_ACTB, i, rd);
                if (rd !== g_fc2[img*32 + i]) begin
                    if (nerr_fc2 < 3) $display("  [img %0d] FC2 line %0d : got %h exp %h", img, i, rd, g_fc2[img*32 + i]);
                    nerr_fc2 = nerr_fc2 + 1;
                end
            end
            best = 32'sh8000_0000; pred = -1;
            for (i = 0; i < 10; i = i + 1) begin
                ext_read(SEL_OMEM, i, rd);
                if (rd !== g_fc3[img*10 + i]) begin
                    if (nerr_fc3 < 3) $display("  [img %0d] FC3 score %0d : got %h exp %h", img, i, rd, g_fc3[img*10 + i]);
                    nerr_fc3 = nerr_fc3 + 1;
                end
                if ($signed(rd) > best) begin best = $signed(rd); pred = i; end
            end

            nerr_img = nerr_fc1 + nerr_fc2 + nerr_fc3;
            if (nerr_img == 0) n_pass = n_pass + 1;
            if (pred == g_lab[img]) n_correct = n_correct + 1;
            $display("img %0d : FC1 %0d/128  FC2 %0d/32  FC3 %0d/10 match | pred %0d label %0d | %0d clk | %s",
                     img, 128 - nerr_fc1, 32 - nerr_fc2, 10 - nerr_fc3, pred, g_lab[img], cycles,
                     (nerr_img == 0) ? "PASS" : "FAIL");
        end

        $display("==================================================");
        $display(" golden bit-exact : %0d / %0d images", n_pass, N_IMG);
        $display(" prediction       : %0d / %0d correct", n_correct, N_IMG);
        if (n_pass == N_IMG) $display(" *** tb_npu_top PASS ***");
        else                 $display(" *** tb_npu_top FAIL ***");
        $display("==================================================");
        $finish;
    end

    // 너무 오래 걸리면 멈춤 (이미지당 200만 클럭 이상이면 FSM 이 멈춘 것)
    initial begin
        #(64'd20_000_000 * N_IMG);
        $display("[TIMEOUT] o_done 이 안 올라옴");
        $finish;
    end

    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("tb_npu_top.vcd");
            $dumpvars(0, tb_npu_top);
        end
    end
endmodule
