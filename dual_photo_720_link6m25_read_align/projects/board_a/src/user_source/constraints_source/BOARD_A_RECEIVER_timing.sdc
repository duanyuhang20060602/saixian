create_clock -name clk -period 20.000 -waveform {0.000 10.000} [get_ports {clk}]
derive_clocks
rename_clock -name {sd_card_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_sys_pll/pll_inst.clkc[0]}]
rename_clock -name {ext_mem_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_sys_pll/pll_inst.clkc[1]}]
rename_clock -name {ext_mem_clk_sft} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_sys_pll/pll_inst.clkc[2]}]
rename_clock -name {board_pixel_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_video_pll/pll_inst.clkc[0]}]
rename_clock -name {hdmi_5x_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_video_pll/pll_inst.clkc[1]}]
create_clock -name {link_clk} -period 20.000 -waveform {0.000 10.000} [get_ports {link_clk}]
set_input_delay -clock {link_clk} -clock_fall -max 2.000 [get_ports {link_data[*] link_valid link_sof link_eof}]
set_input_delay -clock {link_clk} -clock_fall -min 0.500 [get_ports {link_data[*] link_valid link_sof link_eof}]



set_false_path -to [get_regs -nowarn {*ack_meta* *finish_meta* *valid_meta* *ready_meta* *init_meta* *error_meta* *load_meta* *hpd_meta* *status_meta* *menu_meta* *menu_digits_meta* *write_req_d0* *read_req_d0* *wrfin_sync[0]* *commit_sync[0]*}]
 # FIFO reset assertion is asynchronous; deassertion uses the two local reset
 # flops. Cut only their async reset pins, retaining local D-path timing.
set_false_path -to [get_pins -nowarn {*asy_w_rst*.sr *asy_r_rst*.sr}]
 # Generated RAM/FIFO async output resets can be packed into cells whose
 # physical names belong to a neighboring video register. Match by source
 # and reset pin, not the packed cell name. D paths and Gray checks remain.
set_false_path -from [get_regs -nowarn {rm/sync_ff* store/rw/frame_fifo_read_m0/fifo_aclr* store/rw/frame_fifo_write_m0/fifo_aclr*}] -to [get_pins -nowarn {*.sr}]
 set_max_delay -datapath_only -from [get_regs {u_clock_check/pixel_gray*}] -to [get_regs {u_clock_check/gray_meta*}] 10.000
set_min_delay -from [get_regs {u_clock_check/pixel_gray*}] -to [get_regs {u_clock_check/gray_meta*}] 0.000
set_false_path -from [get_ports {hdmi_hpd}]
set_output_delay -clock {link_clk} -max 2.000 [get_ports {link_ready}]
set_output_delay -clock {link_clk} -min 0.500 [get_ports {link_ready}]

# photo CDC: cut only first-stage synchronizers; bundled metadata remains
# stable for the complete transaction. Gray FIFO paths retain IP constraints.
set_false_path -to [get_regs -nowarn {*event_meta* *rx_meta* *fault_meta* *armed_meta* *fin_meta* *key_meta* *sync_key[0]* *key_sync[0]* *write_addr_index_d0* *read_addr_index_d0* *slide_old_d0* *slide_new_d0* *slide_active_d0* *slide_right_d0* *slide_offset_d0* *transition_mode_d0*}]
set_false_path -from [get_ports {control_rx}]
set_false_path -from [get_ports {hmi_uart_rx key[*]}]

# Frozen CRC/page display bundle: first-stage CDC only.
# AUDIO1: SPI oversampling, cut only async first stages.
set_false_path -to [get_regs -nowarn {*spi_miso_meta* *hpd_audio_meta* *audio_diag_meta*}]
set_output_delay -clock {board_pixel_clk} -max 2.000 [get_ports {audio_sclk audio_cs audio_mosi}]
set_output_delay -clock {board_pixel_clk} -min 0.500 [get_ports {audio_sclk audio_cs audio_mosi}]
set_false_path -to [get_regs -nowarn {*color_meta* *color_link_meta*}]

# RGB format reset is asserted asynchronously, then released by the three
# local reset flops rcm/rcl. Only asynchronous SR pins are excepted;
# all register D paths and local reset shift-register paths remain timed.
set_false_path -from [get_regs -nowarn {image_reset_count* rcm/sync_ff* rcl/sync_ff*}] -to [get_pins -nowarn {*.sr}]
