`timescale 1ns / 1ps
// ============================================================================
// npu_checker : 리뷰용 "매 클럭 검사기" (테스트벤치 전용, 합성 대상 아님)
//
// 쓰는 법: 기존 TB 를 고치지 않고 시뮬레이션의 두 번째 top 으로 같이 올림.
//   xelab ... work.tb_npu_top work.npu_checker
//   `CHK_TOP = 검사할 npu_top 인스턴스 경로 (기본 tb_npu_top.u_top)
//   `CHK_IMG = 지금 IMEM 에 들어 있는 사진 번호(정수) 경로 (기본 tb_npu_top.img). 단계별 정답 비교에 씀
//   `CHK_STAGES 를 define 하면 golden_check.py 가 만든 누산값/합(acc, acc+bias) 정답과도 비교
//
// D 의 내부 레지스터(r_n, r_k, r_state)는 보지 않음. 블록 경계 신호만 보고,
// 검사기가 따로 세는 (레이어, 뉴런, 줄) 카운터와 그림자 메모리(shadow)로 기대값을 만든다.
//
// 검사 항목 (ID 는 에러 메시지 맨 앞에 찍힘)
//   A1  WMEM 뱅크 주소 <= 29,279 (매 클럭. B 의 WMEM ena 가 항상 1 이라 ISSUE 가 아닐 때도 봄)
//   A2  BMEM 주소 <= 162 (매 클럭)
//   A3  읽기 주소: rd_en 클럭의 layer / xaddr / waddr / wbank_addr / wbank_sel / baddr 가 기대값과 같음
//   A4  valid = rd_en 을 RD_LAT 클럭 늦춘 것
//   A5  valid 클럭의 w = 단일 WMEM hex[waddr], x = 그림자 메모리[줄 k]  (읽은 값이 맞는 값인지)
//   A6  bias_we 는 뉴런당 정확히 1번, 그 클럭의 bias = bias hex[b_base + n]
//   A7  go: 마지막 valid 의 정확히 2클럭 뒤, valid 개수 = L, acc_clr = go, lane/shift/relu/fc3/layer = 기대값
//   A8  A 의 o_we 는 go 다음 클럭에만(FC1/FC2 는 lane 3, FC3 는 매번), 그 클럭의 layer/oaddr/wdata = 기대값
//       (wdata 기대값은 검사기가 acc + bias -> ReLU -> shift -> 포화 -> 묶기를 따로 계산)
//   A9  같은 메모리를 같은 클럭에 읽고 쓰지 않음, 쓰기 주소 범위(ACT_A <= 127, ACT_B <= 31, OMEM <= 9)
//   A10 busy 동안 BRAM 포트(ena/wea/addr/din)는 내부 신호만으로 결정됨 = 외부 접근 무시
//   A11 외부 읽기: 주소 준 다음 클럭의 o_dout = 그림자 메모리 값
//   A12 start/busy/done 규칙: busy 는 받아들인 start 다음 클럭에 1, done 은 busy 가 0 이 되는 엣지에 같이 올라가고
//       (done = 1 && busy = 1 인 클럭 없음, 11/15 D01) 다음 start 까지 유지
//   A13 한 번의 연산 끝: go 512/128/10, we 128/32/10, valid 117,056, bias_we 650, 줄마다 정확히 1번 쓰기,
//       start -> done = 119,009 + 650 x (RD_LAT - 1) 클럭
//   A14 제어 신호에 X 없음, valid 클럭의 x/w, go 클럭의 acc, we 클럭의 wdata 에 X 없음
//   A15 (CHK_STAGES) go 클럭의 acc, acc + bias 가 파이썬 독립 모델 값과 같음
// ============================================================================
`ifndef CHK_TOP
  `define CHK_TOP tb_npu_top.u_top
`endif
`ifndef CHK_IMG
  `define CHK_IMG tb_npu_top.img
`endif
`ifndef CHK_RD_LAT
  `define CHK_RD_LAT 1
`endif
`ifndef HEX_DIR
  `define HEX_DIR "hex/"
`endif

module npu_checker;
    localparam RD = `CHK_RD_LAT;

    // ---------------------------------------------------------------- 볼 신호 (npu_top 경계 + 블록 사이 선)
    wire        rstn    = `CHK_TOP.i_rstn;
    wire        cen     = `CHK_TOP.i_cen;
    wire        wen     = `CHK_TOP.i_wen;
    wire [19:0] addr    = `CHK_TOP.i_addr;
    wire [31:0] din     = `CHK_TOP.i_din;
    wire [31:0] dout    = `CHK_TOP.o_dout;
    wire        start   = `CHK_TOP.i_start;
    wire        busy    = `CHK_TOP.o_busy;
    wire        done    = `CHK_TOP.o_done;
    wire [31:0] x       = `CHK_TOP.x;
    wire [31:0] w       = `CHK_TOP.w;
    wire [31:0] bias    = `CHK_TOP.bias;
    wire [31:0] acc     = `CHK_TOP.acc;
    wire [31:0] wdata   = `CHK_TOP.wdata;
    wire        we      = `CHK_TOP.we;
    wire        valid   = `CHK_TOP.valid;
    wire        acc_clr = `CHK_TOP.acc_clr;
    wire        bias_we = `CHK_TOP.bias_we;
    wire        go      = `CHK_TOP.go;
    wire        relu_en = `CHK_TOP.relu_en;
    wire        fc3     = `CHK_TOP.fc3;
    wire        rd_en   = `CHK_TOP.rd_en;
    wire [1:0]  lane    = `CHK_TOP.lane;
    wire [1:0]  layer   = `CHK_TOP.layer;
    wire [1:0]  wbsel   = `CHK_TOP.wbank_sel;
    wire [4:0]  shift   = `CHK_TOP.shift;
    wire [16:0] waddr   = `CHK_TOP.waddr;
    wire [14:0] wbaddr  = `CHK_TOP.wbank_addr;
    wire [7:0]  xaddr   = `CHK_TOP.xaddr;
    wire [7:0]  oaddr   = `CHK_TOP.oaddr;
    wire [9:0]  baddr   = `CHK_TOP.baddr;
    // BRAM 바로 앞 (조원2 memory_controller 포트)
    wire [14:0] m_waddr   = `CHK_TOP.u_B.u_mem.weight_addr;
    wire [7:0]  m_baddr   = `CHK_TOP.u_B.u_mem.bias_addr;
    wire        ia_req    = `CHK_TOP.u_B.u_mem.imem_a_req;
    wire        ia_we     = `CHK_TOP.u_B.u_mem.imem_a_we;
    wire [7:0]  ia_addr   = `CHK_TOP.u_B.u_mem.imem_a_addr;
    wire        aa_req    = `CHK_TOP.u_B.u_mem.act_a_req;
    wire        aa_we     = `CHK_TOP.u_B.u_mem.act_a_we;
    wire [6:0]  aa_addr   = `CHK_TOP.u_B.u_mem.act_a_addr;
    wire [31:0] aa_din    = `CHK_TOP.u_B.u_mem.act_a_din;
    wire        ab_req    = `CHK_TOP.u_B.u_mem.act_b_req;
    wire        ab_we     = `CHK_TOP.u_B.u_mem.act_b_we;
    wire [4:0]  ab_addr   = `CHK_TOP.u_B.u_mem.act_b_addr;
    wire [31:0] ab_din    = `CHK_TOP.u_B.u_mem.act_b_din;
    wire        om_req    = `CHK_TOP.u_B.u_mem.omem_req;
    wire        om_we     = `CHK_TOP.u_B.u_mem.omem_we;
    wire [3:0]  om_addr   = `CHK_TOP.u_B.u_mem.omem_addr;
    wire [31:0] om_din    = `CHK_TOP.u_B.u_mem.omem_din;

    // ---------------------------------------------------------------- 정답 파일
    reg [31:0] m_w [0:117055];      // 단일 WMEM (스펙 주소)
    reg [31:0] m_b [0:649];
`ifdef CHK_STAGES
    reg [31:0] g_acc1 [0:51199];  reg [31:0] g_sum1 [0:51199];
    reg [31:0] g_acc2 [0:12799];  reg [31:0] g_sum2 [0:12799];
    reg [31:0] g_acc3 [0:999];    reg [31:0] g_sum3 [0:999];
`endif

    function integer fL;     input integer l; fL     = (l==0) ? 196 : (l==1) ? 128    : 32;     endfunction
    function integer fN;     input integer l; fN     = (l==0) ? 512 : (l==1) ? 128    : 10;     endfunction
    function integer fWB;    input integer l; fWB    = (l==0) ? 0   : (l==1) ? 100352 : 116736; endfunction
    function integer fBB;    input integer l; fBB    = (l==0) ? 0   : (l==1) ? 512    : 640;    endfunction
    function integer fWBB;   input integer l; fWBB   = (l==0) ? 0   : (l==1) ? 25088  : 29184;  endfunction
    function integer fSH;    input integer l; fSH    = (l==0) ? 11  : (l==1) ? 7      : 0;      endfunction

    // ---------------------------------------------------------------- 상태
    integer nerr, nchk, cyc, nrun;
    integer e_layer, e_n, e_k;                 // 다음 rd_en 이 가리켜야 할 위치
    integer valid_run, bwe_run;                // 이번 뉴런에서 센 valid / bias_we 개수
    integer go_cnt [0:2], we_cnt [0:2], n_valid, n_bwe, t_start, n_ext_ign, n_dout_tgl;
    integer wr_a [0:127], wr_b [0:31], wr_o [0:15];
    reg [31:0] sh_i [0:255]; reg sh_i_v [0:255];        // 그림자 메모리 + "한 번이라도 쓴 적 있음" 표시
    reg [31:0] sh_a [0:127]; reg sh_a_v [0:127];
    reg [31:0] sh_b [0:31];  reg sh_b_v [0:31];
    reg [31:0] sh_o [0:15];  reg sh_o_v [0:15];
    // 지연 기록 (index 0 = 1클럭 전)
    reg        h_rd [0:3]; reg [16:0] h_wa [0:3]; integer h_k [0:3]; integer h_l [0:3];
    reg        v_d1, v_d2, busy_d1, done_d1, start_d1;
    reg        pend_we; reg [31:0] pend_data; integer pend_layer, pend_addr;
    reg        pend_rd, pend_rd_v; reg [31:0] pend_rd_data; reg [19:0] pend_rd_addr;
    reg [31:0] bias_lat, exp_pack, dout_d1;
    reg signed [31:0] s_sum, s_r;
    reg [7:0]  y8;
    integer    i, img, gi;
    reg        in_run;

    task err; input [8*96-1:0] msg; begin
        nerr = nerr + 1;
        if (nerr <= 40) $display("[CHK-ERR] %0s | t=%0t run %0d img %0d  L%0d n%0d k%0d", msg, $time, nrun, `CHK_IMG, e_layer, e_n, e_k);
    end endtask
    // 조건 검사 한 번 = nchk 1 증가
    task chk; input cond; input [8*96-1:0] msg; begin
        nchk = nchk + 1;
        if (cond !== 1'b1) err(msg);
    end endtask

    task clear_run; begin
        e_layer = 0; e_n = 0; e_k = 0; valid_run = 0; bwe_run = 0;
        go_cnt[0] = 0; go_cnt[1] = 0; go_cnt[2] = 0; we_cnt[0] = 0; we_cnt[1] = 0; we_cnt[2] = 0;
        n_valid = 0; n_bwe = 0;
        for (i = 0; i < 128; i = i + 1) wr_a[i] = 0;
        for (i = 0; i < 32;  i = i + 1) wr_b[i] = 0;
        for (i = 0; i < 16;  i = i + 1) wr_o[i] = 0;
    end endtask

    task clear_track; begin          // 리셋 때
        clear_run;
        for (i = 0; i < 4; i = i + 1) begin h_rd[i] = 1'b0; h_wa[i] = 17'd0; h_k[i] = 0; h_l[i] = 0; end
        v_d1 = 1'b0; v_d2 = 1'b0; busy_d1 = 1'b0; done_d1 = 1'b0; start_d1 = 1'b0;
        pend_we = 1'b0; pend_rd = 1'b0; exp_pack = 32'd0; bias_lat = 32'd0; in_run = 1'b0;
    end endtask

    initial begin
        $readmemh({`HEX_DIR, "wmem_single.hex"}, m_w);
        $readmemh({`HEX_DIR, "bias_single.hex"}, m_b);
`ifdef CHK_STAGES
        $readmemh({`HEX_DIR, "rev_acc1.hex"}, g_acc1); $readmemh({`HEX_DIR, "rev_sum1.hex"}, g_sum1);
        $readmemh({`HEX_DIR, "rev_acc2.hex"}, g_acc2); $readmemh({`HEX_DIR, "rev_sum2.hex"}, g_sum2);
        $readmemh({`HEX_DIR, "rev_acc3.hex"}, g_acc3); $readmemh({`HEX_DIR, "rev_sum3.hex"}, g_sum3);
`endif
        nerr = 0; nchk = 0; cyc = 0; nrun = 0; n_ext_ign = 0; n_dout_tgl = 0; dout_d1 = 32'd0;
        for (i = 0; i < 256; i = i + 1) begin sh_i[i] = 32'd0; sh_i_v[i] = 1'b0; end
        for (i = 0; i < 128; i = i + 1) begin sh_a[i] = 32'd0; sh_a_v[i] = 1'b0; end
        for (i = 0; i < 32;  i = i + 1) begin sh_b[i] = 32'd0; sh_b_v[i] = 1'b0; end
        for (i = 0; i < 16;  i = i + 1) begin sh_o[i] = 32'd0; sh_o_v[i] = 1'b0; end
        clear_track;
    end

    // 비동기 리셋이 클럭 사이에 들어와도 추적 상태를 바로 지움
    always @(negedge rstn) begin
        if (in_run) $display("[CHK] reset during run %0d (L%0d n%0d k%0d) at t=%0t", nrun, e_layer, e_n, e_k, $time);
        clear_track;
    end

    // TB 가 끝에서 부를 수 있는 최종 보고
    task final_report; begin
        $display("[CHK] FINAL : %0d runs, %0d checks evaluated, %0d errors, ext access ignored while busy %0d clk, o_dout changed while busy %0d clk",
                 nrun, nchk, nerr, n_ext_ign, n_dout_tgl);
    end endtask

    // ---------------------------------------------------------------- 매 클럭 검사 (posedge 직전 값 = 그 클럭 동안의 값)
    always @(posedge `CHK_TOP.i_clk) begin
        if (!rstn) begin
            clear_track;
            // 리셋 중에도 외부 쓰기는 BRAM 에 들어감 (BRAM 은 리셋이 없고, 리셋 중 busy = 0) -> 그림자도 갱신
            if (!busy && !cen && !wen) begin
                case (addr[19:17])
                    3'd2: if (addr[7:0] < 196) begin sh_i[addr[7:0]] = din; sh_i_v[addr[7:0]] = 1'b1; end
                    3'd3: begin sh_a[addr[6:0]] = din; sh_a_v[addr[6:0]] = 1'b1; end
                    3'd4: begin sh_b[addr[4:0]] = din; sh_b_v[addr[4:0]] = 1'b1; end
                    3'd5: if (addr[3:0] < 10) begin sh_o[addr[3:0]] = din; sh_o_v[addr[3:0]] = 1'b1; end
                    default: ;
                endcase
            end
        end else begin
            cyc = cyc + 1;
            img = `CHK_IMG;

            // ---- A14: 제어 신호에 X 없음
            chk(^{busy, done, rd_en, valid, acc_clr, bias_we, go, we, relu_en, fc3, lane, layer, wbsel, shift,
                  waddr, wbaddr, xaddr, oaddr, baddr} !== 1'bx, "A14 X on control signal");

            // ---- A11: 외부 읽기 데이터 (앞 클럭에 받은 읽기)
            if (pend_rd) begin
                if (pend_rd_v) chk(dout === pend_rd_data, "A11 o_dout != shadow memory (external read)");
                pend_rd = 1'b0;
            end
            if (busy && busy_d1 && dout !== dout_d1) n_dout_tgl = n_dout_tgl + 1;   // 참고용: busy 중 o_dout 변화

            // ---- A12: start / busy / done 규칙
            if (start_d1 && !busy_d1) begin
                chk(busy === 1'b1, "A12 busy not 1 the clock after accepted start");
                chk(done === 1'b0, "A12 done not cleared by start");
            end
            if (busy && !busy_d1)  chk(start_d1 === 1'b1, "A12 busy rose without start");
            if (!busy && busy_d1)  chk(done === 1'b1, "A12 busy fell but done != 1");
            if (done && !done_d1)  chk(busy_d1 === 1'b1 && busy === 1'b0, "A12 done did not rise exactly when busy fell");
            chk(!(done === 1'b1 && busy === 1'b1), "A12 done = 1 while busy = 1");
            if (!done && done_d1)  chk(start_d1 === 1'b1 && !busy_d1, "A12 done fell without a new start");
            if (!busy) begin
                chk(!rd_en && !valid && !go && !acc_clr && !bias_we, "A12 activity (rd_en/valid/go/bias_we) while idle");
            end

            // ---- A13: 연산 한 번이 끝났을 때 (busy 가 내려가고 done 이 올라간 첫 IDLE 클럭에 집계)
            if (!busy && busy_d1 && in_run) begin
                chk(go_cnt[0] == 512 && go_cnt[1] == 128 && go_cnt[2] == 10, "A13 go count != 512/128/10");
                chk(we_cnt[0] == 128 && we_cnt[1] == 32  && we_cnt[2] == 10, "A13 write count != 128/32/10");
                chk(n_valid == 117056, "A13 valid count != 117056");
                chk(n_bwe == 650, "A13 bias_we count != 650");
                for (i = 0; i < 128; i = i + 1) if (wr_a[i] != 1) err("A13 ACT_A line not written exactly once");
                for (i = 0; i < 32;  i = i + 1) if (wr_b[i] != 1) err("A13 ACT_B line not written exactly once");
                for (i = 0; i < 10;  i = i + 1) if (wr_o[i] != 1) err("A13 OMEM line not written exactly once");
                nchk = nchk + 170;
                chk((cyc - 1 - t_start) == 119009 + 650 * (RD - 1), "A13 start->done clock count");
                $display("[CHK] run %0d img %0d : go %0d/%0d/%0d  we %0d/%0d/%0d  valid %0d  bias_we %0d  start->done %0d clk | checks %0d, errors %0d",
                         nrun, img, go_cnt[0], go_cnt[1], go_cnt[2], we_cnt[0], we_cnt[1], we_cnt[2], n_valid, n_bwe,
                         cyc - 1 - t_start, nchk, nerr);
                in_run = 1'b0;
            end

            // ---- 받아들인 start: 새 연산 시작
            if (start && !busy) begin
                clear_run;
                nrun = nrun + 1; t_start = cyc; in_run = 1'b1;
            end

            // ---- A8 / A9: 쓰기 (앞 클럭 go 의 결과)
            chk(we === pend_we, "A8 o_we timing (must be exactly go+1, lane 3 or FC3)");
            if (we) begin
                chk(busy === 1'b1, "A8 write while not busy");
                chk(^wdata !== 1'bx, "A14 X on wdata");
                if (pend_we) begin
                    chk(layer === pend_layer, "A8 layer at write clock != layer of that neuron");
                    chk(oaddr === pend_addr,  "A8 oaddr at write clock");
                    chk(wdata === pend_data,  "A8 wdata != independently computed post-processing result");
                    // A9: 주소 범위 + 같은 메모리 동시 읽기 금지 (FC1: 읽기 IMEM, FC2: ACT_A, FC3: ACT_B)
                    chk(pend_addr <= ((pend_layer == 0) ? 127 : (pend_layer == 1) ? 31 : 9), "A9 write address out of range");
                    chk(!(rd_en && (layer == pend_layer + 1)), "A9 read and write of the same memory in one clock");
                    // BRAM 포트에 실제로 그 쓰기가 갔는지
                    case (pend_layer)
                        0: chk(aa_req && aa_we && aa_addr === pend_addr && aa_din === wdata, "A8 ACT_A BRAM port != write");
                        1: chk(ab_req && ab_we && ab_addr === pend_addr && ab_din === wdata, "A8 ACT_B BRAM port != write");
                        default: chk(om_req && om_we && om_addr === pend_addr && om_din === wdata, "A8 OMEM BRAM port != write");
                    endcase
                    case (pend_layer)
                        0: begin sh_a[pend_addr] = wdata; sh_a_v[pend_addr] = 1'b1; wr_a[pend_addr] = wr_a[pend_addr] + 1; end
                        1: begin sh_b[pend_addr] = wdata; sh_b_v[pend_addr] = 1'b1; wr_b[pend_addr] = wr_b[pend_addr] + 1; end
                        default: begin sh_o[pend_addr] = wdata; sh_o_v[pend_addr] = 1'b1; wr_o[pend_addr] = wr_o[pend_addr] + 1; end
                    endcase
                    we_cnt[pend_layer] = we_cnt[pend_layer] + 1;
                end
            end
            pend_we = 1'b0;

            // ---- A3: 읽기 주소 (ISSUE 클럭)
            if (rd_en) begin
                chk(busy === 1'b1, "A3 rd_en while not busy");
                chk(e_layer <= 2 && e_k < fL(e_layer), "A3 more rd_en clocks than L (or after last layer)");
                chk(layer  === e_layer, "A3 layer during read");
                chk(xaddr  === e_k,     "A3 xaddr != k");
                chk(waddr  === fWB(e_layer) + e_n * fL(e_layer) + e_k, "A3 waddr != w_base + n*L + k");
                chk(wbaddr === fWBB(e_layer) + (e_n / 4) * fL(e_layer) + e_k, "A3 wbank_addr != wbank_base + (n/4)*L + k");
                chk(wbsel  === e_n % 4, "A3 wbank_sel != n%4");
                chk(baddr  === fBB(e_layer) + e_n, "A3 baddr != b_base + n");
                chk(m_waddr === wbaddr, "A3 WMEM BRAM address != wbank_addr");
                case (e_layer)
                    0: chk(ia_req && !ia_we && ia_addr === e_k, "A3 IMEM_A BRAM port != read line k");
                    1: chk(aa_req && !aa_we && aa_addr === e_k, "A3 ACT_A BRAM port != read line k");
                    default: chk(ab_req && !ab_we && ab_addr === e_k, "A3 ACT_B BRAM port != read line k");
                endcase
            end

            // ---- A4 / A5: valid 와 읽은 데이터
            chk(valid === h_rd[RD-1], "A4 valid != rd_en delayed by RD_LAT");
            if (valid) begin
                n_valid = n_valid + 1; valid_run = valid_run + 1;
                chk(^w !== 1'bx && ^x !== 1'bx, "A14 X on x/w at valid");
                chk(w === m_w[h_wa[RD-1]], "A5 w != WMEM hex[waddr] (4-bank mapping / bank select)");
                case (h_l[RD-1])
                    0: if (sh_i_v[h_k[RD-1]]) chk(x === sh_i[h_k[RD-1]], "A5 x != IMEM_A shadow[k]");
                    1: if (sh_a_v[h_k[RD-1]]) chk(x === sh_a[h_k[RD-1]], "A5 x != ACT_A shadow[k]");
                    default: if (sh_b_v[h_k[RD-1]]) chk(x === sh_b[h_k[RD-1]], "A5 x != ACT_B shadow[k]");
                endcase
            end

            // ---- A6: bias
            if (bias_we) begin
                n_bwe = n_bwe + 1; bwe_run = bwe_run + 1;
                chk(busy === 1'b1, "A6 bias_we while not busy");
                chk(bias === m_b[fBB(e_layer) + e_n], "A6 bias != bias hex[b_base + n]");
                chk(m_baddr === ((fBB(e_layer) + e_n) / 4), "A6 BMEM BRAM address != (b_base + n)/4");
                bias_lat = bias;
            end

            // ---- A7: go
            chk(acc_clr === go, "A7 acc_clr != go");
            if (go) begin
                chk(!valid && !v_d1 && v_d2, "A7 go is not exactly 2 clocks after the last valid");
                chk(valid_run == fL(e_layer) && e_k == fL(e_layer), "A7 valid/rd_en count of this neuron != L");
                chk(bwe_run == 1, "A6 bias_we count of this neuron != 1");
                chk(lane === e_n % 4, "A7 lane != n%4");
                chk(layer === e_layer, "A7 layer at go");
                chk(shift === fSH(e_layer) && relu_en === (e_layer != 2) && fc3 === (e_layer == 2), "A7 shift/relu_en/fc3");
                chk(^acc !== 1'bx, "A14 X on acc at go");
                // 후처리 기대값을 따로 계산
                s_sum = $signed(acc) + $signed(bias_lat);
`ifdef CHK_STAGES
                if (img >= 0 && img < 100) begin
                    gi = img * fN(e_layer) + e_n;
                    case (e_layer)
                        0: begin chk(acc === g_acc1[gi], "A15 acc != python model (FC1)"); chk(s_sum === g_sum1[gi], "A15 acc+bias != python model (FC1)"); end
                        1: begin chk(acc === g_acc2[gi], "A15 acc != python model (FC2)"); chk(s_sum === g_sum2[gi], "A15 acc+bias != python model (FC2)"); end
                        default: begin chk(acc === g_acc3[gi], "A15 acc != python model (FC3)"); chk(s_sum === g_sum3[gi], "A15 acc+bias != python model (FC3)"); end
                    endcase
                end
`endif
                if (e_layer == 2) begin
                    pend_we = 1'b1; pend_data = s_sum; pend_addr = e_n;
                end else begin
                    s_r = (s_sum < 0) ? 32'sd0 : s_sum;
                    s_r = s_r >>> fSH(e_layer);
                    y8  = (s_r > 32'sd127) ? 8'd127 : s_r[7:0];
                    case (e_n % 4)
                        0: exp_pack[7:0]   = y8;
                        1: exp_pack[15:8]  = y8;
                        2: exp_pack[23:16] = y8;
                        default: exp_pack[31:24] = y8;
                    endcase
                    pend_we = (e_n % 4 == 3); pend_data = exp_pack; pend_addr = e_n / 4;
                end
                pend_layer = e_layer;
                go_cnt[e_layer] = go_cnt[e_layer] + 1;
                e_k = 0; valid_run = 0; bwe_run = 0;
                e_n = e_n + 1;
                if (e_n == fN(e_layer)) begin e_n = 0; e_layer = e_layer + 1; end
            end else if (rd_en) begin
                e_k = e_k + 1;
            end

            // ---- A1 / A2: 항상 켜져 있는 WMEM / BMEM 의 주소 범위
            chk(m_waddr <= 15'd29279, "A1 WMEM bank address > 29279");
            chk(m_baddr <= 8'd162,    "A2 BMEM address > 162");

            // ---- A10: busy 동안 BRAM 포트는 내부 신호만으로 결정
            if (busy) begin
                chk(ia_we === 1'b0 && ia_req === (rd_en && layer == 2'd0), "A10 IMEM_A port affected while busy");
                chk(aa_we === (we && layer == 2'd0) && aa_req === ((rd_en && layer == 2'd1) || (we && layer == 2'd0)), "A10 ACT_A port while busy");
                chk(ab_we === (we && layer == 2'd1) && ab_req === ((rd_en && layer == 2'd2) || (we && layer == 2'd1)), "A10 ACT_B port while busy");
                chk(om_we === (we && layer == 2'd2) && om_req === (we && layer == 2'd2), "A10 OMEM port while busy");
                if (!cen) n_ext_ign = n_ext_ign + 1;
            end else begin
                // ---- 외부 접근 (스펙: busy = 0 일 때만 받음) -> 그림자 메모리 갱신 / A11 예약
                if (!cen && !wen) begin
                    case (addr[19:17])
                        3'd2: if (addr[7:0] < 196) begin sh_i[addr[7:0]] = din; sh_i_v[addr[7:0]] = 1'b1; end
                        3'd3: begin sh_a[addr[6:0]] = din; sh_a_v[addr[6:0]] = 1'b1; end
                        3'd4: begin sh_b[addr[4:0]] = din; sh_b_v[addr[4:0]] = 1'b1; end
                        3'd5: if (addr[3:0] < 10) begin sh_o[addr[3:0]] = din; sh_o_v[addr[3:0]] = 1'b1; end
                        default: ;
                    endcase
                end
                if (!cen && wen) begin
                    pend_rd = 1'b1; pend_rd_addr = addr; pend_rd_v = 1'b0; pend_rd_data = 32'd0;
                    case (addr[19:17])
                        3'd2: if (addr[7:0] < 196) begin pend_rd_v = sh_i_v[addr[7:0]]; pend_rd_data = sh_i[addr[7:0]]; end
                        3'd3: begin pend_rd_v = sh_a_v[addr[6:0]]; pend_rd_data = sh_a[addr[6:0]]; end
                        3'd4: begin pend_rd_v = sh_b_v[addr[4:0]]; pend_rd_data = sh_b[addr[4:0]]; end
                        3'd5: if (addr[3:0] < 10) begin pend_rd_v = sh_o_v[addr[3:0]]; pend_rd_data = sh_o[addr[3:0]]; end
                        default: begin pend_rd_v = 1'b1; pend_rd_data = 32'd0; end     // WMEM/BIAS/없는 번호: 0 이 나와야 함
                    endcase
                end
            end

            // ---- 지연 기록 갱신
            for (i = 3; i > 0; i = i - 1) begin h_rd[i] = h_rd[i-1]; h_wa[i] = h_wa[i-1]; h_k[i] = h_k[i-1]; h_l[i] = h_l[i-1]; end
            h_rd[0] = rd_en; h_wa[0] = waddr; h_k[0] = xaddr; h_l[0] = layer;
            v_d2 = v_d1; v_d1 = valid;
            busy_d1 = busy; done_d1 = done; start_d1 = start; dout_d1 = dout;
        end
    end
endmodule
