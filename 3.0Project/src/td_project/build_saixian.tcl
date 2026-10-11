set alRun phy_1
set device_name eagle_s20.db
set package_name EG4S20BG256
set prj_name {HDMI1.4b_Transmitter_v3.0_720p_SoftFlow}
set top_model_name {top}
set ADCList {{../user_source/constraints_source/pin.adc}}
set SDCList {{../user_source/constraints_source/timing.sdc}}
set IpSDCList {}
set start_step read_design
set end_step bitgen
set area_option -packarea
set arr_filter on
set arr_rwns -100000
set drHoldFix on
set phyWildParams {place seed 31 route post_route_opt high route effort high gate map_mode area_prior gate pack_seq_in_io off}
if {[info exists ::env(SAIXIAN_PLACE_SEED)]} {set phyWildParams [list place seed $::env(SAIXIAN_PLACE_SEED) route post_route_opt high route effort high gate map_mode area_prior gate pack_seq_in_io off]}
source {C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/doc/scripts/DefaultFlow.tcl}
