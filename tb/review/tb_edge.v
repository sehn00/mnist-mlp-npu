`timescale 1ns / 1ps
// ============================================================================
// tb_edge : 예외 상황 테스트벤치 (리뷰 1단계 5번). npu_checker 와 같이 돌림.
//   xelab ... work.tb_edge work.npu_checker   (+define CHK_TOP=tb_edge.u_top, CHK_IMG=tb_edge.cur_img)
//
// 시나리오 (각각 끝에 ACT_A 128줄 / ACT_B 32줄 / OMEM 10줄을 golden 과 비교)
//   S01 리셋 중에 이미지 쓰기 -> 리셋을 푼 바로 그 클럭에 start
//   S02 연산 중 i_start 재입력 (997클럭마다 1클럭 + WAIT/GO/LAYER 상태에 맞춰서 + 300클럭 연속)
//   S03 i_start 를 5클럭 유지
//   S04 연산 중 외부 쓰기/읽기 (IMEM/ACT_A/ACT_B/OMEM/WMEM/BIAS 번호 전부) -> 결과와 IMEM 내용이 그대로인지
//   S05 연산 중 리셋 (a FC1 중간, b FC2 중간, c FC3 끝 직전, d 쓰기 클럭) 후 재시작. b 는 다른 이미지로 바꿔서
//   S06 done 직후: (a) busy 가 내려간 첫 클럭에 바로 start, (b) 다음 이미지 마지막 줄 쓰기와 같은 클럭에 start
//   S07 o_done 이 올라간 바로 그 클럭에 start 1클럭           -> 판정: 받아들여져야 함 (11/15 D01 전에는 무시됐음)
//   S08 i_start 를 연산이 끝난 뒤까지 계속 1 로 유지           -> 관찰: 다시 시작하는지
//   S09 busy 가 내려간 첫 클럭에 OMEM 9 읽기 (마지막 쓰기가 보이는지)
//   S10 외부 포트 연속 접근: cen 을 계속 0 으로 두고 연속 쓰기 / 연속 읽기, 쓰기 바로 다음 클럭 읽기
//   S11 없는 SRAM 번호(0, 1, 6, 7) 읽기/쓰기, 범위 밖 주소, 윗주소 비트 겹침(aliasing) -> 그 뒤 연산 결과 확인
//   S12 o_done 만 보고 바로 결과 읽기 (스펙 6-1 순서 그대로)    -> 판정: 첫 읽기가 맞아야 함 (D01 전에는 무시됐음)
// 출력: "[EDGE] Sxx ... : PASS / FAIL / OBSERVE"
// ============================================================================
`ifndef HEX_DIR
  `define HEX_DIR "hex/"
`endif

module tb_edge;
    localparam [2:0] SEL_IMEM = 3'd2, SEL_ACTA = 3'd3, SEL_ACTB = 3'd4, SEL_OMEM = 3'd5;
    localparam integer T_RUN = 119009;

    reg         i_clk = 1'b0, i_rstn = 1'b0;
    reg         i_cen = 1'b1, i_wen = 1'b1, i_start = 1'b0;
    reg  [19:0] i_addr = 20'd0;
    reg  [31:0] i_din = 32'd0;
    wire [31:0] o_dout;
    wire        o_busy, o_done;

    npu_top #(.RD_LAT(1)) u_top (
        .i_clk(i_clk), .i_rstn(i_rstn),
        .i_cen(i_cen), .i_wen(i_wen), .i_addr(i_addr), .i_din(i_din), .o_dout(o_dout),
        .i_start(i_start), .o_busy(o_busy), .o_done(o_done)
    );

    always #5 i_clk = ~i_clk;

    reg [31:0] g_in  [0:19599];
    reg [31:0] g_fc1 [0:12799];
    reg [31:0] g_fc2 [0:3199];
    reg [31:0] g_fc3 [0:999];

    integer cur_img;                // 지금 IMEM 에 들어 있는 사진 번호 (체커가 읽음)
    integer n_fail, n_pass, n_obs;
    integer cyc;                    // 클럭 카운터
    always @(posedge i_clk) cyc = cyc + 1;

    // ---------------------------------------------------------------- 기본 동작
    task ext_write(input [2:0] sel, input [16:0] a, input [31:0] d);
    begin
        @(negedge i_clk); i_cen = 1'b0; i_wen = 1'b0; i_addr = {sel, a}; i_din = d;
        @(negedge i_clk); i_cen = 1'b1; i_wen = 1'b1;
    end endtask

    task ext_read(input [2:0] sel, input [16:0] a, output [31:0] d);
    begin
        @(negedge i_clk); i_cen = 1'b0; i_wen = 1'b1; i_addr = {sel, a};
        @(negedge i_clk); i_cen = 1'b1; d = o_dout;
    end endtask

    task load_image(input integer img);
        integer k;
    begin
        for (k = 0; k < 196; k = k + 1) ext_write(SEL_IMEM, k, g_in[img*196 + k]);
        cur_img = img;
    end endtask

    task start_pulse(input integer nclk);
    begin
        @(negedge i_clk); i_start = 1'b1;
        repeat (nclk) @(negedge i_clk);
        i_start = 1'b0;
    end endtask

    // done 까지 기다림. 너무 오래 걸리면 에러
    task wait_done(output integer ok);
        integer t;
    begin
        t = 0; ok = 1;
        while (!(o_busy === 1'b0 && o_done === 1'b1) && t < 400000) begin @(negedge i_clk); t = t + 1; end
        if (t >= 400000) ok = 0;
    end endtask

    // 결과 3종을 golden 과 비교. nerr = 다른 줄 수
    task check_results(input integer img, output integer nerr);
        integer k; reg [31:0] rd;
    begin
        nerr = 0;
        for (k = 0; k < 128; k = k + 1) begin ext_read(SEL_ACTA, k, rd); if (rd !== g_fc1[img*128 + k]) nerr = nerr + 1; end
        for (k = 0; k < 32;  k = k + 1) begin ext_read(SEL_ACTB, k, rd); if (rd !== g_fc2[img*32 + k])  nerr = nerr + 1; end
        for (k = 0; k < 10;  k = k + 1) begin ext_read(SEL_OMEM, k, rd); if (rd !== g_fc3[img*10 + k])  nerr = nerr + 1; end
    end endtask

    task check_imem(input integer img, output integer nerr);
        integer k; reg [31:0] rd;
    begin
        nerr = 0;
        for (k = 0; k < 196; k = k + 1) begin ext_read(SEL_IMEM, k, rd); if (rd !== g_in[img*196 + k]) nerr = nerr + 1; end
    end endtask

    task report(input [8*8-1:0] id, input [8*90-1:0] what, input integer ok, input integer nerr, input integer clk);
    begin
        if (ok) begin n_pass = n_pass + 1; $display("[EDGE] %0s %0s : PASS (golden mismatch %0d, %0d clk)", id, what, nerr, clk); end
        else    begin n_fail = n_fail + 1; $display("[EDGE] %0s %0s : FAIL (golden mismatch %0d, %0d clk)", id, what, nerr, clk); end
    end endtask

    task do_reset(input integer nclk);     // 비동기 리셋: 클럭 중간(posedge 뒤 3 ns)에 내렸다가 클럭 중간에 올림
    begin
        @(posedge i_clk); #3 i_rstn = 1'b0;
        repeat (nclk) @(posedge i_clk);
        #3 i_rstn = 1'b1;
    end endtask

    integer ok, nerr, nerr2, t0, t1, k, n_start_in_busy, seen_busy, retrig;
    reg [31:0] rd, rd2;
    reg        stop_bg;

    // ---------------------------------------------------------------- 시나리오
    initial begin
        $readmemh({`HEX_DIR, "input_act_a.hex"},      g_in);
        $readmemh({`HEX_DIR, "fc1_out_act_b.hex"},    g_fc1);
        $readmemh({`HEX_DIR, "fc2_out_act_a196.hex"}, g_fc2);
        $readmemh({`HEX_DIR, "fc3_omem.hex"},         g_fc3);
        n_fail = 0; n_pass = 0; n_obs = 0; cyc = 0; cur_img = -1; stop_bg = 1'b0;

        // ================= S01: 리셋 중 이미지 쓰기 -> 리셋 해제와 같은 클럭에 start
        repeat (3) @(posedge i_clk);
        load_image(0);                               // i_rstn = 0 인 상태에서 쓰기
        @(negedge i_clk); i_rstn = 1'b1; i_start = 1'b1; t0 = cyc + 1;   // 다음 posedge 가 리셋 해제 후 첫 클럭
        @(negedge i_clk); i_start = 1'b0;
        wait_done(ok); t1 = cyc;
        check_results(0, nerr);
        report("S01", "image written during reset, start on first clock after reset", ok && nerr == 0, nerr, 0);

        // ================= S02: 연산 중 i_start 재입력
        load_image(1);
        start_pulse(1); t0 = cyc;
        n_start_in_busy = 0;
        fork
            begin : bg_start                           // 997클럭마다 1클럭 start
                while (!stop_bg) begin
                    repeat (997) @(negedge i_clk);
                    if (o_busy && !stop_bg) begin i_start = 1'b1; @(negedge i_clk); i_start = 1'b0; n_start_in_busy = n_start_in_busy + 1; end
                end
            end
            begin                                      // 상태에 맞춰서: WAIT(2), GO(3), LAYER(4)
                // 그 상태 클럭 동안 1 로 두고, 그 클럭을 끝내는 posedge 를 지난 뒤 0 으로 (= 그 상태에서 start 가 잡힘)
                wait (u_top.u_D.r_state == 3'd2); i_start = 1'b1; @(posedge i_clk); #1 i_start = 1'b0;   // WAIT
                wait (u_top.u_D.r_state == 3'd3); i_start = 1'b1; @(posedge i_clk); #1 i_start = 1'b0;   // GO
                wait (u_top.u_D.r_state == 3'd4); i_start = 1'b1; @(posedge i_clk); #1 i_start = 1'b0;   // LAYER (FC1 -> FC2)
                wait (u_top.u_D.r_state == 3'd4); i_start = 1'b1; @(posedge i_clk); #1 i_start = 1'b0;   // LAYER (FC2 -> FC3)
                repeat (20) @(negedge i_clk);
                i_start = 1'b1; repeat (300) @(negedge i_clk); i_start = 1'b0;                           // 300클럭 연속
                n_start_in_busy = n_start_in_busy + 5;
                wait_done(ok); stop_bg = 1'b1;
            end
        join
        t1 = cyc;
        check_results(1, nerr);
        $display("[EDGE] S02 info: i_start asserted %0d times while busy", n_start_in_busy);
        report("S02", "i_start re-asserted while busy (ignored?)", ok && nerr == 0, nerr, 0);
        stop_bg = 1'b0;

        // ================= S03: i_start 5클럭 유지
        load_image(2);
        start_pulse(5); t0 = cyc - 4;
        wait_done(ok);
        check_results(2, nerr);
        report("S03", "i_start held 5 clocks", ok && nerr == 0, nerr, 0);

        // ================= S04: 연산 중 외부 쓰기/읽기
        load_image(3);
        start_pulse(1); t0 = cyc;
        k = 0;
        while (cyc - t0 < T_RUN - 20) begin            // 끝나기 20클럭 전까지만 (busy = 0 이 된 뒤의 쓰기는 정상 접근이라 결과를 바꿈)
            // 쓰기: 모든 SRAM 번호, 줄 번호는 돌아가며 (IMEM 은 앞으로 읽힐 줄도 포함)
            @(negedge i_clk); i_cen = 1'b0; i_wen = 1'b0; i_addr = {k[2:0], 9'd0, k[10:3]}; i_din = 32'hDEAD0000 | k;
            @(negedge i_clk); i_cen = 1'b0; i_wen = 1'b1; i_addr = {k[5:3], 9'd0, k[13:6]};       // 읽기
            @(negedge i_clk); i_cen = 1'b1; i_wen = 1'b1;
            k = k + 1;
        end
        i_cen = 1'b1; i_wen = 1'b1;
        wait_done(ok);
        check_results(3, nerr);
        check_imem(3, nerr2);
        $display("[EDGE] S04 info: %0d external write+read pairs issued while busy, IMEM lines changed %0d", k, nerr2);
        report("S04", "external write/read while busy (ignored?)", ok && nerr == 0 && nerr2 == 0, nerr + nerr2, 0);

        // ================= S05a: FC1 중간 리셋 -> 같은 이미지 재시작
        load_image(4);
        start_pulse(1);
        repeat (50001) @(negedge i_clk);
        do_reset(3);
        @(negedge i_clk);
        if (o_busy !== 1'b0 || o_done !== 1'b0) begin n_fail = n_fail + 1; $display("[EDGE] S05a busy/done not cleared by reset : FAIL"); end
        start_pulse(1);
        wait_done(ok);
        check_results(4, nerr);
        report("S05a", "reset in FC1, restart same image without reloading", ok && nerr == 0, nerr, 0);

        // ================= S05b: FC2 중간 리셋 -> 다른 이미지로 바꿔서 시작
        start_pulse(1);
        repeat (110000) @(negedge i_clk);
        do_reset(2);
        load_image(5);
        start_pulse(1);
        wait_done(ok);
        check_results(5, nerr);
        report("S05b", "reset in FC2, load another image, start", ok && nerr == 0, nerr, 0);

        // ================= S05c: FC3 끝 직전 리셋 -> 재시작
        start_pulse(1);
        repeat (118990) @(negedge i_clk);
        do_reset(1);
        start_pulse(1);
        wait_done(ok);
        check_results(5, nerr);
        report("S05c", "reset near the end of FC3, restart", ok && nerr == 0, nerr, 0);

        // ================= S05d: A 의 쓰기 클럭(o_we = 1)에 리셋
        start_pulse(1);
        repeat (30000) @(negedge i_clk);
        wait (u_top.we == 1'b1);
        #2 i_rstn = 1'b0;                              // 쓰기 클럭 한가운데서 비동기 리셋
        repeat (2) @(posedge i_clk);
        #3 i_rstn = 1'b1;
        start_pulse(1);
        wait_done(ok);
        check_results(5, nerr);
        report("S05d", "reset asserted during a write clock, restart", ok && nerr == 0, nerr, 0);

        // ================= S09: busy 가 내려간 첫 클럭에 OMEM 9 읽기 (S06 앞에서: 새 연산을 한 번 더 돌림)
        start_pulse(1);
        wait (o_busy == 1'b1);
        @(negedge o_busy);                             // IDLE 로 돌아온 클럭
        i_cen = 1'b0; i_wen = 1'b1; i_addr = {SEL_OMEM, 17'd9};
        @(negedge i_clk); #0 rd = o_dout;              // 아직 주소를 준 클럭 (posedge 전)
        @(negedge i_clk); i_cen = 1'b1; rd = o_dout;   // 주소 준 다음 클럭
        if (rd === g_fc3[5*10 + 9]) begin n_pass = n_pass + 1; $display("[EDGE] S09 OMEM[9] read on the first idle clock : PASS (%h)", rd); end
        else begin n_fail = n_fail + 1; $display("[EDGE] S09 OMEM[9] read on the first idle clock : FAIL (got %h exp %h)", rd, g_fc3[5*10 + 9]); end

        // ================= S06a: busy 가 내려간 바로 그 클럭에 start (같은 이미지)
        start_pulse(1);
        wait (o_busy == 1'b1);
        @(negedge o_busy);
        i_start = 1'b1; @(negedge i_clk); @(negedge i_clk); i_start = 1'b0;   // 첫 IDLE 클럭의 posedge 에 잡힘
        @(negedge i_clk);
        if (o_busy !== 1'b1) begin n_fail = n_fail + 1; $display("[EDGE] S06a start on first idle clock was not accepted : FAIL"); end
        wait_done(ok);
        check_results(5, nerr);
        report("S06a", "start on the first idle clock after done", ok && nerr == 0, nerr, 0);

        // ================= S06b: 다음 이미지 마지막 줄 쓰기와 같은 클럭에 start
        for (k = 0; k < 195; k = k + 1) ext_write(SEL_IMEM, k, g_in[6*196 + k]);
        cur_img = 6;
        @(negedge i_clk); i_cen = 1'b0; i_wen = 1'b0; i_addr = {SEL_IMEM, 17'd195}; i_din = g_in[6*196 + 195]; i_start = 1'b1;
        @(negedge i_clk); i_cen = 1'b1; i_wen = 1'b1; i_start = 1'b0;
        wait_done(ok);
        check_results(6, nerr);
        report("S06b", "last image line written in the same clock as start", ok && nerr == 0, nerr, 0);

        // ================= S07: o_done 이 올라간 바로 그 클럭에 start 1클럭 -> 받아들여져야 함 (D01)
        load_image(7);
        start_pulse(1);
        wait (o_done == 1'b1);                         // o_done 이 올라간 엣지 (이때 o_busy 는 0 이어야 함)
        #0.1 seen_busy = o_busy;
        i_start = 1'b1; @(negedge i_clk); @(negedge i_clk); i_start = 1'b0;   // 그 다음 posedge 한 번만 걸치게
        retrig = 0;
        repeat (10) begin @(negedge i_clk); if (o_busy) retrig = 1; end
        $display("[EDGE] S07 start pulse on the clock o_done rose (o_busy=%0d) -> %0s",
                 seen_busy, retrig ? "accepted (new run started)" : "ignored (no new run)");
        if (retrig) wait_done(ok); else ok = 0;
        check_results(7, nerr);
        report("S07", "start on the clock o_done rose is accepted, results", ok && retrig && seen_busy === 1'b0 && nerr == 0, nerr, 0);

        // ================= S12: o_done 만 보고 바로 읽기 (스펙 6-1 의 "o_done = 1 까지 기다리기 -> 읽기"를 글자 그대로 따른 TB) -> 첫 읽기가 맞아야 함
        // 읽을 줄: ACT_A 에서 마지막으로 읽힌 줄(127)과 값이 다른 줄을 고름 (같으면 무시됐는지 구별이 안 됨)
        t1 = 0;
        for (k = 126; k >= 0; k = k - 1) if (g_fc1[7*128 + k] !== g_fc1[7*128 + 127]) t1 = k;
        start_pulse(1);
        wait (o_done == 1'b1);                         // o_done 이 올라간 엣지 (o_busy 도 같은 엣지에 0)
        ext_read(SEL_ACTA, t1, rd);                    // 이 읽기의 주소는 그 다음 posedge 에 걸림
        ext_read(SEL_ACTA, t1, rd2);                   // 한 번 더
        $display("[EDGE] S12 read of ACT_A[%0d] issued right after o_done rose: got %h, second try %h, golden %h", t1, rd, rd2, g_fc1[7*128 + t1]);
        report("S12", "first read right after o_done rose is correct", rd === g_fc1[7*128 + t1] && rd2 === g_fc1[7*128 + t1], 0, 0);

        // ================= S08: i_start 를 끝난 뒤까지 계속 유지 (관찰)
        load_image(8);
        @(negedge i_clk); i_start = 1'b1;
        wait (o_busy == 1'b1);
        @(negedge o_busy);
        retrig = 0;
        repeat (10) begin @(negedge i_clk); if (o_busy) retrig = 1; end
        i_start = 1'b0;
        n_obs = n_obs + 1;
        $display("[EDGE] S08 i_start held high through done : OBSERVE -> %0s",
                 retrig ? "re-triggered (runs again as long as start is high)" : "single run");
        wait_done(ok);
        check_results(8, nerr);
        report("S08", "results after i_start held through done", ok && nerr == 0, nerr, 0);

        // ================= S10: 연속 접근 (cen 계속 0)
        @(negedge i_clk); i_cen = 1'b0; i_wen = 1'b0;
        for (k = 0; k < 8; k = k + 1) begin i_addr = {SEL_IMEM, 17'd0} + k; i_din = 32'hA5A50000 + k; @(negedge i_clk); end
        i_wen = 1'b1; nerr = 0;
        for (k = 0; k < 8; k = k + 1) begin
            i_addr = {SEL_IMEM, 17'd0} + k; @(negedge i_clk);
            if (o_dout !== 32'hA5A50000 + k) nerr = nerr + 1;
        end
        // 쓰기 바로 다음 클럭에 같은 주소 읽기
        i_wen = 1'b0; i_addr = {SEL_IMEM, 17'd20}; i_din = 32'h12345678; @(negedge i_clk);
        i_wen = 1'b1; @(negedge i_clk); if (o_dout !== 32'h12345678) nerr = nerr + 1;
        i_cen = 1'b1;
        if (nerr == 0) begin n_pass = n_pass + 1; $display("[EDGE] S10 burst write / burst read / write-then-read with cen held low : PASS"); end
        else begin n_fail = n_fail + 1; $display("[EDGE] S10 burst access : FAIL (%0d mismatches)", nerr); end
        cur_img = -1;

        // ================= S11: 없는 번호, 범위 밖 주소, 주소 겹침
        ext_write(3'd0, 17'd5, 32'hFFFFFFFF); ext_write(3'd1, 17'd5, 32'hFFFFFFFF);     // WMEM / BIAS 쓰기 시도
        ext_write(3'd6, 17'd5, 32'hFFFFFFFF); ext_write(3'd7, 17'd5, 32'hFFFFFFFF);
        ext_read(3'd0, 17'd5, rd); ext_read(3'd1, 17'd5, rd2);
        n_obs = n_obs + 1;
        $display("[EDGE] S11 read of WMEM (sel 0) = %h, BIAS (sel 1) = %h : OBSERVE (external access to weights/bias is not connected)", rd, rd2);
        ext_write(SEL_IMEM, 17'h00100, 32'hCAFE0001);                                  // 윗주소 비트 [8] = 1, 아래 8비트 = 0
        ext_read(SEL_IMEM, 17'd0, rd);
        n_obs = n_obs + 1;
        $display("[EDGE] S11 write to IMEM address 0x100 then read address 0 = %h : OBSERVE -> %0s", rd,
                 (rd === 32'hCAFE0001) ? "aliased (upper address bits are ignored)" : "not aliased");
        ext_write(SEL_IMEM, 17'd200, 32'hCAFE0002);                                    // 깊이 196 을 넘는 주소
        ext_read(SEL_IMEM, 17'd200, rd);
        n_obs = n_obs + 1;
        $display("[EDGE] S11 write/read IMEM address 200 (depth is 196) = %h : OBSERVE", rd);
        load_image(9);
        start_pulse(1);
        wait_done(ok);
        check_results(9, nerr);
        report("S11", "normal run after odd external accesses (weights intact?)", ok && nerr == 0, nerr, 0);

        // ---------------------------------------------------------------- 끝
        repeat (5) @(negedge i_clk);
        npu_checker.final_report;
        $display("==================================================");
        $display(" tb_edge : %0d PASS, %0d FAIL, %0d OBSERVE | checker errors %0d", n_pass, n_fail, n_obs, npu_checker.nerr);
        if (n_fail == 0 && npu_checker.nerr == 0) $display(" *** tb_edge PASS ***");
        else                                      $display(" *** tb_edge FAIL ***");
        $display("==================================================");
        $finish;
    end

    initial begin
        #(64'd400_000_000);
        $display("[TIMEOUT] tb_edge");
        $finish;
    end
endmodule
