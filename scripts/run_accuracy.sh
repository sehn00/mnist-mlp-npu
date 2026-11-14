#!/usr/bin/env bash
# ============================================================================
# run_accuracy.sh : 테스트셋 정확도를 RTL 시뮬레이션으로 측정 (가이드 보고서 6번)
#
#   bash scripts/run_accuracy.sh                # MNIST 테스트셋 1만 장, 500장씩 20묶음 (약 3~4시간)
#   bash scripts/run_accuracy.sh 1000 250       # 앞 1,000장만, 250장씩
#
# 방식
#   - tb_npu_top 을 ACC_ONLY 모드로 컴파일 (FC1/FC2 출력은 안 읽고, FC3 점수 10개를 golden 과 비교 + 예측을 label 과 비교)
#   - golden 은 scripts/gen_golden_10k.py 가 만든 build/golden_10k/ (없으면 여기서 만듦)
#   - 컴파일은 한 번, 그 뒤 묶음마다 xsim 을 +IMG_BASE=<시작 번호> 로 실행. 한 번에 하나씩만 돌림
#   - 묶음 로그: build/accuracy/chunks/chunk_<시작 번호>.log
#     끝난 묶음은 건너뛰므로, 중간에 끊겨도 같은 명령을 다시 실행하면 이어서 함
#     (rtl/, tb_npu_top.v, golden 이 바뀌면 묶음 로그를 지우고 처음부터 다시)
#   - 끝나면 scripts/accuracy_report.py 가 reports/accuracy_10k.txt 를 씀
# 반환값: 0 = 전 이미지 FC3 점수가 golden 과 비트 일치 + 클럭 수 정상, 1 = 아님
# 필요한 것: run_regress.sh 와 같음 (Vivado 2024.2 xsim, vivado_sim/ 의 BRAM IP 모델, python + numpy)
# ============================================================================
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -W)"
cd "$ROOT" || exit 2
TOTAL="${1:-10000}"
CHUNK="${2:-500}"
PY="${PYTHON:-python}"
export PYTHONIOENCODING=utf-8
XB="${VIVADO_BIN:-E:\\Xilinx\\Vivado\\2024.2\\bin}"
GOLD="$ROOT/build/golden_10k"
WORK="$ROOT/build/accuracy"
CH="$WORK/chunks"
REPORT="reports/accuracy_10k.txt"
[ "$TOTAL" = "10000" ] || REPORT="reports/accuracy_${TOTAL}.txt"

if [ $((TOTAL % CHUNK)) -ne 0 ]; then echo "전체 장수($TOTAL)는 묶음 크기($CHUNK)의 배수여야 함"; exit 2; fi
if [ ! -f "$GOLD/fc3_omem.hex" ]; then "$PY" scripts/gen_golden_10k.py || exit 2; fi
NGOLD=$(wc -l < "$GOLD/labels.txt")
if [ "$TOTAL" -gt "$NGOLD" ]; then echo "golden 은 $NGOLD 장뿐 (요청 $TOTAL 장)"; exit 2; fi
mkdir -p "$CH"

# ---- 입력이 바뀌었으면 예전 묶음 로그는 버림
STAMP="$(cat rtl/*.v tb/tb_npu_top.v "$GOLD/input_act_a.hex" "$GOLD/fc3_omem.hex" "$GOLD/labels.txt" | sha1sum | cut -d' ' -f1) total=$TOTAL chunk=$CHUNK"
if [ "$(cat "$WORK/stamp.txt" 2>/dev/null)" != "$STAMP" ]; then
  rm -f "$CH"/chunk_*.log
  echo "$STAMP" > "$WORK/stamp.txt"
  : > "$WORK/progress.txt"
fi

# ---- 컴파일 (매번 새로, 약 30초). 결과 폴더: build/accuracy/snap/
T0=$SECONDS
export OUT_BASE=build/accuracy HEX_SRC="$GOLD" BUILD_ONLY=1
bash scripts/review/xrun.sh snap rtl "N_IMG=$CHUNK N_GOLD=$NGOLD ACC_ONLY" "tb/tb_npu_top.v" "tb_npu_top" || { echo "컴파일 실패 (build/accuracy/snap/ 의 xvlog.log, xelab.log)"; exit 2; }
unset BUILD_ONLY
cd "$WORK/snap" || exit 2

# ---- 묶음 실행
for ((b = 0; b < TOTAL; b += CHUNK)); do
  log="$CH/chunk_$(printf '%05d' "$b").log"
  if grep -qE '\*\*\* tb_npu_top (PASS|FAIL)' "$log" 2>/dev/null; then continue; fi
  t1=$SECONDS
  rm -f xsim_chunk.log
  # 따옴표 필수: cmd 의 .bat 는 따옴표 없는 인자를 '=' 에서 둘로 쪼갬 (IMG_BASE=0 -> "IMG_BASE" "0")
  env -u NoDefaultCurrentDirectoryInExePath cmd //c "$XB\\xsim.bat snap -R -testplusarg \"IMG_BASE=$b\" -log xsim_chunk.log" > xsim.out 2>&1
  if [ ! -f xsim_chunk.log ]; then echo "[acc] images $b.. : xsim 로그가 없음 (build/accuracy/snap/xsim.out)"; exit 2; fi
  tr -d '\r' < xsim_chunk.log > "$log.tmp" && mv "$log.tmp" "$log"
  line="[acc] images $b..$((b + CHUNK - 1)) : $(grep -E 'golden bit-exact|prediction  ' "$log" | sed -E 's/^ +//; s/ +/ /g' | tr '\n' ',' | sed 's/,$//; s/,/, /') | $(grep -oE '\*\*\* tb_npu_top [A-Z]+' "$log" | tail -1 | sed 's/\*\*\* //') | $((SECONDS - t1)) s   ($(date '+%H:%M:%S'))"
  echo "$line" | tee -a "$WORK/progress.txt"
done

cd "$ROOT" || exit 2
"$PY" scripts/accuracy_report.py --chunks "$CH" --gold "$GOLD" --total "$TOTAL" --seconds $((SECONDS - T0)) --out "$REPORT"
