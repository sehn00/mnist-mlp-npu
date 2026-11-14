#!/usr/bin/env bash
# ============================================================================
# run_mutants.sh : 버그 주입 테스트 실행 (mutate.py 가 만든 복사본을 xrun.sh 로 하나씩 시뮬레이션)
#   1) python scripts/review/mutate.py prepare
#   2) 뮤턴트마다: (D 만) 기존 tb_npu_ctrl, 그리고 기존 tb_npu_top(golden 2장) + npu_checker
#   3) 통합 TB 를 통과한 뮤턴트만: (기능 버그면 golden 10장, 100장), 합성 이미지 16장(stress), tb_edge + npu_checker
#      PHASE2_ONLY=1 이면 2) 를 건너뛰고 3) 부터
#   4) python scripts/review/mutate.py report  -> reports/review/mutation_results.md
# 시뮬레이션은 한 번에 하나씩만 돌림. 전체 약 30~40분.
# 사용법: bash scripts/review/run_mutants.sh [ID ...]   (ID 를 주면 그것만)
# ============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd -W)"
cd "$ROOT" || exit 1
PY="${PYTHON:-python}"
export PYTHONIOENCODING=utf-8

if [ $# -eq 0 ] && [ "${PHASE2_ONLY:-0}" != "1" ]; then "$PY" scripts/review/mutate.py prepare || exit 1; fi
[ -f build/review/stress_hex/input_act_a.hex ] || "$PY" scripts/review/gen_stress.py

while IFS='|' read -r id scope exp; do
  [ -z "$id" ] && continue
  [ "${PHASE2_ONLY:-0}" = "1" ] && continue
  if [ $# -gt 0 ] && ! echo " $* " | grep -q " $id "; then continue; fi
  rtl="build/review/mut/$id/rtl"
  if [ "$scope" = "D" ]; then
    NO_IP=1 SIM_MAX=5ms bash "$HERE/xrun.sh" "mut_${id}_ctrl" "$rtl" "TB_RD_LAT=1" "tb/tb_npu_ctrl.v" "tb_npu_ctrl"
  fi
  SIM_MAX=60ms bash "$HERE/xrun.sh" "mut_${id}_top" "$rtl" "N_IMG=2 CHK_STAGES" "tb/review/npu_checker.v tb/tb_npu_top.v" "tb_npu_top npu_checker"
  echo "[$id] done: $(grep -hE '\*\*\* tb_npu_(ctrl|top) (PASS|FAIL)|TIMEOUT' build/review/mut_${id}_*/xsim.log 2>/dev/null | tr -s ' ' | tr '\n' ' ') chk-err-lines $(grep -c 'CHK-ERR' build/review/mut_${id}_top/xsim.log 2>/dev/null)"
done < build/review/mut/list.txt

# ---- 2단계: 통합 TB(2장)를 통과한 뮤턴트만 추가 검사 (PHASE2_ONLY=1 이면 여기부터)
for id in $("$PY" scripts/review/mutate.py survivors | tr -d '\r'); do
  if [ $# -gt 0 ] && ! echo " $* " | grep -q " $id "; then continue; fi
  rtl="build/review/mut/$id/rtl"
  # 기능 버그인데 2장을 통과한 것: 기존 TB 기본값(10장)과 100장으로도 돌려 봄
  if "$PY" scripts/review/mutate.py survivors detect | tr -d '\r' | grep -qx "$id"; then
    SIM_MAX=250ms  bash "$HERE/xrun.sh" "mut_${id}_top10"  "$rtl" "N_IMG=10"  "tb/tb_npu_top.v" "tb_npu_top"
    SIM_MAX=2500ms bash "$HERE/xrun.sh" "mut_${id}_top100" "$rtl" "N_IMG=100" "tb/tb_npu_top.v" "tb_npu_top"
  fi
  HEX_SRC="$ROOT/build/review/stress_hex" STAGE_SRC="$ROOT/build/review/stress_hex" SIM_MAX=400ms \
    bash "$HERE/xrun.sh" "mut_${id}_stress" "$rtl" "N_IMG=16" "tb/tb_npu_top.v" "tb_npu_top"
  SIM_MAX=450ms bash "$HERE/xrun.sh" "mut_${id}_edge" "$rtl" "CHK_TOP=tb_edge.u_top CHK_IMG=tb_edge.cur_img CHK_STAGES" \
    "tb/review/npu_checker.v tb/review/tb_edge.v" "tb_edge npu_checker"
  echo "[$id] survivor: top10/top100 $(grep -hoE '\*\*\* tb_npu_top (PASS|FAIL)' build/review/mut_${id}_top10/xsim.log build/review/mut_${id}_top100/xsim.log 2>/dev/null | tr '\n' ' ') / stress $(grep -hoE '\*\*\* tb_npu_top (PASS|FAIL)' build/review/mut_${id}_stress/xsim.log | tail -1) / edge $(grep -hoE '\*\*\* tb_edge (PASS|FAIL)' build/review/mut_${id}_edge/xsim.log | tail -1)"
done

"$PY" scripts/review/mutate.py report > build/review/mutation_report.out
tail -3 build/review/mutation_report.out
