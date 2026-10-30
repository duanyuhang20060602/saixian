set alRun phy_1
set device_name eagle_s20.db
set package_name EG4S20BG256
set prj_name TEXT_DEMO_J1
set top_model_name top_text_demo
set ADCList {pins.adc}
set SDCList {timing.sdc}
set IpSDCList {}
set start_step read_design
set end_step bitgen
set area_option -packarea
set arr_filter false
set drHoldFix on
set phyWildParams {place seed 17}
source {C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/doc/scripts/DefaultFlow.tcl}
