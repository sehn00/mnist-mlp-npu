# ============================================================================
# netlist_export.tcl : 리뷰 1단계 8번 준비 + 추가 리포트  (rtl/ 과 프로젝트 설정은 바꾸지 않음, 읽기만)
#   vivado_sim/ 의 synth_1 / impl_1 결과를 열어서
#     build/review/netlist/npu_top_synth_funcsim.v   합성 후 기능 시뮬레이션용 넷리스트
#     build/review/netlist/npu_top_impl_funcsim.v    배치·배선 후 기능 시뮬레이션용
#     build/review/netlist/npu_top_impl_timesim.v + .sdf   배치·배선 후 타이밍 시뮬레이션용 (지연 포함)
#   그리고 reports/review/ 에 check_timing, RAM 사용, 로직 단수 분포, 경로별 타이밍 리포트를 씀
# 사용법: vivado -mode batch -source scripts/review/netlist_export.tcl -log build/review/netlist_export.log -nojournal
# ============================================================================
catch {unset ::env(NoDefaultCurrentDirectoryInExePath)}
set here [file normalize "[file dirname [info script]]/../.."]
set out  "$here/build/review/netlist"
set rpt  "$here/reports/review"
file mkdir $out
file mkdir $rpt

open_project -read_only "$here/vivado_sim/aissd_D_sim.xpr"
foreach r {synth_1 impl_1} {
    puts "### RUN $r : [get_property STATUS [get_runs $r]] | needs_refresh = [get_property NEEDS_REFRESH [get_runs $r]]"
}

open_run synth_1 -name synth_1
write_verilog -force -mode funcsim "$out/npu_top_synth_funcsim.v"
close_design

open_run impl_1 -name impl_1
write_verilog -force -mode funcsim "$out/npu_top_impl_funcsim.v"
write_verilog -force -mode timesim -sdf_anno true -sdf_file "$out/npu_top_impl_timesim.sdf" "$out/npu_top_impl_timesim.v"
write_sdf     -force -mode timesim "$out/npu_top_impl_timesim.sdf"

# ---- 추가 리포트 ----
check_timing -verbose -file "$rpt/check_timing.rpt"
report_ram_utilization -file "$rpt/ram_utilization.rpt"
report_design_analysis -logic_level_distribution -logic_level_dist_paths 5000 -file "$rpt/logic_levels.rpt"
report_timing -setup -max_paths 30 -nworst 1 -unique_pins -path_type summary -file "$rpt/timing_setup_top30_summary.rpt"
report_timing -hold  -max_paths 30 -nworst 1 -unique_pins -path_type summary -file "$rpt/timing_hold_top30_summary.rpt"
report_control_sets -file "$rpt/control_sets.rpt"
report_high_fanout_nets -max_nets 15 -file "$rpt/high_fanout.rpt"
report_drc -file "$rpt/drc_routed.rpt"

# 블록별 가장 느린 경로 (끝점 기준)
set f [open "$rpt/worst_path_by_block.txt" w]
foreach {tag pat} {A u_A/* B u_B/* C u_C/* D u_D/*} {
    set cells [get_cells -hier -quiet -filter "NAME =~ $pat && IS_SEQUENTIAL"]
    if {[llength $cells] == 0} { puts $f "$tag : no sequential cells"; continue }
    set p [get_timing_paths -setup -max_paths 1 -nworst 1 -to $cells]
    set h [get_timing_paths -hold  -max_paths 1 -nworst 1 -to $cells]
    if {[llength $p] > 0} {
        puts $f "$tag setup: slack [get_property SLACK $p] ns, levels [get_property LOGIC_LEVELS $p], delay [get_property DATAPATH_DELAY $p] ns"
        puts $f "    from [get_property STARTPOINT_PIN $p]"
        puts $f "    to   [get_property ENDPOINT_PIN $p]"
    }
    if {[llength $h] > 0} { puts $f "$tag hold : slack [get_property SLACK $h] ns  ([get_property STARTPOINT_PIN $h] -> [get_property ENDPOINT_PIN $h])" }
}
set wns [get_property SLACK [get_timing_paths -setup -max_paths 1 -nworst 1]]
puts $f "WNS $wns ns at 10 ns period -> minimum period about [expr {10.0 - $wns}] ns = [format %.1f [expr {1000.0 / (10.0 - $wns)}]] MHz (this placement, slow corner)"
# BRAM enable 핀이 어디에 묶여 있는지 (전력 분석용)
set rams [get_cells -hier -filter {REF_NAME =~ RAMB*}]
puts $f "BRAM primitives: [llength $rams]"
foreach blk {u_wmem_bank0 u_wmem_bank1 u_wmem_bank2 u_wmem_bank3 u_bmem u_imem_a u_act_a u_act_b u_omem} {
    set rs [get_cells -hier -quiet -filter "REF_NAME =~ RAMB* && NAME =~ *$blk/*"]
    set const 0; set logic 0
    foreach r $rs {
        set n [get_nets -quiet -of_objects [get_pins $r/ENARDEN]]
        if {[llength $n] == 0 || [get_property TYPE $n] eq "POWER"} { incr const } else { incr logic }
    }
    puts $f "  $blk : [llength $rs] primitives, ENARDEN tied to 1: $const, driven by logic (address decode): $logic"
}
close $f

close_design
close_project
puts "### netlist_export done"
exit 0
