create_clock -name clk -period 20.000 -waveform {0.000 10.000} [get_ports {clk}]
derive_clocks
rename_clock -name {sd_card_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_sys_pll/pll_inst.clkc[0]}]
rename_clock -name {ext_mem_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_sys_pll/pll_inst.clkc[1]}]
rename_clock -name {ext_mem_clk_sft} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_sys_pll/pll_inst.clkc[2]}]
rename_clock -name {board_pixel_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_video_pll/pll_inst.clkc[0]}]
rename_clock -name {hdmi_5x_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_video_pll/pll_inst.clkc[1]}]
create_clock -name {link_clk} -period 40.000 -waveform {0.000 20.000} [get_ports {link_clk}]
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
# u_clock_check's outputs are unused in this top and synthesis removes the
# entire monitor (confirmed by the mapped area hierarchy). No monitor Gray
# bus remains to constrain. The active FIFO Gray buses retain their IP SDC.
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
set_false_path -to [get_regs -nowarn {*spi_miso_meta* *hpd_audio_meta* *audio_diag_meta* *award_diag_meta*}]
set_output_delay -clock {board_pixel_clk} -max 2.000 [get_ports {audio_sclk audio_cs audio_mosi}]
set_output_delay -clock {board_pixel_clk} -min 0.500 [get_ports {audio_sclk audio_cs audio_mosi}]
set_false_path -to [get_regs -nowarn {*color_meta* *color_link_meta*}]

# RGB format reset is asserted asynchronously, then released by the three
# local reset flops rcm/rcl. Only asynchronous SR pins are excepted;
# all register D paths and local reset shift-register paths remain timed.
set_false_path -from [get_regs -nowarn {image_reset_count* rcm/sync_ff* rcl/sync_ff*}] -to [get_pins -nowarn {*.sr}]

# Additional first-stage samplers for the fluid transaction/frame selectors.
set_false_path -to [get_regs -nowarn {*fluid_link_meta* *fluid_meta* *fluid_mode_meta* *read_request_pipe[0]* store/rw/fluid_reader/c0*}]

# The fluid reader owns the same asynchronous output-FIFO clear as the legacy reader.
set_false_path -from [get_regs -nowarn {store/rw/fluid_reader/fifo_aclr*}] -to [get_pins -nowarn {*.sr}]

# Trophy-v5: only the first sampler of each toggle or held data bundle is
# asynchronous. The following synchronizers, RAM ports and consumers stay timed.
set_false_path -to [get_regs -nowarn {*award_link_meta* store/award_w0* store/award_r0* store/light_en0* store/slot_m0* award_render/lights/enable_meta* award_render/lights/request_sync[0]* award_render/lights/request_frame_meta* award_render/lights/request_row_meta* award_render/lights/request_initial_meta* award_render/lights/done_sync[0]* award_render/lights/startup_sync[0]* award_render/lights/video_error_sync[0]*}]

# Thumbnail toggles and held row/slot bundles: only the first sampler is
# asynchronous. The next synchronizer stages and both eRAM ports stay timed.
set_false_path -to [get_regs -nowarn {store/display_meta* store/thumbnails/job_sync[0]* store/thumbnails/slot_meta* store/thumbnails/cancel_meta* store/thumbnails/blank_meta* preview/done_sync[0]*}]

# Relief player: only first-stage CDC samplers are asynchronous. Requested
# angle/row stay stable until the return toggle; both RAM clock ports are timed.
set_false_path -to [get_regs -nowarn {award_render/relief_meta* award_render/gold/player/enable_meta* award_render/gold/player/request_sync[0]* award_render/gold/player/angle_meta* award_render/gold/player/row_meta* award_render/gold/player/done_sync[0]* award_render/gold/player/ready_sync[0]*}]
