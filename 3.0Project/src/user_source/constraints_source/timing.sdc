create_clock -name clk -period 20.000 -waveform {0.000 10.000} [get_ports {clk}]
derive_clocks
rename_clock -name {sd_card_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_sys_pll/pll_inst.clkc[0]}]
rename_clock -name {ext_mem_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_sys_pll/pll_inst.clkc[1]}]
rename_clock -name {ext_mem_clk_sft} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_sys_pll/pll_inst.clkc[2]}]
rename_clock -name {video_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_video_pll/pll_inst.clkc[0]}]
rename_clock -name {hdmi_5x_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_video_pll/pll_inst.clkc[1]}]
set_false_path -to [get_regs {upload_done_meta file_words_meta[*] frame_count_meta[*] frame_sync[0] commit_sync[0] active_meta display_meta pause_meta video_scan/publish_sync[0] video_scan/slot_meta hpd_meta}]
set_false_path -to [get_regs {diagnostics/status_meta[*] diagnostics/debug_meta[*] diagnostics/mode_meta diagnostics/key_meta}]
set_false_path -to [get_regs {payload_crc_meta[*]}]
set_false_path -from [get_regs {por_count[22]}] -to [get_clocks {hdmi_5x_clk}]
# Native Gray-pointer FIFOs: constrain physical skew to below the fastest
# clock period instead of masking payload paths with clock-group exceptions.
set_max_delay -from [get_regs {*/primary_addr_gray_reg[*]}] -to [get_regs {*/sync_r1[*]}] 9.700 -datapath_only
set_false_path -hold -to [get_regs {*/sync_r1[*]}]
