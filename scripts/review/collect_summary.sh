#!/usr/bin/env bash
# ============================================================================
# collect_summary.sh : build/review/*/xsim.log (git 제외 폴더)의 핵심 줄만 모아 reports/review/sim_summary.txt 로
#   보고서(docs/review_1114.md)가 인용하는 숫자의 근거를 저장소에 남기기 위한 것.
# 사용법: bash scripts/review/collect_summary.sh
# ============================================================================
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -W)"
cd "$ROOT" || exit 1
OUT=reports/review/sim_summary.txt
PAT='\*\*\* tb_|golden bit|prediction  |GO count|bias_we count|start->done|RD_LAT =|\[EDGE\]|\[CHK\] (FINAL|reset)|tb_edge :|TIMEOUT|outside range|elapsed'
{
  echo "sim_summary : collected $(date '+%Y-%m-%d %H:%M')   (full logs: build/review/<run>/xsim.log)"
  for run in t0 ctrl_rd2 base_top top100_chk stress edge model_rd1 model_rd2 net_synth net_impl_saif net_impl_time; do
    f="build/review/$run/xsim.log"
    echo; echo "==== $run"
    if [ ! -f "$f" ]; then echo "(no log)"; continue; fi
    grep -E "$PAT" "$f" | cut -c1-240
    last_chk="$(grep -E '^\[CHK\] run ' "$f" | tail -1)"
    [ -n "$last_chk" ] && echo "last checker line: $last_chk"
    echo "img PASS lines: $(grep -cE '^img .* PASS' "$f")   img FAIL lines: $(grep -cE '^img .* FAIL' "$f")   [CHK-ERR] lines: $(grep -c 'CHK-ERR' "$f")"
  done
  echo; echo "==== golden_check.py"
  PYTHONIOENCODING=utf-8 python scripts/review/golden_check.py 2>&1 | grep -E "FAIL\]|golden_check:|포화|max \||상한|경계"
} > "$OUT"
echo "wrote $OUT ($(wc -l < "$OUT") lines)"
