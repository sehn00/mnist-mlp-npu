# ============================================================================
# run_sim.tcl : one-click Vivado batch flow for D block + integration test
#   1) create a NEW project (vivado_sim/), does not touch aissd_mnist_npu
#   2) re-create the 10 BRAM IPs with the same settings as memory_controller.zip .xci, EXCEPT:
#      Primitives Output Register is OFF on every IP (project guideline p.9) = read latency 1.
#      (The team .xci of 11/12 has it ON for WMEM/BMEM. Add "oreg_on" to rebuild that old setup.)
#   3) run tb_npu_ctrl (D unit test) and tb_npu_top (A+B+C+D, N_IMG images)
#   4) write a summary to result.txt. Exit code 0 only if both testbenches print their PASS line, else 1.
#   Before simulating, scripts/check_ip.py checks the 10 IPs (width, depth, output registers, init files
#   vs data/coe/) against the RTL RD_LAT (11/15 review D03). A mismatch stops the run with exit code 1.
# ============================================================================
# Usage: double-click scripts/run_sim.bat, or (from the repository root) (create the logs folder first: mkdir logs)
#        vivado -mode batch -source scripts/run_sim.tcl -log logs/run_sim.log -journal logs/run_sim.jou -notrace
#   add at the end, in any order:
#        -tclargs 100              100 images (default 10)
#        -tclargs fresh            delete + re-create project and IPs
#        -tclargs 10 fresh oreg_on old setup: WMEM/BMEM register ON, RD_LAT=2
# The project (vivado_sim/) and its 10 IPs are re-used if they already exist.
# After changing an IP setting, always run once with "fresh".
# Full regression (these two testbenches + checker, stress images, edge cases): bash scripts/run_regress.sh
# If this variable is set, cmd.exe does not look in the current folder, and Vivado then fails
# to start compile.bat ("Spawn failed: Broken pipe"). Clear it for this Vivado process only.
catch {unset ::env(NoDefaultCurrentDirectoryInExePath)}

set N_IMG 10
set fresh 0
# WMEM/BMEM primitives output register: false = guideline p.9 (RD_LAT=1), true = team .xci of 11/12 (RD_LAT=2)
set WB_OREG false
foreach a $argv {
    if {[string is integer -strict $a] && $a > 0} { set N_IMG $a
    } elseif {$a eq "fresh"}   { set fresh 1
    } elseif {$a eq "oreg_on"} { set WB_OREG true
    } else {
        puts "run_sim.tcl: unknown argument '$a' (use: <number of images> fresh oreg_on)"
        exit 1
    }
}
set all_pass 1

set here     [file normalize [file join [file dirname [info script]] ..]]   ;# repository root (this script is in scripts/)
set proj_dir "$here/vivado_sim"
set hex_dir  "$here/data/hex"
set coe_dir  "$here/data/coe"
set log_dir  "$here/logs"
set result   "$here/result.txt"
file mkdir $log_dir

set rf [open $result w]
puts $rf "run_sim.tcl  [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
puts $rf "Vivado [version -short]"
close $rf
proc note {msg} {
    global result
    set f [open $result a]; puts $f $msg; close $f
    puts "### $msg"
}

# 10 IPs (width, depth, output registers, init files) vs the RTL RD_LAT: scripts/check_ip.py (review D03)
proc check_ip_cfg {rd_lat} {
    global here
    set py python
    if {[info exists ::env(NPU_PYTHON)]} { set py $::env(NPU_PYTHON) }   ;# not PYTHON: Vivado sets that to its own folder
    set args [list "$here/scripts/check_ip.py"]
    if {$rd_lat ne ""} { lappend args --rd-lat $rd_lat }
    set rc [catch {exec $py {*}$args 2>@1} out]
    foreach line [split $out "\n"] { if {$line ne ""} { note "  $line" } }
    if {$rc} {
        if {[lindex $::errorCode 0] ne "CHILDSTATUS"} { note "  check_ip.py could not run with '$py' (set NPU_PYTHON to the python.exe path)" }
        return 0
    }
    return 1
}

# ---------------------------------------------------------------- project + BRAM IPs
proc mk_bram {name width depth oreg coe} {
    create_ip -name blk_mem_gen -vendor xilinx.com -library ip -module_name $name
    set cfg [list]
    lappend cfg CONFIG.Memory_Type {Single_Port_RAM}
    lappend cfg CONFIG.Write_Width_A $width
    lappend cfg CONFIG.Write_Depth_A $depth
    lappend cfg CONFIG.Read_Width_A $width
    lappend cfg CONFIG.Operating_Mode_A {WRITE_FIRST}
    lappend cfg CONFIG.Enable_A {Use_ENA_Pin}
    lappend cfg CONFIG.Register_PortA_Output_of_Memory_Primitives $oreg
    lappend cfg CONFIG.Register_PortA_Output_of_Memory_Core {false}
    if {$coe ne ""} {
        lappend cfg CONFIG.Load_Init_File {true} CONFIG.Coe_File $coe
    }
    set_property -dict $cfg [get_ips $name]
}

if {!$fresh && [file exists "$proj_dir/aissd_D_sim.xpr"]} {
    open_project "$proj_dir/aissd_D_sim.xpr"
    note "project re-used ([llength [get_ips]] IPs)"
} else {
    create_project aissd_D_sim $proj_dir -part xck26-sfvc784-2LV-c -force
    set_property target_language Verilog [current_project]
    add_files -norecurse [glob $here/rtl/*.v]
    if {[catch {
        mk_bram wmem_bank0  32 29280 $WB_OREG "$coe_dir/weight_bank0.coe"
        mk_bram wmem_bank1  32 29280 $WB_OREG "$coe_dir/weight_bank1.coe"
        mk_bram wmem_bank2  32 29280 $WB_OREG "$coe_dir/weight_bank2.coe"
        mk_bram wmem_bank3  32 29280 $WB_OREG "$coe_dir/weight_bank3.coe"
        mk_bram bmem_128   128   163 $WB_OREG "$coe_dir/bias_128bit.coe"
        mk_bram imem_a_bram 32   196 false ""
        mk_bram imem_b_bram 32   196 false ""
        mk_bram act_a_bram  32   128 false ""
        mk_bram act_b_bram  32    32 false ""
        mk_bram omem_bram   32    10 false ""
        generate_target {instantiation_template simulation} [get_ips]
    } err]} {
        note "IP creation FAILED: $err"
        exit 1
    }
    note "IP creation OK (10 blk_mem_gen)"
}
# The RTL read latency must match the IPs: stop if a re-used project has a different register setting.
foreach ip [get_ips] {
    set nm   [get_property NAME $ip]
    set want false
    if {[string match {wmem_bank*} $nm] || $nm eq "bmem_128"} { set want $WB_OREG }
    set got  [get_property CONFIG.Register_PortA_Output_of_Memory_Primitives $ip]
    if {$got ne $want} {
        note "IP $nm : primitives output register is $got, expected $want -> run again with: -tclargs $N_IMG fresh"
        close_project
        exit 1
    }
}
note "BRAM primitives output register: WMEM/BMEM $WB_OREG, others false (RD_LAT = [expr {$WB_OREG ? 2 : 1}])"
if {![check_ip_cfg [expr {$WB_OREG ? 2 : 1}]]} {
    note "IP check FAILED (scripts/check_ip.py) -> fix the IPs (run again with: -tclargs $N_IMG fresh)"
    close_project
    exit 1
}

# ---------------------------------------------------------------- sim sources
# local copy of tb_npu_top.v with absolute HEX_DIR
set f [open "$here/tb/tb_npu_top.v" r]; fconfigure $f -encoding utf-8; set src [read $f]; close $f
set src_new [string map [list "`define HEX_DIR \"hex/\"" "`define HEX_DIR \"$hex_dir/\""] $src]
if {$src_new eq $src} {
    note "tb_npu_top.v : the line `define HEX_DIR \"hex/\" was not found, cannot point the testbench at $hex_dir -> FAIL"
    close_project
    exit 1
}
set src $src_new
file mkdir "$here/build"
set tb_local "$here/build/tb_npu_top_local.v"
set f [open $tb_local w]; fconfigure $f -encoding utf-8; puts -nonewline $f $src; close $f

foreach tbf [list "$here/tb/tb_npu_ctrl.v" $tb_local] {
    if {[llength [get_files -quiet -of_objects [get_filesets sim_1] $tbf]] == 0} {
        add_files -fileset sim_1 -norecurse $tbf
    }
}
set defs [list "N_IMG=$N_IMG"]
if {$WB_OREG} { lappend defs "OREG_ON" }
set_property verilog_define $defs [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

proc run_tb {top runtime} {
    global proj_dir log_dir all_pass
    set passed 0
    set xdir "$proj_dir/aissd_D_sim.sim/sim_1/behav/xsim"
    foreach lg {simulate.log compile.log elaborate.log xvlog.log} { file delete -force "$xdir/$lg" }
    set_property top $top [get_filesets sim_1]
    set_property -name {xsim.simulate.runtime} -value $runtime -objects [get_filesets sim_1]
    update_compile_order -fileset sim_1
    if {[catch {launch_simulation} err]} {
        note "$top : launch_simulation FAILED: $err"
    }
    catch {close_sim -force}
    set slog "$xdir/simulate.log"
    if {[file exists $slog]} {
        file copy -force $slog "$log_dir/${top}_simulate.log"
        set f [open $slog r]; set txt [read $f]; close $f
        set nwarn 0
        foreach line [split $txt \n] {
            if {[regexp {PASS|FAIL|ERR|TIMEOUT|GO count|bias_we count|last o_waddr|start->done|RD_LAT|golden bit|prediction|clock count|^img } $line]} {
                note "  $line"
            }
            if {[regexp -nocase {warning|outside range} $line]} { incr nwarn }
        }
        note "  simulator warnings in simulate.log: $nwarn"
        # PASS only if the testbench printed its own PASS line and no FAIL / TIMEOUT line
        if {[string first "*** $top PASS ***" $txt] >= 0 && ![regexp "\\*\\*\\* $top FAIL|TIMEOUT" $txt]} { set passed 1 }
    } else {
        note "$top : simulate.log not found (see $xdir/)"
    }
    if {!$passed} {
        set all_pass 0
        note "  => $top did NOT pass"
    }
    foreach lg {compile.log elaborate.log} {
        if {[file exists "$xdir/$lg"]} { file copy -force "$xdir/$lg" "$log_dir/${top}_$lg" }
    }
}

note "==== tb_npu_ctrl (D unit test, RD_LAT=1) ===="
run_tb tb_npu_ctrl 2ms
note "==== tb_npu_top (A+B+C+D, $N_IMG images) ===="
run_tb tb_npu_top [expr {$N_IMG * 2}]ms

note "done. logs: $log_dir"
close_project
if {$all_pass} {
    note "RESULT: PASS (tb_npu_ctrl and tb_npu_top, $N_IMG images)"
    exit 0
} else {
    note "RESULT: FAIL (see the lines above and $log_dir)"
    exit 1
}
