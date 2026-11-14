# ============================================================================
# run_sim.tcl : one-click Vivado batch flow for D block + integration test
#   1) create a NEW project (vivado_sim/), does not touch aissd_mnist_npu
#   2) re-create the 10 BRAM IPs with the same settings as memory_controller.zip .xci
#      (WMEM/BMEM: output register ON = read latency 2, COE init / others: latency 1)
#   3) run tb_npu_ctrl (D unit test) and tb_npu_top (A+B+C+D, N_IMG images)
#   4) write a summary to result.txt
# Usage: double-click run_sim.bat  (or: vivado -mode batch -source run_sim.tcl)
# ============================================================================
set N_IMG 10

set here     [file normalize [file dirname [info script]]]
set proj_dir "$here/vivado_sim"
set hex_dir  "$here/hex"
set coe_dir  "$here/coe"
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

# ---------------------------------------------------------------- project
create_project aissd_D_sim $proj_dir -part xck26-sfvc784-2LV-c -force
set_property target_language Verilog [current_project]
add_files -norecurse [glob $here/rtl/*.v]

# ---------------------------------------------------------------- BRAM IPs
proc mk_bram {name width depth oreg coe} {
    create_ip -name blk_mem_gen -vendor xilinx.com -library ip -module_name $name
    set cfg [list \
        CONFIG.Memory_Type {Single_Port_RAM} \
        CONFIG.Write_Width_A $width \
        CONFIG.Write_Depth_A $depth \
        CONFIG.Read_Width_A $width \
        CONFIG.Operating_Mode_A {WRITE_FIRST} \
        CONFIG.Enable_A {Use_ENA_Pin} \
        CONFIG.Register_PortA_Output_of_Memory_Primitives $oreg \
        CONFIG.Register_PortA_Output_of_Memory_Core {false} ]
    if {$coe ne ""} {
        lappend cfg CONFIG.Load_Init_File {true} CONFIG.Coe_File $coe
    }
    set_property -dict $cfg [get_ips $name]
}

if {[catch {
    mk_bram wmem_bank0  32 29280 true  "$coe_dir/weight_bank0.coe"
    mk_bram wmem_bank1  32 29280 true  "$coe_dir/weight_bank1.coe"
    mk_bram wmem_bank2  32 29280 true  "$coe_dir/weight_bank2.coe"
    mk_bram wmem_bank3  32 29280 true  "$coe_dir/weight_bank3.coe"
    mk_bram bmem_128   128   163 true  "$coe_dir/bias_128bit.coe"
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

# ---------------------------------------------------------------- sim sources
# local copy of tb_npu_top.v with absolute HEX_DIR
set f [open "$here/tb/tb_npu_top.v" r]; fconfigure $f -encoding utf-8; set src [read $f]; close $f
set src [string map [list "`define HEX_DIR \"hex/\"" "`define HEX_DIR \"$hex_dir/\""] $src]
file mkdir "$here/build"
set tb_local "$here/build/tb_npu_top_local.v"
set f [open $tb_local w]; fconfigure $f -encoding utf-8; puts -nonewline $f $src; close $f

add_files -fileset sim_1 -norecurse [list "$here/tb/tb_npu_ctrl.v" $tb_local]
set_property verilog_define [list "N_IMG=$N_IMG"] [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

proc run_tb {top runtime} {
    global proj_dir log_dir
    set_property top $top [get_filesets sim_1]
    set_property -name {xsim.simulate.runtime} -value $runtime -objects [get_filesets sim_1]
    update_compile_order -fileset sim_1
    if {[catch {launch_simulation} err]} {
        note "$top : launch_simulation FAILED: $err"
    }
    catch {close_sim -force}
    set slog "$proj_dir/aissd_D_sim.sim/sim_1/behav/xsim/simulate.log"
    if {[file exists $slog]} {
        file copy -force $slog "$log_dir/${top}_simulate.log"
        set f [open $slog r]; set txt [read $f]; close $f
        foreach line [split $txt "\n"] {
            if {[regexp {PASS|FAIL|ERR|TIMEOUT|GO count|bias_we count|last o_waddr|start->done|RD_LAT|golden bit|prediction|^img } $line]} {
                note "  $line"
            }
        }
    } else {
        note "$top : simulate.log not found (see $proj_dir/aissd_D_sim.sim/sim_1/behav/xsim/)"
    }
    foreach lg {compile.log elaborate.log} {
        set p "$proj_dir/aissd_D_sim.sim/sim_1/behav/xsim/$lg"
        if {[file exists $p]} { file copy -force $p "$log_dir/${top}_$lg" }
    }
}

note "==== tb_npu_ctrl (D unit test, RD_LAT=1) ===="
run_tb tb_npu_ctrl 2ms
note "==== tb_npu_top (A+B+C+D, $N_IMG images) ===="
run_tb tb_npu_top [expr {$N_IMG * 2}]ms

note "done. logs: $log_dir"
close_project
exit 0
