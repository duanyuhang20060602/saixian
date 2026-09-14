set alRun phy_1
set device_name eagle_s20.db
set package_name EG4S20BG256
set prj_name {HDMI1.4b_Transmitter_v1.0}
set top_model_name {top}
set ADCList {{../user_source/constraints_source/pin.adc}}
set SDCList {{../user_source/constraints_source/timing.sdc}}
set IpSDCList { rfifo_32_32_512 ../user_source/hdl_source/IP/afifo_32_16_256.tcl wfifo_32_32_512 ../user_source/hdl_source/IP/afifo_16_32_256.tcl }
set start_step read_design
set end_step bitgen
set area_option -packarea
set arr_filter false
set drHoldFix on
source {C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/doc/scripts/DefaultFlow.tcl}
