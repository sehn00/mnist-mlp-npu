"""
mutate.py : 버그 주입(뮤테이션) 테스트 준비 + 결과 정리 (리뷰 1단계 7번)

원본 rtl/ 은 건드리지 않는다. 뮤턴트마다 build/review/mut/<ID>/rtl/ 에 rtl 6개를 복사하고
그 복사본 한 군데(또는 두 군데)만 바꾼다. 실행은 run_mutants.sh 가 xrun.sh 로 한다.

  python scripts/review/mutate.py prepare     복사본 만들기 + build/review/mut/list.txt
  python scripts/review/mutate.py survivors   기존 통합 TB(골든 2장)를 통과해 버린 뮤턴트 ID 출력
  python scripts/review/mutate.py report      reports/review/mutation_results.md 작성

판정 열
  unit   : 기존 tb_npu_ctrl (D 뮤턴트만)                  FAIL = 잡음
  top    : 기존 tb_npu_top, golden 사진 2장                FAIL / TIMEOUT = 잡음
  chk    : 같은 시뮬레이션에 붙인 npu_checker 의 에러 수   > 0 = 잡음
  stress : top 을 통과한 것만. 기존 tb_npu_top + 합성 이미지 16장 (gen_stress.py)
  edge   : top 을 통과한 것만. tb_edge + npu_checker
"""
import os, re, shutil, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MUT = os.path.join(ROOT, "build", "review", "mut")
CT, MC, PP, PE = "npu_ctrl.v", "npu_mem_ctrl.v", "npu_postproc.v", "npu_pe_array.v"

# (ID, 파일, 설명, [(원래 문자열, 바꾼 문자열), ...], 예상)
#   예상: "detect" = 기능 버그라 잡혀야 함, "equiv" = 동작이 같아서 못 잡는 게 정상,
#         "benign" = 최종 결과는 같지만 타이밍/프로토콜이 달라짐 (통합 골든 비교로는 안 보임)
M = [
 ("D01", CT, "shift FC1 11 -> 10",                         [("w_shift = 5'd11", "w_shift = 5'd10")], "detect"),
 ("D02", CT, "shift FC2 7 -> 8",                           [("w_shift = 5'd7; ", "w_shift = 5'd8; ")], "detect"),
 ("D03", CT, "L FC2 128 -> 127 (줄 하나 덜 읽음)",          [("w_L = 8'd128", "w_L = 8'd127")], "detect"),
 ("D04", CT, "N FC3 10 -> 9 (마지막 뉴런 빠짐)",            [("w_N = 10'd10;", "w_N = 10'd9;")], "detect"),
 ("D05", CT, "N FC1 512 -> 511",                           [("w_N = 10'd512", "w_N = 10'd511")], "detect"),
 ("D06", CT, "o_valid 1클럭 늦음",                          [("assign o_valid      = r_valid_sr[RD_LAT-1];", "assign o_valid      = r_valid_sr[RD_LAT];")], "detect"),
 ("D07", CT, "o_valid 1클럭 빠름",                          [("assign o_valid      = r_valid_sr[RD_LAT-1];", "assign o_valid      = (RD_LAT == 1) ? w_issue : r_valid_sr[RD_LAT-2];")], "detect"),
 ("D08", CT, "o_bias_we 1클럭 늦음",                        [("assign o_bias_we    = r_bwe_sr[RD_LAT-1];", "assign o_bias_we    = r_bwe_sr[RD_LAT];")], "benign"),
 ("D09", CT, "o_bias_we 1클럭 빠름",                        [("assign o_bias_we    = r_bwe_sr[RD_LAT-1];", "assign o_bias_we    = (RD_LAT == 1) ? w_issue_k0 : r_bwe_sr[RD_LAT-2];")], "detect"),
 ("D10", CT, "go 1클럭 빠름 (WAIT 1클럭 짧음)",             [("(r_wait_cnt == RD_LAT);", "(r_wait_cnt == RD_LAT - 1);")], "detect"),
 ("D11", CT, "go 1클럭 늦음 (WAIT 1클럭 김)",               [("(r_wait_cnt == RD_LAT);", "(r_wait_cnt == RD_LAT + 1);")], "benign"),
 ("D12", CT, "o_lane 순서 뒤집힘 (3 - n%4)",                [("assign o_lane       = r_n[1:0];", "assign o_lane       = ~r_n[1:0];")], "detect"),
 ("D13", CT, "o_wbank_sel = n%4 + 1",                      [("assign o_wbank_sel  = r_n[1:0];", "assign o_wbank_sel  = r_n[1:0] + 2'd1;")], "detect"),
 ("D14", CT, "o_wbank_addr + 1",                           [("assign o_wbank_addr = r_wb_ptr;", "assign o_wbank_addr = r_wb_ptr + 15'd1;")], "detect"),
 ("D15", CT, "o_xaddr + 1",                                [("assign o_xaddr      = r_k;", "assign o_xaddr      = r_k + 8'd1;")], "detect"),
 ("D16", CT, "o_baddr + 1",                                [("assign o_baddr      = r_b_ptr;", "assign o_baddr      = r_b_ptr + 10'd1;")], "detect"),
 ("D17", CT, "o_oaddr + 1 (FC1/FC2)",                      [("r_oaddr <= w_fc3 ? r_n[7:0] : {1'b0, r_n[8:2]};", "r_oaddr <= w_fc3 ? r_n[7:0] : ({1'b0, r_n[8:2]} + 8'd1);")], "detect"),
 ("D18", CT, "o_oaddr FC3 도 n/4",                          [("r_oaddr <= w_fc3 ? r_n[7:0] : {1'b0, r_n[8:2]};", "r_oaddr <= {1'b0, r_n[8:2]};")], "detect"),
 ("D19", CT, "FC3 wbank_base 29184 -> 29185",              [("w_next_wbbase = 15'd29184;", "w_next_wbbase = 15'd29185;")], "detect"),
 ("D20", CT, "FC2 relu_en = 0",                            [("w_shift = 5'd7;  w_relu = 1'b1;", "w_shift = 5'd7;  w_relu = 1'b0;")], "detect"),
 ("D21", CT, "o_fc3 항상 0",                                [("w_relu = 1'b0; w_fc3 = 1'b1;", "w_relu = 1'b0; w_fc3 = 1'b0;")], "detect"),
 ("D22", CT, "뱅크 포인터 되돌림 조건 lane != 3 -> != 2",   [("if (r_n[1:0] != 2'd3) r_wb_ptr", "if (r_n[1:0] != 2'd2) r_wb_ptr")], "detect"),
 ("D23", CT, "o_acc_clr 항상 0",                            [("assign o_acc_clr    = (r_state == S_GO);", "assign o_acc_clr    = 1'b0;")], "detect"),
 ("D24", CT, "o_waddr + 1 (top 에서는 안 쓰는 출력)",       [("assign o_waddr      = r_w_ptr;", "assign o_waddr      = r_w_ptr + 17'd1;")], "benign"),
 ("D25", CT, "LAYER 에서 wbank 포인터 다시 안 넣음",        [("r_wb_ptr <= w_next_wbbase;", "r_wb_ptr <= r_wb_ptr;")], "equiv"),
 ("D26", CT, "o_done 이 1클럭만 1 (유지 안 함)",            [("r_state <= S_IDLE;\n                end\n\n                default", "r_state <= S_IDLE; o_done <= 1'b0;\n                end\n\n                default")], "detect"),
 ("D27", CT, "o_busy 가 DONE 클럭에 0 (1클럭 일찍 내려감)", [("assign o_busy       = (r_state != S_IDLE);", "assign o_busy       = (r_state != S_IDLE) && (r_state != S_DONE);")], "detect"),
 ("D28", CT, "o_rd_en 이 WAIT 에서도 1",                    [("assign o_rd_en      = w_issue;", "assign o_rd_en      = w_issue || (r_state == S_WAIT);")], "benign"),
 ("B01", MC, "busy 중 외부 쓰기를 IMEM 으로 통과시킴",       [("wire       w_ext_en  = !i_busy && !i_cen;", "wire       w_ext_en  = !i_cen;"),
                                                            ("wire        w_imem_we   = i_busy ? 1'b0      : (w_ext_we && w_ext_sel == 3'd2);", "wire        w_imem_we   = (w_ext_we && w_ext_sel == 3'd2);")], "detect"),
 ("B02", MC, "FC2 결과 쓰기 대상 레이어 번호 틀림",          [("wire w_wr_actb = i_busy && i_we    && (i_layer == 2'd1);", "wire w_wr_actb = i_busy && i_we    && (i_layer == 2'd2);")], "detect"),
 ("B03", MC, "ACT_A 쓰기 주소에 xaddr 사용",                [("(w_wr_acta ? i_oaddr[6:0] : i_xaddr[6:0])", "i_xaddr[6:0]")], "detect"),
 ("B04", MC, "WMEM 뱅크 MUX: 뱅크 0 자리에 뱅크 1",         [("assign o_w = (w_wsel == 2'd0) ? w_wd0 :", "assign o_w = (w_wsel == 2'd0) ? w_wd1 :")], "detect"),
 ("B05", MC, "bias 4개 묶음에서 0번 자리에 1번",             [("(w_bsel == 2'd0) ? w_bias128[31:0]  :", "(w_bsel == 2'd0) ? w_bias128[63:32] :")], "detect"),
 ("B06", MC, "FC2 입력을 IMEM 에서 읽음",                   [("2'd1:    w_x_mux = w_acta_dout;", "2'd1:    w_x_mux = w_imem_dout;")], "detect"),
 ("B07", MC, "BMEM 주소를 /4 하지 않음",                    [(".bias_addr(i_baddr[9:2])", ".bias_addr(i_baddr[7:0])")], "detect"),
 ("B08", MC, "외부 읽기 MUX: ACT_A 자리에 ACT_B",           [("3'd3:    o_dout = w_acta_dout;", "3'd3:    o_dout = w_actb_dout;")], "detect"),
 ("B09", MC, "외부 IMEM 주소 7비트만 사용",                 [("wire [7:0]  w_imem_addr = i_busy ? i_xaddr   : i_addr[7:0];", "wire [7:0]  w_imem_addr = i_busy ? i_xaddr   : {1'b0, i_addr[6:0]};")], "detect"),
 ("B10", MC, "WMEM 뱅크 선택을 지연 없이 사용",              [("wire [1:0] w_wsel = (RD_LAT == 2) ? r_wsel_d2 : r_wsel_d1;", "wire [1:0] w_wsel = (RD_LAT == 2) ? r_wsel_d2 : i_wbank_sel;")], "equiv"),
 ("A01", PP, "포화 기준 127 -> 1000 (사실상 포화 없음)",     [("(w_shr > 32'sd127) ? 8'd127", "(w_shr > 32'sd1000) ? 8'd127")], "detect"),
 ("A02", PP, "묶기 레인 0 과 3 자리 바뀜",                  [("2'd0: w_pack_next[ 7: 0] = w_sat;", "2'd0: w_pack_next[31:24] = w_sat;"), ("2'd3: w_pack_next[31:24] = w_sat;", "2'd3: w_pack_next[ 7: 0] = w_sat;")], "detect"),
 ("A03", PP, "ReLU 없음",                                   [("(i_relu_en && w_sum[31]) ? 32'sd0", "(1'b0 && w_sum[31]) ? 32'sd0")], "detect"),
 ("A04", PP, "bias 안 더함",                                [("$signed(i_acc) + r_bias;", "$signed(i_acc);")], "detect"),
 ("A05", PP, "o_we 를 lane 2 에서 냄",                      [("end else if (i_lane == 2'd3) begin", "end else if (i_lane == 2'd2) begin")], "detect"),
 ("A06", PP, "포화 값 127 -> 126",                          [("(w_shr > 32'sd127) ? 8'd127", "(w_shr > 32'sd127) ? 8'd126")], "detect"),
 ("C01", PE, "x 레인 1 자리에 레인 2",                      [("x1 = i_x[15:8],", "x1 = i_x[23:16],")], "detect"),
 ("C02", PE, "덧셈 트리에서 p3 빠짐",                       [("s23 = p2 + p3;", "s23 = p2;")], "detect"),
 ("C03", PE, "가중치를 부호 없는 수로 곱함 (레인 3)",        [("p3 <= x3 * w3;", "p3 <= $signed({1'b0, x3}) * $signed({1'b0, w3});")], "detect"),
 ("C04", PE, "누산을 v1 이 아니라 i_valid 로 (1클럭 어긋남)", [("else if (v1)   acc <= acc + s;", "else if (i_valid)   acc <= acc + s;")], "detect"),
 ("C05", PE, "acc_clr 보다 누산 우선",                       [("if (i_acc_clr) acc <= 32'sd0;        // 새 뉴런 시작 (우선)\n            else if (v1)   acc <= acc + s;", "if (v1)   acc <= acc + s;\n            else if (i_acc_clr) acc <= 32'sd0;")], "equiv"),
]


def prepare():
    if os.path.isdir(MUT): shutil.rmtree(MUT)
    os.makedirs(MUT)
    lines = []
    for mid, fn, desc, reps, exp in M:
        d = os.path.join(MUT, mid, "rtl")
        shutil.copytree(os.path.join(ROOT, "rtl"), d)
        p = os.path.join(d, fn)
        src = open(p, encoding="utf-8", newline="").read()
        nl = "\r\n" if "\r\n" in src else "\n"
        for old, new in reps:
            old, new = old.replace("\n", nl), new.replace("\n", nl)
            if src.count(old) != 1:
                sys.exit("%s: pattern found %d times (need exactly 1): %r" % (mid, src.count(old), old))
            src = src.replace(old, new)
        open(p, "w", encoding="utf-8", newline="").write(src)
        lines.append("%s|%s|%s" % (mid, "D" if fn == CT else "X", exp))
    open(os.path.join(MUT, "list.txt"), "w", newline="\n").write("\n".join(lines) + "\n")
    print("prepared %d mutants in %s" % (len(M), MUT))


def verdict(run, tb):
    """xsim.log -> 'PASS' / 'FAIL' / 'TIMEOUT' / 'HANG' / 'ERR' / '-' (안 돌림) 과 체커 에러 수"""
    p = os.path.join(ROOT, "build", "review", run, "xsim.log")
    if not os.path.exists(p):
        return ("-" if not os.path.isdir(os.path.dirname(p)) else "ERR"), None
    t = open(p, encoding="utf-8", errors="replace").read()
    nchk = None
    m = re.findall(r"\[CHK\] (?:run \d+ .*?|FINAL .*?)errors[ so far]* ?(\d+)", t)
    m2 = re.findall(r"checks (?:evaluated, )?\d*,? ?errors (\d+)|(\d+) errors,", t)
    n_errlines = t.count("[CHK-ERR]")
    if "[CHK" in t or "npu_checker" in t:
        nums = [int(a or b) for a, b in m2] if m2 else []
        nchk = max(nums + [n_errlines])
    if "*** %s PASS ***" % tb in t: v = "PASS"
    elif "*** %s FAIL" % tb in t:   v = "FAIL"
    elif "[TIMEOUT]" in t:          v = "TIMEOUT"
    else:                           v = "HANG"
    return v, nchk


def collect():
    rows = []
    for mid, fn, desc, reps, exp in M:
        unit, _ = verdict("mut_%s_ctrl" % mid, "tb_npu_ctrl") if fn == CT else ("n/a", None)
        top, chk = verdict("mut_%s_top" % mid, "tb_npu_top")
        top10, _ = verdict("mut_%s_top10" % mid, "tb_npu_top")
        top100, _ = verdict("mut_%s_top100" % mid, "tb_npu_top")
        stress, _ = verdict("mut_%s_stress" % mid, "tb_npu_top")
        edge, echk = verdict("mut_%s_edge" % mid, "tb_edge")
        rows.append(dict(id=mid, file=fn, desc=desc, exp=exp, unit=unit, top=top, chk=chk, top10=top10, top100=top100, stress=stress, edge=edge, echk=echk))
    return rows


def survivors():
    only_detect = len(sys.argv) > 2 and sys.argv[2] == "detect"
    for r in collect():
        if r["top"] == "PASS" and (not only_detect or r["exp"] == "detect"): print(r["id"])


def report():
    rows = collect()
    out = os.path.join(ROOT, "reports", "review"); os.makedirs(out, exist_ok=True)
    caught = lambda v: v in ("FAIL", "TIMEOUT", "HANG")
    L = ["# 버그 주입(뮤테이션) 결과", "",
         "원본 rtl/ 은 그대로 두고 복사본(build/review/mut/<ID>/rtl)에 버그를 하나씩 넣어 돌린 결과. 스크립트: scripts/review/mutate.py, run_mutants.sh", "",
         "- unit = 기존 tb_npu_ctrl, top = 기존 tb_npu_top(golden 2장), chk = 같은 시뮬에 붙인 npu_checker 에러 수",
         "- stress / edge 는 top 을 통과한(PASS) 뮤턴트만 추가로 돌림 (stress = 기존 tb_npu_top + 합성 이미지 16장, edge = tb_edge + 체커)",
         "- HANG = 정해 둔 시뮬레이션 시간 안에 TB 가 끝나지 않음 (tb_npu_ctrl 에는 타임아웃이 없음)", "",
         "- top10 / top100 = 2장을 통과한 기능 버그만, 기존 tb_npu_top 을 golden 10장(기본값) / 100장으로 다시 돌린 결과", "",
         "| ID | 파일 | 넣은 버그 | 예상 | unit | top (2장) | chk | top10 | top100 | stress | edge | 기존 TB 판정 |", "|---|---|---|---|---|---|---|---|---|---|---|---|"]
    n_det = n_bug = 0; miss = []
    for r in rows:
        old = caught(r["unit"]) or caught(r["top"]) or caught(r["top10"]) or caught(r["top100"])
        if r["exp"] == "detect":
            n_bug += 1; n_det += old
            if not old: miss.append(r["id"])
        note = "잡음" if old else ("못 잡음" if r["exp"] == "detect" else ("동작 같음" if r["exp"] == "equiv" else "결과 같음(못 잡음)"))
        ed = r["edge"] if r["edge"] == "-" else "%s (chk %s)" % (r["edge"], r["echk"])
        L.append("| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |" % (
            r["id"], r["file"], r["desc"], r["exp"], r["unit"], r["top"], "-" if r["chk"] is None else r["chk"],
            r["top10"], r["top100"], r["stress"], ed, note))
    L += ["", "기능 버그(예상 detect) %d개 중 기존 TB 두 개(tb_npu_ctrl, tb_npu_top golden 100장까지)가 잡은 것: %d개. 못 잡은 것: %s" % (n_bug, n_det, ", ".join(miss) if miss else "없음")]
    new_caught = [r["id"] for r in rows if r["id"] in miss and (caught(r["stress"]) or caught(r["edge"]) or (r["echk"] or 0) > 0 or (r["chk"] or 0) > 0)]
    L += ["그중 리뷰에서 추가한 검사(체커, 합성 이미지, tb_edge)가 잡은 것: %s" % (", ".join(new_caught) if new_caught else "없음")]
    open(os.path.join(out, "mutation_results.md"), "w", encoding="utf-8", newline="\n").write("\n".join(L) + "\n")
    print("\n".join(L))


if __name__ == "__main__":
    {"prepare": prepare, "survivors": survivors, "report": report}[sys.argv[1]]()
