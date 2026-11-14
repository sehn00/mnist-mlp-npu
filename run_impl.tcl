# ============================================================================
# run_impl.tcl : npu_top 합성 + 구현(place & route) + 리포트   (조원4)
#   run_sim.tcl 이 만든 프로젝트(vivado_sim/)를 열어서 그대로 사용 (BRAM IP 10개 재사용)
#   -> run_sim.tcl 을 먼저 한 번 돌려야 함
# Usage: vivado -mode batch -source run_impl.tcl -log run_impl.log -notrace
#        vivado -mode batch -source run_impl.tcl -tclargs synth     (합성까지만)
# 결과 : result_impl.txt (요약), reports/*.rpt (사용량, 타이밍, 전력)
# ============================================================================
catch {unset ::env(NoDefaultCurrentDirectoryInExePath)}   ;# see run_sim.tcl
# Parallel Vivado jobs. Each one needs 2-3 GB of RAM: with 8 jobs a 16 GB PC ran out of memory
# and three IP runs died without any error message. Keep this small.
set JOBS 2
set stop_after "impl"
if {[llength $argv] > 0} { set stop_after [lindex $argv 0] }

set here    [file normalize [file dirname [info script]]]
set xpr     "$here/vivado_sim/aissd_D_sim.xpr"
set rpt_dir "$here/reports"
set result  "$here/result_impl.txt"
file mkdir $rpt_dir

set rf [open $result w]
puts $rf "run_impl.tcl  [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
puts $rf "Vivado [version -short]"
close $rf
proc note {msg} {
    global result
    set f [open $result a]; puts $f $msg; close $f
    puts "### $msg"
}

if {![file exists $xpr]} {
    note "project not found: $xpr  (run run_sim.tcl first)"
    exit 1
}
open_project $xpr

# ---------------------------------------------------------------- constraints / top
if {[llength [get_files -quiet -of_objects [get_filesets constrs_1] *npu_top.xdc]] == 0} {
    add_files -fileset constrs_1 -norecurse "$here/constr/npu_top.xdc"
}
set_property top npu_top [get_filesets sources_1]
update_compile_order -fileset sources_1
note "part [get_property part [current_project]]  top [get_property top [get_filesets sources_1]]"

# 사용량/타이밍 요약을 result_impl.txt 에 적는 공통 함수 (열려 있는 디자인 기준)
proc summarize {tag} {
    global rpt_dir
    report_utilization             -file "$rpt_dir/${tag}_utilization.rpt"
    report_utilization -hierarchical -file "$rpt_dir/${tag}_utilization_hier.rpt"
    report_timing_summary -max_paths 10 -file "$rpt_dir/${tag}_timing_summary.rpt"
    report_timing -setup -max_paths 5 -nworst 1 -file "$rpt_dir/${tag}_timing_setup_top5.rpt"
    report_timing -hold  -max_paths 5 -nworst 1 -file "$rpt_dir/${tag}_timing_hold_top5.rpt"

    set lut  [llength [get_cells -hier -quiet -filter {IS_PRIMITIVE && REF_NAME =~ LUT*}]]
    set ff   [llength [get_cells -hier -quiet -filter {IS_PRIMITIVE && (REF_NAME =~ FD*)}]]
    set b36  [llength [get_cells -hier -quiet -filter {IS_PRIMITIVE && REF_NAME =~ RAMB36*}]]
    set b18  [llength [get_cells -hier -quiet -filter {IS_PRIMITIVE && REF_NAME =~ RAMB18*}]]
    set dsp  [llength [get_cells -hier -quiet -filter {IS_PRIMITIVE && REF_NAME =~ DSP48E*}]]
    set c8   [llength [get_cells -hier -quiet -filter {IS_PRIMITIVE && REF_NAME =~ CARRY8*}]]
    note "  \[$tag\] LUT cells $lut / FF $ff / RAMB36 $b36 / RAMB18 $b18 (= [expr {$b36 + $b18/2.0}] BRAM tiles) / DSP48E2 $dsp / CARRY8 $c8"

    set sp [get_timing_paths -setup -max_paths 1 -nworst 1]
    set hp [get_timing_paths -hold  -max_paths 1 -nworst 1]
    if {[llength $sp] > 0} {
        note "  \[$tag\] WNS [get_property SLACK $sp] ns  (logic levels [get_property LOGIC_LEVELS $sp], data delay [get_property DATAPATH_DELAY $sp] ns)"
        note "  \[$tag\]   from [get_property STARTPOINT_PIN $sp]"
        note "  \[$tag\]   to   [get_property ENDPOINT_PIN $sp]"
    }
    if {[llength $hp] > 0} {
        note "  \[$tag\] WHS [get_property SLACK $hp] ns"
        note "  \[$tag\]   from [get_property STARTPOINT_PIN $hp]"
        note "  \[$tag\]   to   [get_property ENDPOINT_PIN $hp]"
    }
}

# 전력 리포트 (가이드 p.39: breakdown 포함). 스위칭 정보 파일(SAIF) 없이 Vivado 기본 추정(vectorless)으로 계산.
proc summarize_power {tag} {
    global rpt_dir
    set pf "$rpt_dir/${tag}_power.rpt"
    report_power -file $pf
    report_power -hier all -hierarchical_depth 3 -file "$rpt_dir/${tag}_power_hier.rpt"
    set f [open $pf r]; set txt [read $f]; close $f
    foreach line [split $txt \n] {
        if {[regexp {^\| (Total On-Chip Power \(W\)|Dynamic \(W\)|Device Static \(W\)|Confidence Level|Junction Temperature \(C\))\s*\|\s*([^|]+?)\s*\|} $line -> k v]} {
            note "  \[$tag\] power: $k = $v"
        }
        if {[regexp {^\| (Clocks|CLB Logic|Signals|Block RAM|I/O|Static Power)\s*\|\s*([<0-9.]+)\s*\|} $line -> k v]} {
            note "  \[$tag\] power breakdown: $k = $v W"
        }
    }
}

# ---------------------------------------------------------------- synthesis
note "==== synthesis (synth_1) ===="
# IP runs (out-of-context synthesis of the 10 BRAMs): keep finished ones, reset the rest
foreach r [get_runs -quiet *_synth_1] {
    if {[get_property PROGRESS $r] ne "100%"} { reset_run $r }
}
reset_run synth_1
launch_runs synth_1 -jobs $JOBS
if {[catch {wait_on_run synth_1} err]} { note "wait_on_run synth_1: $err" }
foreach r [get_runs -quiet *_synth_1] {
    if {[get_property PROGRESS $r] ne "100%"} { note "  IP run $r : [get_property STATUS $r]" }
}
set st [get_property STATUS [get_runs synth_1]]
note "synth_1 status: $st"
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    note "synthesis FAILED (see vivado_sim/aissd_D_sim.runs/synth_1/runme.log)"
    close_project
    exit 1
}
open_run synth_1 -name synth_1
summarize synth
close_design

if {$stop_after eq "synth"} {
    note "done (synth only). reports: $rpt_dir"
    close_project
    exit 0
}

# ---------------------------------------------------------------- implementation
note "==== implementation (impl_1) ===="
launch_runs impl_1 -jobs $JOBS
if {[catch {wait_on_run impl_1} err]} { note "wait_on_run impl_1: $err" }
set st [get_property STATUS [get_runs impl_1]]
note "impl_1 status: $st"
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    note "implementation FAILED (see vivado_sim/aissd_D_sim.runs/impl_1/runme.log)"
    close_project
    exit 1
}
open_run impl_1 -name impl_1
summarize impl
if {[catch {summarize_power impl} err]} { note "report_power: $err" }
set wns [get_property SLACK [get_timing_paths -setup -max_paths 1 -nworst 1]]
set whs [get_property SLACK [get_timing_paths -hold  -max_paths 1 -nworst 1]]
if {$wns >= 0 && $whs >= 0} { note "*** TIMING MET at 100 MHz (WNS $wns, WHS $whs) ***" } \
else                        { note "*** TIMING NOT MET (WNS $wns, WHS $whs) ***" }
close_design

note "done. reports: $rpt_dir"
file copy -force $result "$rpt_dir/impl_summary.txt"
close_project
exit 0
