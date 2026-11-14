#!/usr/bin/env bash
# ============================================================================
# xrun_netlist.sh : 구현된 회로(넷리스트)를 기존 tb_npu_top 으로 시뮬레이션 (리뷰 1단계 8번)
#   먼저 scripts/review/netlist_export.tcl 로 build/review/netlist/ 를 만들어 둬야 함.
#
# 사용법: scripts/review/xrun_netlist.sh <run 이름> <모드> <사진 장수> [saif]
#   모드 synth_funcsim : 합성 후 넷리스트, 지연 없음 (unisims_ver)
#        impl_funcsim  : 배치·배선 후 넷리스트, 지연 없음
#        impl_timesim  : 배치·배선 후 넷리스트 + SDF 지연 (simprims_ver, slow corner max 지연)
#   saif : 스위칭 기록(SAIF)을 build/review/<run>/dump.saif 로 남김 (전력 분석용)
#
# TB 는 tb/tb_npu_top.v 를 그대로 복사해서 아래만 바꿈 (넷리스트에는 parameter 가 없고, 타이밍 시뮬은 지연이 있어서)
#   - "npu_top #(.RD_LAT(1)) u_top"  ->  "npu_top u_top"
#   - (timesim 만) 리셋 해제를 negedge 로, o_dout 샘플을 negedge 4.5 ns 뒤(다음 posedge 0.5 ns 전)로
# ============================================================================
set -u
RUN="$1"; MODE="$2"; NIMG="$3"; SAIF="${4:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -W)"
XB="${VIVADO_BIN:-E:\\Xilinx\\Vivado\\2024.2\\bin}"
RD="$ROOT/build/review/$RUN"
NL="$ROOT/build/review/netlist"

rm -rf "$RD"; mkdir -p "$RD/hex"
cp "${HEX_SRC:-$ROOT/hex}"/*.hex "${HEX_SRC:-$ROOT/hex}"/labels.txt "$RD/hex/"

sed -E 's/npu_top #\(\.RD_LAT\([0-9]\)\) u_top/npu_top u_top/' "$ROOT/tb/tb_npu_top.v" > "$RD/tb_npu_top_netlist.v"
case "$MODE" in
  synth_funcsim) NET="$NL/npu_top_synth_funcsim.v"; LIBS="-L unisims_ver -L secureip"; XOPT="" ;;
  impl_funcsim)  NET="$NL/npu_top_impl_funcsim.v";  LIBS="-L unisims_ver -L secureip"; XOPT="" ;;
  impl_timesim)  NET="$NL/npu_top_impl_timesim.v";  LIBS="-L simprims_ver -L secureip"
                 XOPT="${DELAY_OPT:--maxdelay} -transport_int_delays -pulse_r 0 -pulse_int_r 0 -pulse_e 0 -pulse_int_e 0" ;;
  *) echo "unknown mode $MODE"; exit 2 ;;
esac
# 타이밍 시뮬용 TB 변형 (TB_VARIANT=timesim 이면 지연 없는 넷리스트에도 같은 TB 를 씀: 비교 실험용)
if [ "$MODE" = "impl_timesim" ] || [ "${TB_VARIANT:-}" = "timesim" ]; then
  sed -i -E "s/^(\s*)i_rstn = 1'b1;/\1@(negedge i_clk) i_rstn = 1'b1;/; s/^(\s*)data = o_dout;/\1#${SAMPLE_DLY:-4.5} data = o_dout;/" "$RD/tb_npu_top_netlist.v"
fi

# EXTRA_SRC  : 같이 컴파일할 파일 (tb/review/tb_progress.v, tb_dump.v 등), EXTRA_TOPS : 같이 올릴 top 모듈 이름
# EXTRA_DEFS : 그 파일들에 줄 define (예: DUMP_NS=12500)
EDEF=""; for d in ${EXTRA_DEFS:-}; do EDEF="$EDEF -d \"$d\""; done
{
  echo "verilog work \"$NET\""
  echo "verilog work -d \"N_IMG=$NIMG\" \"$RD/tb_npu_top_netlist.v\""
  for f in ${EXTRA_SRC:-}; do echo "verilog work $EDEF \"$ROOT/$f\""; done
  echo "verilog work \"$ROOT/vivado_sim/aissd_D_sim.sim/sim_1/behav/xsim/glbl.v\""
  echo "nosort"
} > "$RD/sim.prj"
ETOPS=""; for t in ${EXTRA_TOPS:-}; do ETOPS="$ETOPS work.$t"; done

cd "$RD" || exit 2
if [ "$SAIF" = "saif" ]; then
  printf 'open_saif dump.saif\nlog_saif [get_objects -r /tb_npu_top/u_top/*]\nrun -all\nclose_saif\nexit\n' > run.tcl
else
  printf 'run -all\nexit\n' > run.tcl
fi
run() { env -u NoDefaultCurrentDirectoryInExePath cmd //c "$XB\\$1" > "$2" 2>&1; }
run "xvlog.bat --relax -prj sim.prj -log xvlog.log" xvlog.out
if grep -q "^ERROR" xvlog.log 2>/dev/null; then echo "[$RUN] xvlog ERROR"; grep "^ERROR" xvlog.log | head -5; exit 3; fi
run "xelab.bat --relax --mt 2 $XOPT -L work $LIBS --snapshot snap work.tb_npu_top $ETOPS work.glbl -log xelab.log" xelab.out
if grep -q "^ERROR" xelab.log 2>/dev/null; then echo "[$RUN] xelab ERROR"; grep "^ERROR" xelab.log | head -5; exit 4; fi
run "xsim.bat snap -tclbatch run.tcl -log xsim.log" xsim.out
[ -f xsim.log ] || { echo "[$RUN] xsim.log missing"; exit 5; }
exit 0
