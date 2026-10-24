create_clock -name clk -period 20.000 -waveform {0.000 10.000} [get_ports {clk}]
derive_clocks
rename_clock -name {sd_card_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_sys_pll/pll_inst.clkc[0]}]
rename_clock -name {link_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_link_pll/pll_inst.clkc[0]}]
set_output_delay -clock {link_clk} -clock_fall -max 2.000 [get_ports {link_data[*] link_valid link_sof link_eof}]
set_output_delay -clock {link_clk} -clock_fall -min 0.000 [get_ports {link_data[*] link_valid link_sof link_eof}]
set_input_delay -clock {link_clk} -max 2.000 [get_ports {link_ready}]
set_input_delay -clock {link_clk} -min 0.500 [get_ports {link_ready}]



set_false_path -to [get_regs -nowarn {*ack_meta* *finish_meta* *valid_meta* *ready_meta* *init_meta* *error_meta* *load_meta* *hpd_meta* *status_meta* *write_req_d0* *read_req_d0* *wrfin_sync[0]* *commit_sync[0]*}]
# B's mapped FIFO has no supported *.sr endpoints with the old reset names.
# Keep these reset paths timed instead of issuing an ineffective exception.
 
# photo CDC: cut only first-stage synchronizers; bundled metadata remains
# stable for the complete transaction. Gray FIFO paths retain IP constraints.
set_false_path -to [get_regs -nowarn {*event_meta* *rx_meta* *fault_meta* *armed_meta* *fin_meta* *key_meta* *sync_key[0]* *key_sync[0]* *write_addr_index_d0* *read_addr_index_d0* *slide_old_d0* *slide_new_d0* *slide_active_d0* *slide_right_d0* *slide_offset_d0* *transition_mode_d0*}]
set_false_path -from [get_ports {control_rx}]
set_false_path -from [get_ports {key2_n}]
set_false_path -to [get_regs -nowarn {*settings_meta* *gain_meta* *processing/ack_meta*}]
# AUDIO1: SPI oversampling, cut only async first stages.
# These asynchronous ports feed only the SPI first-stage input registers.
# Port endpoints remain valid when physical packing renames those registers.
set_false_path -from [get_ports {audio_sclk audio_cs audio_mosi}]
set_output_delay -clock {sd_card_clk} -max 2.000 [get_ports {audio_miso}]
set_output_delay -clock {sd_card_clk} -min 0.500 [get_ports {audio_miso}]
set_false_path -to [get_regs -nowarn {*color_meta* *color_link_meta*}]
set_false_path -to [get_regs -nowarn {*award_meta*}]
set_false_path -to [get_regs -nowarn {*top_down_meta*}]

# AV metadata address/data bundles are held for a full SPI word (~8.5 us).
# Only first-stage samplers are asynchronous; the consumer waits until bit 24.
set_false_path -to [get_regs -nowarn {*av_address_meta* *av_data_meta* *av_pcm_meta*}]

# Trophy-v5 format selectors: first-stage samplers only.
set_false_path -to [get_regs -nowarn {store/award_w0* store/award_r0*}]
