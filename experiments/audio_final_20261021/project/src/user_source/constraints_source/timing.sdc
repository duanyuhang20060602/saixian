create_clock -name clk -period 20.000 -waveform {0.000 10.000} [get_ports {clk}]
derive_clocks

rename_clock -name {sd_card_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_sys_pll/pll_inst.clkc[0]}]
rename_clock -name {ext_mem_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_sys_pll/pll_inst.clkc[1]}]
rename_clock -name {ext_mem_clk_sft} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_sys_pll/pll_inst.clkc[2]}]
rename_clock -name {video_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_video_pll/pll_inst.clkc[0]}]
rename_clock -name {hdmi_5x_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_video_pll/pll_inst.clkc[1]}]

# These domains exchange payload only through the official asynchronous FIFOs.
# Control events use two-flop toggle synchronizers in the Saixian RTL.
set_clock_groups -asynchronous \
    -group [get_clocks {sd_card_clk}] \
    -group [get_clocks {ext_mem_clk ext_mem_clk_sft}] \
    -group [get_clocks {video_clk hdmi_5x_clk}]

# Board keys, switches and HPD are explicitly synchronized before use.
set_false_path -from [get_ports {key[*] sw[*] hdmi_hpd}]
# por_count[22] is only the asynchronous assertion source for the per-domain
# reset synchronizers. Reset release is retimed by three destination-clock
# flip-flops, so recovery/removal timing from the 50 MHz counter into the HDMI
# serializer domain is intentionally asynchronous. Keep this exception
# source-specific so ordinary clk-to-hdmi_5x_clk data paths remain analyzed.
set_false_path -from [get_regs {por_count[22]}] \
    -to [get_clocks {hdmi_5x_clk}]
# First stages of the video-to-50MHz status synchronizers are intentional CDC
# sampling points. Only these first-stage registers are exempt; their second
# stages and all downstream seven-segment logic remain fully timed.
set_false_path -to [get_regs {error_code_clk_ff1[*] image_count_clk_ff1[*] event_state_clk_ff1[*] hmi_sent_units_clk_ff1[*] hmi_sent_tens_clk_ff1[*]}]
