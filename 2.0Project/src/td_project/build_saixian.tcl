set alRun phy_1
set device_name eagle_s20.db
set package_name EG4S20BG256
set prj_name {SAIXIAN_KEY2_TF_20261010}
set top_model_name {top}
set ADCList {{../user_source/constraints_source/pin.adc}}
set SDCList {{../user_source/constraints_source/timing.sdc}}
set IpSDCList { rfifo_32_32_512 ../user_source/hdl_source/IP/afifo_32_16_256.tcl wfifo_32_32_512 ../user_source/hdl_source/IP/afifo_16_32_256.tcl }
set start_step read_design
set parent {.}
if {[info exists ::env(SAIXIAN_START_STEP)]} { set start_step $::env(SAIXIAN_START_STEP) }
set end_step bitgen
set area_option -packarea
set arr_filter false
set drHoldFix on
set phyWildParams {place seed 7}
if {[info exists ::env(SAIXIAN_PLACE_SEED)]} {
    set phyWildParams [list place seed $::env(SAIXIAN_PLACE_SEED)]
}
# Strengthen post-route optimization without changing clock constraints.
lappend phyWildParams route post_route_opt high
lappend phyWildParams route effort high
# TD official AreaOptimizeHigh parameters, applied directly so builds do
# not depend on a per-user GUI strategy file.
lappend phyWildParams gate add_map_lut_struct high
lappend phyWildParams gate map_mode area_prior
lappend phyWildParams rtl dsp_pack_zreg on
lappend phyWildParams gate multi_thread_mapping partition
lappend phyWildParams rtl resource_sharing auto
lappend phyWildParams rtl shifter_style shifter_reg
lappend phyWildParams gate merge_tiny_lut on
lappend phyWildParams gate pack_effort high
lappend phyWildParams gate opt_area high
lappend phyWildParams place pack_mode area
lappend phyWildParams place effort high
lappend phyWildParams place opt_timing high
lappend phyWildParams place relaxation 0.97
lappend phyWildParams place post_place_opt high
# TD official TimingHighest: focus critical/high-fanout nets and run extra
# post-route timing optimization while retaining the original constraints.
lappend phyWildParams place logic_level_opt on
lappend phyWildParams place timing_driven_mode on
lappend phyWildParams place shifter_opt on
lappend phyWildParams place crit_path_opt on
lappend phyWildParams place hfn_opt_effort high
lappend phyWildParams place split_data_from_clock on
lappend phyWildParams route postrt_opt_extra_round 4
# This high-utilization design needs the explicit route hold-fix stage.  The
# automatic in-route pass is skipped above 90% slice utilization.  Keep the
# normal route phase enabled, then invoke the tool's official fix_hold phase
# and generate the final routed timing report after that phase.
set arr_filter on
set arr_rwns -100000
set tdRoot {D:/TD}
if {[info exists ::env(SAIXIAN_TD_ROOT)]} { set tdRoot $::env(SAIXIAN_TD_ROOT) }
# Use the pinned TD 6.2 default flow, including its explicit hold-fix stage.


source [file join [file dirname [info script]] key2_tf_flow.tcl]
