set alRun phy_1
set device_name eagle_s20.db
set package_name EG4S20BG256
set prj_name {HDMI1.4b_Transmitter_v2.0}
set top_model_name {top}
set ADCList {{../user_source/constraints_source/pin.adc}}
set SDCList {{../user_source/constraints_source/timing.sdc}}
set IpSDCList { rfifo_32_32_512 ../user_source/hdl_source/IP/afifo_32_16_256.tcl wfifo_32_32_512 ../user_source/hdl_source/IP/afifo_16_32_256.tcl }
set start_step read_design
set end_step bitgen
set area_option -packarea
set arr_filter false
set drHoldFix on
set phyWildParams {place seed 12}
if {[info exists ::env(SAIXIAN_PLACE_SEED)]} {
    set phyWildParams [list place seed $::env(SAIXIAN_PLACE_SEED)]
}
# Strengthen post-route optimization without changing clock constraints.
lappend phyWildParams route post_route_opt high
lappend phyWildParams route effort high
# This high-utilization design needs the explicit route hold-fix stage.  The
# automatic in-route pass is skipped above 90% slice utilization.  Keep the
# normal route phase enabled, then invoke the tool's official fix_hold phase
# and generate the final routed timing report after that phase.
set arr_filter on
set arr_rwns -100000
set tdRoot {C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116}
if {[info exists ::env(SAIXIAN_TD_ROOT)]} { set tdRoot $::env(SAIXIAN_TD_ROOT) }
source [file join $tdRoot doc scripts DefaultFlow.tcl]
