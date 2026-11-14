# ============================================================================
# io_timing.tcl : 배선된 설계의 "핀에서 본" 타이밍 (리뷰용, 읽기만)
#   입출력 지연 제약이 없어서 Vivado 타이밍 요약에는 안 나오는 값을 datasheet 리포트로 뽑음:
#     - 입력 핀: i_clk 핀 기준으로 필요한 setup / hold 시간
#     - 출력 핀: i_clk 핀의 상승 엣지부터 값이 핀에 나올 때까지 걸리는 시간 (clock-to-out, 최대 / 최소)
# 사용법: vivado -mode batch -source scripts/review/io_timing.tcl -log build/review/io_timing.log -nojournal
# 결과 : reports/review/io_datasheet.rpt
# ============================================================================
catch {unset ::env(NoDefaultCurrentDirectoryInExePath)}
set here [file normalize "[file dirname [info script]]/../.."]
set rpt  "$here/reports/review"
file mkdir $rpt
open_project -read_only "$here/vivado_sim/aissd_D_sim.xpr"
open_run impl_1 -name impl_1
report_datasheet -file "$rpt/io_datasheet.rpt"
close_design
close_project
exit 0
