set alRun phy_1
set device_name eagle_s20.db
set package_name EG4S20BG256
set prj_name WATER_SINGLE
set top_model_name top_water_single
set ADCList {pins.adc}
set SDCList {timing.sdc}
set start_step read_design
set end_step bitgen
if {[info exists ::env(WATER_ELAB_ONLY)]} {set end_step read_design}
set area_option -packarea
set arr_filter false
set drHoldFix on
set phyWildParams {place seed 14 rtl resource_sharing auto gate map_mode area_prior gate add_map_lut_struct high place effort high place timing_driven_mode on route effort high route post_route_opt high}
set tdRoot {C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116}
if {[catch {source [file join $tdRoot doc scripts DefaultFlow.tcl]} err]} {puts stderr $err;exit 1}
exit 0

