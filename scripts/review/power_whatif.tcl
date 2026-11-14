# ============================================================================
# power_whatif.tcl : 전력 분석 (리뷰 2단계, 조사만. rtl/ 과 프로젝트는 바꾸지 않음)
#   배치·배선된 설계(impl_1)를 열어서
#     P0 vectorless        : 스위칭 정보 없이 Vivado 기본 추정 (reports/impl_power.rpt 와 같은 조건)
#     P1 saif              : 배선 후 넷리스트로 사진 1장을 실제로 돌린 스위칭 기록(SAIF)을 넣은 값
#     P2 saif + ena gating : P1 에서 WMEM 뱅크 enable 을 "그 뱅크를 쓰는 ISSUE 클럭에만 1", BMEM enable 을
#                            "뉴런당 1클럭만 1" 로 바꿨다고 가정한 값 (RTL 을 고치지 않고 스위칭 확률만 덮어씀)
# 먼저: scripts/review/xrun_netlist.sh net_impl_saif impl_funcsim 1 saif   (build/review/net_impl_saif/dump.saif)
# 사용법: vivado -mode batch -source scripts/review/power_whatif.tcl -log build/review/power_whatif.log -nojournal
# 결과: reports/review/power_*.rpt, reports/review/power_summary.txt
# ============================================================================
catch {unset ::env(NoDefaultCurrentDirectoryInExePath)}
set here [file normalize "[file dirname [info script]]/../.."]
set rpt  "$here/reports/review"
set saif "$here/build/review/net_impl_saif/dump.saif"
file mkdir $rpt
set sf [open "$rpt/power_summary.txt" w]
proc say {msg} { global sf; puts $sf $msg; flush $sf; puts "### $msg" }

open_project -read_only "$here/vivado_sim/aissd_D_sim.xpr"
open_run impl_1 -name impl_1

proc pw {tag} {
    global rpt
    report_power -file "$rpt/power_${tag}.rpt"
    report_power -hier all -hierarchical_depth 4 -file "$rpt/power_${tag}_hier.rpt"
    set f [open "$rpt/power_${tag}.rpt" r]; set txt [read $f]; close $f
    set line "$tag :"
    foreach line_ [split $txt \n] {
        if {[regexp {^\| (Total On-Chip Power \(W\)|Dynamic \(W\)|Device Static \(W\)|Confidence Level)\s*\|\s*([^|]+?)\s*\|} $line_ -> k v]} { append line " $k = $v;" }
        if {[regexp {^\| (Clocks|CLB Logic|Signals|Block RAM|I/O)\s*\|\s*([<0-9.]+)\s*\|} $line_ -> k v]} { append line " $k = $v;" }
    }
    say $line
    set f [open "$rpt/power_${tag}_hier.rpt" r]; set txt [read $f]; close $f
    foreach line_ [split $txt \n] {
        if {[regexp {^\|\s+(u_A|u_B|u_C|u_D|u_mem|u_wmem_bank[0-3]|u_bmem|u_imem_a|u_act_a|u_act_b|u_omem)\s+\|\s*([<0-9.]+)\s*\|} $line_ -> k v]} { say "    $tag  $k = $v W" }
    }
}

# ---------------------------------------------------------------- P0
pw vectorless

# ---------------------------------------------------------------- P1
if {![file exists $saif]} { say "SAIF not found: $saif"; close $sf; exit 1 }
if {[catch {read_saif -strip_path tb_npu_top/u_top $saif} err]} { say "read_saif failed: $err" }
pw saif

# BRAM enable 핀의 현재 스위칭 확률 (SAIF 기준). 반환: {확률 신호율(Mtr/s) 종류}  종류 = const / logic
set rams [get_cells -hier -filter {REF_NAME =~ RAMB*}]
proc en_info {r} {
    set n [get_nets -quiet -of_objects [get_pins $r/ENARDEN]]
    if {[llength $n] == 0} { return {-1 0 none} }
    if {[get_property TYPE $n] eq "POWER"}  { return {1.0 0 const} }
    if {[get_property TYPE $n] eq "GROUND"} { return {0.0 0 const} }
    set s [report_switching_activity -static_probability -signal_rate -return_string $n]
    set p -1; set sr 0
    regexp {static probability = ([0-9.eE+-]+)} $s -> p
    regexp {signal rate = ([0-9.eE+-]+)} $s -> sr
    return [list $p $sr logic]
}
proc en_table {tag} {
    foreach blk {u_wmem_bank0 u_wmem_bank1 u_wmem_bank2 u_wmem_bank3 u_bmem u_imem_a u_act_a u_act_b u_omem} {
        set sum 0.0; set cnt 0; set nconst 0
        foreach r [get_cells -hier -quiet -filter "REF_NAME =~ RAMB* && NAME =~ *$blk/*"] {
            lassign [en_info $r] p sr kind
            if {$p >= 0} { set sum [expr {$sum + $p}]; incr cnt }
            if {$kind eq "const"} { incr nconst }
        }
        if {$cnt > 0} { say "  enable ($tag) $blk : $cnt primitives ($nconst tied to 1), average enable probability [format %.4f [expr {$sum / $cnt}]], sum [format %.3f $sum]" }
    }
}
en_table saif

# ---------------------------------------------------------------- P2: ena 게이팅 가정
#   WMEM 뱅크 i : 지금 확률 p (주소 디코드만) -> p x (그 뱅크 차례인 ISSUE 클럭 비율)
#     뱅크별 ISSUE 클럭 수 (사진 1장): FC1 128x196, FC2 32x128, FC3 뱅크0·1 은 3x32, 뱅크2·3 은 2x32  / 전체 119,009클럭
#   enable 이 1 에 묶인(const) primitive 와 BMEM 은 스위칭 확률을 덮어쓸 수 없어서 여기서는 그대로 둠 (보고서에서 따로 계산)
set T 119009.0
array set frac {}
set frac(0) [expr {(128*196 + 32*128 + 3*32) / $T}]
set frac(1) $frac(0)
set frac(2) [expr {(128*196 + 32*128 + 2*32) / $T}]
set frac(3) $frac(2)
set nset 0; set nfail 0; set nconst 0
# 여러 primitive 가 같은 enable 선을 같이 쓰므로, 선마다 원래 확률을 먼저 모은 다음 한 번씩만 바꿈
array set plan {}
for {set i 0} {$i < 4} {incr i} {
    foreach r [get_cells -hier -quiet -filter "REF_NAME =~ RAMB* && NAME =~ *u_wmem_bank$i/*"] {
        lassign [en_info $r] p sr kind
        if {$kind eq "const"} { incr nconst; continue }
        if {$p < 0} { incr nfail; continue }
        set n [get_nets -of_objects [get_pins $r/ENARDEN]]
        set nr [expr {$sr * $frac($i)}]
        if {$nr < 0.001} { set nr 0.3 }   ;# 계속 켜져 있던 것은 뉴런마다 켜졌다 꺼지는 정도(약 0.3 Mtr/s)로 가정
        set plan($n) [list [expr {$p * $frac($i)}] $nr]
    }
}
foreach n [array names plan] {
    lassign $plan($n) np nr
    if {[catch {set_switching_activity -static_probability $np -signal_rate $nr [get_nets $n]} e]} { incr nfail } else { incr nset }
}
say "what-if: enable probability scaled on $nset WMEM enable nets (x [format %.4f $frac(0)] for bank 0/1, x [format %.4f $frac(2)] for bank 2/3), skipped $nconst tied-to-1 primitives, failed $nfail"
en_table gated
pw saif_ena_gated

close $sf
close_design
close_project
exit 0
