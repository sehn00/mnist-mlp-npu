#!/usr/bin/env bash
# ============================================================================
# sdf_probe.sh : tb/review/sdf_probe/ 의 최소 실험을 XSim 으로 돌림 (약 1분)
#   XSim 이 SDF 의 클럭 배선 지연을 "이름에 대괄호가 있는 플립플롭"에도 적용하는지 확인.
#   타이밍 시뮬레이션(xrun_netlist.sh impl_timesim)과 같은 xelab 옵션을 씀.
# 사용법: bash scripts/review/sdf_probe.sh        결과: reports/review/sdf_probe.txt
# ============================================================================
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -W)"
XB="${VIVADO_BIN:-E:\\Xilinx\\Vivado\\2024.2\\bin}"
RD="$ROOT/build/review/sdf_probe"
rm -rf "$RD"; mkdir -p "$RD"; cd "$RD" || exit 2
cp "${PROBE_SDF:-$ROOT/tb/review/sdf_probe/probe.sdf}" probe.sdf
{
  PDEF=""; for d in ${PROBE_DEFS:-}; do PDEF="$PDEF -d \"$d\""; done
  echo "verilog work $PDEF \"$ROOT/tb/review/sdf_probe/probe.v\""
  echo "verilog work \"$ROOT/vivado_sim/aissd_D_sim.sim/sim_1/behav/xsim/glbl.v\""
  echo "nosort"
} > sim.prj
printf 'run -all\nexit\n' > run.tcl
run() { env -u NoDefaultCurrentDirectoryInExePath cmd //c "$XB\\$1" > "$2" 2>&1; }
run "xvlog.bat --relax -prj sim.prj -log xvlog.log" xvlog.out
# xelab 옵션은 파일(-f)로 넘김: cmd 가 "=" 에서 인자를 쪼개는 문제를 피하려고
echo "${PROBE_RELAX---relax} --mt 2 ${PROBE_XOPT:--maxdelay -transport_int_delays -pulse_r 0 -pulse_int_r 0 -pulse_e 0 -pulse_int_e 0} -L work -L simprims_ver -L secureip --snapshot snap work.probe_tb work.glbl -log xelab.log" > xelab.f
run "xelab.bat -f xelab.f" xelab.out
run "xsim.bat snap -tclbatch run.tcl -log xsim.log" xsim.out
OUT="$ROOT/reports/review/sdf_probe${PROBE_TAG:-}.txt"
{
  echo "sdf_probe : XSim $(grep -m1 -oE 'Vivado Simulator v[0-9.]+' xelab.log)   xelab options: ${PROBE_XOPT:--maxdelay -transport_int_delays -pulse_r 0 -pulse_int_r 0 -pulse_e 0 -pulse_int_e 0}   sdf: $(basename "${PROBE_SDF:-probe.sdf}")"
  echo "SDF: clock interconnect 2000 ps to all four FDCE C pins, C->Q 110 ps. Expected: every q changes at clock edge + BUFGCE + 2000 + 110 ps."
  grep -E "^q[0-3]|SDF|WARNING|ERROR" xelab.log xsim.log | sed 's/^[a-z.]*log://' | cut -c1-200
} > "$OUT"
cat "$OUT"
