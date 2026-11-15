`timescale 1ns / 1ps
// ============================================================================
// tb_npu_ctrl : D 블록(npu_ctrl) 단위 테스트벤치
//
// 확인 항목 (11/5 조원3 공지 + 스펙 6절)
//   1) 뉴런마다 ISSUE가 L클럭 연속 (FC1 196, FC2 128, FC3 32)
//   2) GO 횟수: FC1 512, FC2 128, FC3 10
//   3) ISSUE 중 o_waddr = w_base + n*L + k, 마지막 주소 117,055
//      o_wbank_addr / o_wbank_sel = 4뱅크 구조 주소, o_xaddr = k, o_baddr = b_base + n
//   4) o_valid = ISSUE를 RD_LAT클럭 늦춘 것, go는 마지막 valid 2클럭 뒤
//   5) o_bias_we는 뉴런마다 정확히 1번, k=0 ISSUE의 RD_LAT클럭 뒤
//   6) GO 다음 클럭의 o_oaddr = n/4 (FC3는 n), o_layer = 그 뉴런의 레이어
//   7) GO 클럭의 o_lane = n%4, o_shift/o_relu_en/o_fc3 = 설정표 값
//   8) start -> done 전체 클럭 수 = 119,009 + 650 x (RD_LAT - 1)  (RD_LAT=1이면 119,009, 2면 119,659)
//      = start 를 받은 엣지부터 o_done 이 올라가는 엣지까지 = o_busy 가 1 인 클럭 수
//   9) 타임아웃: o_done 이 200만 클럭 안에 안 올라오면 FAIL 로 끝냄
//  10) o_done 과 o_busy 가 동시에 1 인 클럭이 없음 (o_done 은 busy 가 0 이 되는 엣지에 올라감, 리뷰 D01)
// 시뮬레이션 시간: 약 1.2 ms (Vivado: run all)
// ============================================================================
`ifndef TB_RD_LAT
  `define TB_RD_LAT 1
`endif

module tb_npu_ctrl;
    localparam RD_LAT = `TB_RD_LAT;
    localparam EXP_CYCLES = 119009 + 650 * (RD_LAT - 1);   // WAIT 가 RD_LAT + 1 클럭이라 뉴런(650개)마다 1클럭씩 늘어남

    reg  i_clk = 1'b0, i_rstn = 1'b0, i_start = 1'b0;
    wire o_busy, o_done, o_rd_en, o_valid, o_acc_clr, o_bias_we, o_go, o_relu_en, o_fc3;
    wire [16:0] o_waddr;
    wire [14:0] o_wbank_addr;
    wire [1:0]  o_wbank_sel, o_layer, o_lane;
    wire [7:0]  o_xaddr, o_oaddr;
    wire [9:0]  o_baddr;
    wire [4:0]  o_shift;

    npu_ctrl #(.RD_LAT(RD_LAT)) u_D (
        .i_clk(i_clk), .i_rstn(i_rstn), .i_start(i_start),
        .o_busy(o_busy), .o_done(o_done),
        .o_rd_en(o_rd_en), .o_waddr(o_waddr), .o_wbank_addr(o_wbank_addr), .o_wbank_sel(o_wbank_sel),
        .o_xaddr(o_xaddr), .o_baddr(o_baddr), .o_oaddr(o_oaddr), .o_layer(o_layer),
        .o_valid(o_valid), .o_acc_clr(o_acc_clr),
        .o_bias_we(o_bias_we), .o_go(o_go), .o_lane(o_lane),
        .o_relu_en(o_relu_en), .o_shift(o_shift), .o_fc3(o_fc3)
    );

    always #5 i_clk = ~i_clk;   // 100 MHz

    // ---- 기대값 계산용 (레이어 설정표) ----
    function integer f_L;     input integer l; f_L     = (l==0) ? 196    : (l==1) ? 128    : 32;    endfunction
    function integer f_N;     input integer l; f_N     = (l==0) ? 512    : (l==1) ? 128    : 10;    endfunction
    function integer f_wbase; input integer l; f_wbase = (l==0) ? 0      : (l==1) ? 100352 : 116736; endfunction
    function integer f_bbase; input integer l; f_bbase = (l==0) ? 0      : (l==1) ? 512    : 640;   endfunction
    function integer f_wbb;   input integer l; f_wbb   = (l==0) ? 0      : (l==1) ? 25088  : 29184; endfunction
    function integer f_shift; input integer l; f_shift = (l==0) ? 11     : (l==1) ? 7      : 0;     endfunction

    // ---- 스코어보드: 지금 몇 번째 레이어/뉴런/줄을 기대하는지 ----
    integer e_layer, e_n, e_k;
    integer nerr, cyc, t_start, t_done;
    integer go_cnt [0:2];
    integer bwe_cnt, issue_run, last_waddr;
    integer issue_hist [0:7];      // ISSUE를 몇 클럭 전에 했는지 (valid 지연 확인용)
    integer last_valid_cyc, i;
    reg     go_d1;  integer go_d1_n, go_d1_layer;

    task err; input [8*80-1:0] msg; begin
        nerr = nerr + 1;
        if (nerr <= 20) $display("[ERR] cyc %0d L%0d n%0d k%0d : %0s", cyc - t_start, e_layer, e_n, e_k, msg);
    end endtask

    initial begin
        nerr = 0; cyc = 0; t_start = 0; t_done = 0;
        go_cnt[0] = 0; go_cnt[1] = 0; go_cnt[2] = 0;
        bwe_cnt = 0; issue_run = 0; last_waddr = -1; last_valid_cyc = -100;
        e_layer = 0; e_n = 0; e_k = 0; go_d1 = 0;
        for (i = 0; i < 8; i = i + 1) issue_hist[i] = 0;

        repeat (5) @(posedge i_clk);
        i_rstn = 1'b1;
        repeat (3) @(posedge i_clk);
        @(negedge i_clk) i_start = 1'b1;
        @(negedge i_clk) i_start = 1'b0;

        wait (o_done === 1'b1);
        @(posedge i_clk); @(posedge i_clk);
        #1;
        // ---- 결과 요약 ----
        $display("--------------------------------------------------");
        $display(" RD_LAT = %0d", RD_LAT);
        $display(" GO count  FC1 %0d (512) / FC2 %0d (128) / FC3 %0d (10)", go_cnt[0], go_cnt[1], go_cnt[2]);
        $display(" bias_we count %0d (650)", bwe_cnt);
        $display(" last o_waddr  %0d (117055)", last_waddr);
        $display(" start->done   %0d clocks (%0d)", t_done - t_start, EXP_CYCLES);
        if (t_done - t_start != EXP_CYCLES) nerr = nerr + 1;
        if (go_cnt[0] != 512 || go_cnt[1] != 128 || go_cnt[2] != 10) nerr = nerr + 1;
        if (bwe_cnt != 650)      nerr = nerr + 1;
        if (last_waddr != 117055) nerr = nerr + 1;
        if (o_busy !== 1'b0 || o_done !== 1'b1) begin nerr = nerr + 1; $display("[ERR] busy/done end state"); end
        if (nerr == 0) $display(" *** tb_npu_ctrl PASS ***");
        else           $display(" *** tb_npu_ctrl FAIL : %0d errors ***", nerr);
        $display("--------------------------------------------------");
        $finish;
    end

    // ---- 타임아웃: 정상이면 약 12만 클럭에 끝남. 200만 클럭(20 ms)이 지나도 안 끝나면 FSM 이 멈춘 것 ----
    initial begin
        #(64'd20_000_000);
        $display("[TIMEOUT] o_done did not rise within 2,000,000 clocks (scoreboard at L%0d n%0d k%0d)", e_layer, e_n, e_k);
        $display(" *** tb_npu_ctrl FAIL : timeout ***");
        $finish;
    end

    // ---- 매 클럭 검사 (posedge 직전 값 = 그 클럭 동안의 값) ----
    always @(posedge i_clk) if (i_rstn) begin
        cyc = cyc + 1;
        if (i_start) t_start = cyc;

        // (6) GO 다음 클럭: 쓸 주소/레이어 확인 (A의 o_we와 같은 클럭)
        if (go_d1) begin
            if (o_layer !== go_d1_layer[1:0]) err("o_layer at write clock");
            if (go_d1_layer == 2) begin
                if (o_oaddr !== go_d1_n[7:0]) err("o_oaddr FC3 != n");
            end else begin
                if (o_oaddr !== (go_d1_n / 4)) err("o_oaddr != n/4");
            end
        end
        go_d1 = 1'b0;

        // 4뱅크 주소는 ISSUE가 아닌 클럭에도 뱅크 깊이(29,280) 안에 있어야 함 (B의 WMEM은 ena가 항상 1)
        if (o_wbank_addr > 15'd29279) err("o_wbank_addr out of range (> 29279)");

        // (4) valid = ISSUE를 RD_LAT클럭 늦춘 것
        if (o_valid !== (issue_hist[RD_LAT-1] != 0)) err("o_valid timing");
        if (o_valid) last_valid_cyc = cyc;

        // (1)(3) ISSUE 클럭: 주소 확인
        if (o_rd_en) begin
            if (o_layer !== e_layer[1:0])                          err("o_layer during ISSUE");
            if (o_xaddr !== e_k[7:0])                              err("o_xaddr != k");
            if (o_waddr !== f_wbase(e_layer) + e_n*f_L(e_layer) + e_k) err("o_waddr");
            if (o_wbank_addr !== f_wbb(e_layer) + (e_n/4)*f_L(e_layer) + e_k) err("o_wbank_addr");
            if (o_wbank_sel !== e_n % 4)                           err("o_wbank_sel");
            if (o_baddr !== f_bbase(e_layer) + e_n)                err("o_baddr");
            last_waddr = o_waddr;
            issue_run  = issue_run + 1;
            e_k        = e_k + 1;
        end

        // (5) bias_we : k=0 ISSUE 의 RD_LAT 클럭 뒤
        if (o_bias_we) bwe_cnt = bwe_cnt + 1;

        // (2)(7) GO 클럭
        if (o_go) begin
            if (!o_acc_clr)                          err("acc_clr not with go");
            if (issue_run != f_L(e_layer))           err("ISSUE length != L");
            if (cyc - last_valid_cyc != 2)           err("go != last valid + 2");
            if (o_lane !== e_n % 4)                  err("o_lane");
            if (o_shift !== f_shift(e_layer))        err("o_shift");
            if (o_relu_en !== (e_layer != 2))        err("o_relu_en");
            if (o_fc3 !== (e_layer == 2))            err("o_fc3");
            go_cnt[e_layer] = go_cnt[e_layer] + 1;
            go_d1 = 1'b1; go_d1_n = e_n; go_d1_layer = e_layer;
            issue_run = 0;
            e_k = 0;
            e_n = e_n + 1;
            if (e_n == f_N(e_layer)) begin e_n = 0; e_layer = e_layer + 1; end
        end

        // posedge 에서 보는 값은 직전 엣지에 정해진 값 -> o_done 이 올라간 엣지 = cyc - 1
        if (o_done && t_done == 0) t_done = cyc - 1;
        if (o_done && o_busy) err("o_done = 1 while o_busy = 1 (done must rise when busy falls)");

        // ISSUE 이력 시프트 + bias_we 위치 확인
        for (i = 7; i > 0; i = i - 1) issue_hist[i] = issue_hist[i-1];
        issue_hist[0] = o_rd_en ? 1 : 0;
    end

    // bias_we 위치: k=0 ISSUE 기준 RD_LAT 클럭 뒤인지 따로 확인
    integer k0_hist [0:7];
    integer j;
    initial for (j = 0; j < 8; j = j + 1) k0_hist[j] = 0;
    always @(posedge i_clk) if (i_rstn) begin
        if (o_bias_we !== (k0_hist[RD_LAT-1] != 0)) begin
            nerr = nerr + 1;
            if (nerr <= 20) $display("[ERR] bias_we timing at cyc %0d", cyc);
        end
        for (j = 7; j > 0; j = j - 1) k0_hist[j] = k0_hist[j-1];
        k0_hist[0] = (o_rd_en && o_xaddr == 8'd0) ? 1 : 0;
    end

    // 파형 덤프 (iverilog용, Vivado에서는 무시해도 됨)
    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("tb_npu_ctrl.vcd");
            $dumpvars(0, tb_npu_ctrl);
        end
    end
endmodule
