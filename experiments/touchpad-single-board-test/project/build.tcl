set alRun phy_1
set device_name eagle_s20.db
set package_name EG4S20BG256
set prj_name TOUCHPAD_SINGLE_TEST
set top_model_name top_touch_single
set ADCList {../constraints/pins.adc}
set SDCList {../constraints/timing.sdc}
set IpSDCList {}
set start_step read_design
set end_step bitgen
set parent [pwd]
set area_option -packarea
set drHoldFix on
set arr_filter on
set arr_rwns -100000
set phyWildParams {place seed 31 route post_route_opt high route effort high}
source C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/doc/scripts/DefaultFlow.tcl
