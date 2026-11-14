#!/usr/bin/env bash
# ============================================================================
# run_regress.sh : 전체 회귀를 명령 하나로 (Git Bash). 하나라도 FAIL 이면 반환값 1
#
#   bash run_regress.sh          # 통합 TB 를 golden 100장으로 (전체 약 5~6분)
#   bash run_regress.sh 10       # 통합 TB 를 10장으로 (빠른 확인용, 약 3분)
#
# 돌리는 것 (위에서 아래로, 시뮬레이션은 한 번에 하나씩)
#   rules         rtl/ 에 initial, #지연, $readmemh/b 가 없는지 (과제 가이드 p.4-5)
#   golden_check  mlp_mnist.pt 에서 다시 계산한 값 == 팀 golden hex (가중치, bias, 사진 100장)
#   gen_stress    합성 이미지 16장 + 정답 만들기 (포화, 레인별, 난수. golden 100장에는 포화가 한 번도 없음)
#   ctrl_rd1/2    tb_npu_ctrl (D 단위), RD_LAT = 1 과 2
#   topN_chk      tb_npu_top golden N장 + npu_checker (매 클럭 검사)
#   stress16_chk  tb_npu_top 합성 이미지 16장 + npu_checker
#   edge_chk      tb_edge 예외 상황 12종 + npu_checker
#   model_rd1/2   tb_npu_top 2장, BRAM 을 sim_models/bram_models.v (행동 모델)로. rd2 = 예전 OREG_ON 구성
#
# 필요한 것
#   - Vivado 2024.2 의 xvlog/xelab/xsim (기본 E:\Xilinx\Vivado\2024.2\bin, 다르면 VIVADO_BIN 환경 변수)
#   - BRAM IP 시뮬레이션 모델: vivado_sim/ (run_sim.bat 또는 run_sim.tcl 을 한 번 돌리면 생김)
#   - python + numpy (다른 python 을 쓰려면 PYTHON 환경 변수)
# 결과
#   요약   logs/regress_summary.txt
#   로그   logs/regress/<이름>.log   (작업 폴더는 build/regress/<이름>/)
# Vivado 프로젝트를 열지 않고 xvlog -> xelab -> xsim 만 씀 (scripts/review/xrun.sh).
# ============================================================================
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -W)"
cd "$ROOT" || exit 2
N_IMG="${1:-100}"
PY="${PYTHON:-python}"
export PYTHONIOENCODING=utf-8
export OUT_BASE=build/regress
LOGD=logs/regress
SUM=logs/regress_summary.txt
mkdir -p "$LOGD" "$OUT_BASE"

if [ ! -f vivado_sim/aissd_D_sim.gen/sources_1/ip/wmem_bank0/sim/wmem_bank0.v ]; then
  echo "BRAM IP 시뮬레이션 모델이 없음 (vivado_sim/). 먼저 run_sim.bat (또는 run_sim.tcl) 을 한 번 돌릴 것"
  exit 2
fi

NFAIL=0; NSTEP=0; T_ALL=$SECONDS
{
  echo "run_regress.sh  $(date '+%Y-%m-%d %H:%M:%S')   golden images for tb_npu_top: $N_IMG"
  echo "git $(git rev-parse --short HEAD 2>/dev/null)$(git diff --quiet HEAD -- rtl tb scripts sim_models hex coe 2>/dev/null || echo ' + uncommitted changes')"
  echo
  printf '%-13s %-5s %5s  %s\n' "step" "" "sec" "detail"
} > "$SUM"
cat "$SUM"

# row <이름> <1 = 통과> <걸린 초> <설명>
row() {
  local res="PASS"
  if [ "$2" != "1" ]; then res="FAIL"; NFAIL=$((NFAIL + 1)); fi
  NSTEP=$((NSTEP + 1))
  printf '%-13s %-5s %5s  %s\n' "$1" "$res" "$3" "$4" | tee -a "$SUM"
}

# sim <이름> <있어야 하는 PASS 문자열> <npu_checker 연산 수: 숫자 = 그만큼 있어야 함, - = 검사 안 함> <xrun.sh 인자 4개>
sim() {
  local name="$1" pass="$2" nchk="$3"; shift 3
  local t0=$SECONDS ok=1 detail="" log="$OUT_BASE/$name/xsim.log"
  bash scripts/review/xrun.sh "$name" "$@"
  local rc=$?
  if [ $rc -ne 0 ] || [ ! -f "$log" ]; then
    row "$name" 0 $((SECONDS - t0)) "compile / elaborate error (xrun.sh rc $rc, see $OUT_BASE/$name/)"
    return
  fi
  tr -d '\r' < "$log" > "$LOGD/$name.log"
  log="$LOGD/$name.log"
  grep -qF "$pass" "$log" || { ok=0; detail="missing '$pass'. "; }
  if grep -qE 'TIMEOUT|\*\*\* tb_[a-z_]+ FAIL' "$log"; then ok=0; detail="${detail}FAIL or TIMEOUT line in log. "; fi
  local nce; nce=$(grep -c 'CHK-ERR' "$log")
  if [ "$nce" -ne 0 ]; then ok=0; detail="${detail}checker error lines $nce. "; fi
  # 핵심 숫자
  local k
  k=$(grep -E 'golden bit-exact|prediction  |clock count|start->done  |tb_edge :' "$log" | grep -v '^\[CHK\]' | sed -E 's/^ +//; s/ +/ /g' | tr '\n' ';' | sed 's/;$//; s/;/, /g')
  detail="$detail$k"
  if [ "$nchk" != "-" ]; then
    local runs last
    runs=$(grep -c '^\[CHK\] run ' "$log")
    last=$(grep '^\[CHK\] run ' "$log" | tail -1 | sed -E 's/.*checks ([0-9]+), errors ([0-9]+).*/\1 checks, \2 errors/')
    if [ "$runs" -ne "$nchk" ]; then ok=0; detail="$detail | checker saw $runs runs, expected $nchk"; fi
    case "$last" in *", 0 errors") ;; *) ok=0 ;; esac
    detail="$detail | checker: $runs runs, $last"
  fi
  local fin; fin=$(grep '^\[CHK\] FINAL' "$log" | sed -E 's/^\[CHK\] FINAL : //; s/, ext access.*//')
  [ -n "$fin" ] && detail="$detail | checker: $fin"
  local nw; nw=$(grep -ciE 'warning|outside range' "$log")
  detail="$detail | simulator warnings $nw"
  row "$name" $ok $((SECONDS - t0)) "$detail"
}

# ---- 1. 가이드 규칙: rtl/ 에 initial, #지연, $readmem 없음 (주석은 빼고 봄)
t0=$SECONDS
bad=$(for f in rtl/*.v; do sed -E 's://.*$::' "$f" | grep -nE '(^|[^a-zA-Z_])initial([^a-zA-Z_]|$)|\$readmem|#[0-9]' | sed "s|^|$f:|"; done)
if [ -z "$bad" ]; then row rules 1 $((SECONDS - t0)) "no initial / #delay / \$readmem in rtl/ ($(ls rtl/*.v | wc -l) files)"
else row rules 0 $((SECONDS - t0)) "found in rtl/: $(echo "$bad" | head -3 | tr '\n' ' ')"; fi

# ---- 2. golden 독립 확인 (+ 체커용 단계별 정답 build/review/golden_stages)
t0=$SECONDS
"$PY" scripts/review/golden_check.py > "$LOGD/golden_check.log" 2>&1; rc=$?
d=$(tr -d '\r' < "$LOGD/golden_check.log" | grep -E '^==== golden_check' | tail -1)
[ $rc -eq 0 ] && row golden_check 1 $((SECONDS - t0)) "$d" || row golden_check 0 $((SECONDS - t0)) "rc $rc ${d:-(see $LOGD/golden_check.log)}"

# ---- 3. 합성 이미지 16장
t0=$SECONDS
"$PY" scripts/review/gen_stress.py > "$LOGD/gen_stress.log" 2>&1; rc=$?
d=$(tr -d '\r' < "$LOGD/gen_stress.log" | grep -E '^FC1 saturated' | sed -E 's/ +/ /g')
[ $rc -eq 0 ] && row gen_stress 1 $((SECONDS - t0)) "16 images, $d" || row gen_stress 0 $((SECONDS - t0)) "rc $rc (see $LOGD/gen_stress.log)"

# ---- 4. D 단위 TB
export NO_IP=1
sim ctrl_rd1 "*** tb_npu_ctrl PASS ***" - rtl "TB_RD_LAT=1" "tb/tb_npu_ctrl.v" "tb_npu_ctrl"
sim ctrl_rd2 "*** tb_npu_ctrl PASS ***" - rtl "TB_RD_LAT=2" "tb/tb_npu_ctrl.v" "tb_npu_ctrl"
unset NO_IP

# ---- 5. 통합 TB: golden N장 + 매 클럭 검사기
sim "top${N_IMG}_chk" "*** tb_npu_top PASS ***" "$N_IMG" rtl "N_IMG=$N_IMG CHK_STAGES" "tb/review/npu_checker.v tb/tb_npu_top.v" "tb_npu_top npu_checker"

# ---- 6. 통합 TB: 합성 이미지 16장 + 검사기
export HEX_SRC="$ROOT/build/review/stress_hex" STAGE_SRC="$ROOT/build/review/stress_hex"
sim stress16_chk "*** tb_npu_top PASS ***" 16 rtl "N_IMG=16 CHK_STAGES" "tb/review/npu_checker.v tb/tb_npu_top.v" "tb_npu_top npu_checker"
unset HEX_SRC STAGE_SRC

# ---- 7. 예외 상황 TB + 검사기
sim edge_chk "*** tb_edge PASS ***" - rtl "CHK_TOP=tb_edge.u_top CHK_IMG=tb_edge.cur_img CHK_STAGES" "tb/review/npu_checker.v tb/review/tb_edge.v" "tb_edge npu_checker"

# ---- 8. BRAM 행동 모델 (iverilog 용 sim_models/) 로 2장: RD_LAT 1 / 2
export NO_IP=1 EXTRA_SRC="sim_models/bram_models.v"
sim model_rd1 "*** tb_npu_top PASS ***" 2 rtl "N_IMG=2 CHK_STAGES" "tb/review/npu_checker.v tb/tb_npu_top.v" "tb_npu_top npu_checker"
sim model_rd2 "*** tb_npu_top PASS ***" 2 rtl "N_IMG=2 OREG_ON CHK_RD_LAT=2 CHK_STAGES" "tb/review/npu_checker.v tb/tb_npu_top.v" "tb_npu_top npu_checker"
unset NO_IP EXTRA_SRC

echo | tee -a "$SUM"
if [ $NFAIL -eq 0 ]; then
  echo "*** REGRESSION PASS *** ($NSTEP steps, $((SECONDS - T_ALL)) s)" | tee -a "$SUM"
  exit 0
else
  echo "*** REGRESSION FAIL *** ($NFAIL of $NSTEP steps failed, $((SECONDS - T_ALL)) s)" | tee -a "$SUM"
  exit 1
fi
