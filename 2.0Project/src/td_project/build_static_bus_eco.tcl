# TD 6.2 native ECO: retain the timing-pass preload placement and routing.
# verify_static_eco.py checks the checkpoint hash, the exact two RTL edits,
# all other user-source files and the complete implemented netlist delta.
set ecoProjectDir [file dirname [file normalize [info script]]]
set ecoRoot [file normalize [file join $ecoProjectDir ../..]]
set ecoProofDir [file join $ecoRoot validation key2_tf_20261010 static_bus_eco]
file mkdir $ecoProofDir
set ecoName SAIXIAN_KEY2_TF_20261010
import_device eagle_s20.db -package EG4S20BG256
import_db "$ecoProjectDir/static_bus_baseline/baseline_pr.db"
set_param place seed 3
write_verilog "$ecoProofDir/baseline_phy.v" -implement
eco_lock_design
# The frozen native FSM encodes IDLE/COMMAND_CLEAR/VIDEO_CLEAR as bits 0/5/6.
# This cell's LUT0 is the single shared session && !IDLE bus select.
# Its LUT1 and two registered DLT header bits are left intact.
set ecoTarget {u_tf_animation/loader/header_reg[234]_syn_4}
connect_net -net {u_tf_animation/memory_bus/state_reg_syn_1[5]} -objects {{u_tf_animation/loader/header_reg[234]_syn_4.a[0]}}
connect_net -net {u_tf_animation/memory_bus/state_reg_syn_1[6]} -objects {{u_tf_animation/loader/header_reg[234]_syn_4.b[0]}}
set_inst_attr -model_name top -inst $ecoTarget -attr_key LUT0 -attr_value {=(~A*~B*~C*D)}
write_verilog "$ecoProofDir/patched_phy.v" -implement
place -eco
route -eco
fix_hold -eco
report_area -io_info -file "$ecoProjectDir/${ecoName}_phy.area"
update_timing -mode final
report_timing_summary -file "$ecoProjectDir/${ecoName}_pr.timing"
write_verilog "$ecoProofDir/routed_phy.v" -implement
export_db "$ecoProjectDir/${ecoName}_pr.db"
bitgen -bit "$ecoProjectDir/${ecoName}.bit"
exit
