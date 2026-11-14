#!/usr/bin/env bash
# ============================================================================
# xrun.sh : 리뷰용 XSim 단독 실행기 (Vivado 프로젝트를 열지 않고 xvlog -> xelab -> xsim)
#
#   BRAM 은 run_sim.tcl 이 만든 실제 blk_mem_gen IP 의 시뮬레이션 모델을 그대로 씀
#   (vivado_sim/aissd_D_sim.gen/sources_1/ip/*/sim/*.v + .mif). 그래서 run_sim.tcl 을 한 번은 돌려 둬야 함.
#   결과물은 전부 build/review/<run>/ 아래 (git 제외 폴더). rtl/ 은 읽기만 함.
#
# 사용법:
#   scripts/review/xrun.sh <run 이름> <rtl 폴더> "<define 들>" "<tb 파일들>" "<top 모듈들>"
#   예) scripts/review/xrun.sh base_top rtl "N_IMG=2" "tb/tb_npu_top.v" "tb_npu_top"
#       scripts/review/xrun.sh base_ctrl rtl "TB_RD_LAT=1" "tb/tb_npu_ctrl.v" "tb_npu_ctrl"
#   환경 변수:
#     VIVADO_BIN  Vivado bin 폴더 (기본 E:\Xilinx\Vivado\2024.2\bin)
#     NO_IP=1     BRAM IP 모델을 넣지 않음 (D 단독 TB 처럼 메모리가 필요 없을 때)
#     EXTRA_SRC   추가로 컴파일할 파일들 (공백 구분, 저장소 루트 기준 또는 절대 경로)
#     XELAB_OPTS  xelab 추가 옵션
#     SIM_MAX     시뮬레이션 시간 상한 (예: 5ms). 없으면 $finish 까지 (run -all)
#     HEX_SRC     TB 가 읽을 golden 폴더 (기본 hex/). 합성 이미지 세트는 build/review/stress_hex
#     STAGE_SRC   체커용 단계별 정답 폴더 (기본 build/review/golden_stages)
#     OUT_BASE    결과 폴더의 부모 (기본 build/review). 정식 회귀(run_regress.sh)는 build/regress 를 씀
#     BUILD_ONLY=1  컴파일(xvlog, xelab)까지만 하고 시뮬레이션은 안 돌림 (scripts/run_accuracy.sh 가 씀)
# 끝나면 <OUT_BASE>/<run>/xsim.log 에 시뮬레이션 출력이 남음. 반환값: 0 = 시뮬레이션까지 실행됨
# ============================================================================
set -u
RUN="$1"; RTL_DIR="$2"; DEFS="$3"; TBS="$4"; TOPS="$5"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -W)"
XB="${VIVADO_BIN:-E:\\Xilinx\\Vivado\\2024.2\\bin}"
IPGEN="$ROOT/vivado_sim/aissd_D_sim.gen/sources_1/ip"
RD="$ROOT/${OUT_BASE:-build/review}/$RUN"

abs() { case "$1" in [A-Za-z]:*|/*) echo "$1";; *) echo "$ROOT/$1";; esac; }

rm -rf "$RD"; mkdir -p "$RD/hex"
# golden / 가중치 파일: TB 는 "hex/" 상대 경로로 읽음
cp "${HEX_SRC:-$ROOT/hex}"/*.hex "${HEX_SRC:-$ROOT/hex}"/labels.txt "$RD/hex/" 2>/dev/null; cp "$ROOT"/hex/*.mem "$RD/hex/" 2>/dev/null
cp "$ROOT/team_originals/handoff_D_1112/golden/mem/wmem.hex" "$RD/hex/wmem_single.hex"
cp "$ROOT/team_originals/handoff_D_1112/golden/mem/bias.hex" "$RD/hex/bias_single.hex"
STG="${STAGE_SRC:-$ROOT/build/review/golden_stages}"      # golden_check.py / gen_stress.py 가 만든 단계별 정답 (체커 CHK_STAGES 용)
[ -d "$STG" ] && cp "$STG"/rev_*.hex "$RD/hex/" 2>/dev/null

DOPT=""
for d in $DEFS; do DOPT="$DOPT -d \"$d\""; done

{
  if [ "${NO_IP:-0}" != "1" ]; then
    for ip in omem_bram imem_b_bram imem_a_bram act_b_bram act_a_bram bmem_128 wmem_bank3 wmem_bank2 wmem_bank1 wmem_bank0; do
      echo "verilog work \"$IPGEN/$ip/sim/$ip.v\""
      [ -f "$IPGEN/$ip/$ip.mif" ] && cp "$IPGEN/$ip/$ip.mif" "$RD/"
    done
  fi
  for f in "$(abs "$RTL_DIR")"/*.v; do echo "verilog work $DOPT \"$f\""; done
  for f in ${EXTRA_SRC:-}; do echo "verilog work $DOPT \"$(abs "$f")\""; done
  for f in $TBS; do echo "verilog work $DOPT \"$(abs "$f")\""; done
  if [ "${NO_IP:-0}" != "1" ]; then echo "verilog work \"$ROOT/vivado_sim/aissd_D_sim.sim/sim_1/behav/xsim/glbl.v\""; fi
  echo "nosort"
} > "$RD/sim.prj"

TOPARGS=""; for t in $TOPS; do TOPARGS="$TOPARGS work.$t"; done
LIBS=""
if [ "${NO_IP:-0}" != "1" ]; then
  TOPARGS="$TOPARGS work.glbl"
  LIBS="-L blk_mem_gen_v8_4_9 -L unisims_ver -L unimacro_ver -L secureip -L xpm"
fi

cd "$RD" || exit 2
run() { env -u NoDefaultCurrentDirectoryInExePath cmd //c "$XB\\$1" > "$2" 2>&1; }
run "xvlog.bat --relax -prj sim.prj -log xvlog.log" xvlog.out
if grep -q "^ERROR" xvlog.log 2>/dev/null; then echo "[$RUN] xvlog ERROR"; grep "^ERROR" xvlog.log | head -5; exit 3; fi
run "xelab.bat --relax --mt 2 ${XELAB_OPTS:-} -L work $LIBS --snapshot snap $TOPARGS -log xelab.log" xelab.out
if grep -q "^ERROR" xelab.log 2>/dev/null; then echo "[$RUN] xelab ERROR"; grep "^ERROR" xelab.log | head -5; exit 4; fi
[ -d xsim.dir/snap ] || { echo "[$RUN] xelab made no snapshot (see $RD/xelab.log)"; exit 4; }
if [ "${BUILD_ONLY:-0}" = "1" ]; then exit 0; fi
if [ -n "${SIM_MAX:-}" ]; then            # 시뮬레이션 시간 상한 (예: SIM_MAX=5ms). TB 에 타임아웃이 없어도 멈추게
  printf 'run %s\nexit\n' "$SIM_MAX" > run.tcl
  run "xsim.bat snap -tclbatch run.tcl -log xsim.log" xsim.out
else
  run "xsim.bat snap -R -log xsim.log" xsim.out
fi
[ -f xsim.log ] || { echo "[$RUN] xsim.log missing"; exit 5; }
exit 0
