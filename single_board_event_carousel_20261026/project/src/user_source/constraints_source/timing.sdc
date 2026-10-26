create_clock -name clk -period 20.000 -waveform {0.000 10.000} [get_ports {clk}]
derive_clocks
rename_clock -name {video_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_video_pll/pll_inst.clkc[0]}]
rename_clock -name {hdmi_5x_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_video_pll/pll_inst.clkc[1]}]
# Buttons and HPD are sampled through explicit two-register synchronizers.
set_false_path -from [get_ports {key[*] hdmi_hpd}]
# This counter only asserts resets; each reset releases through three local
# flip-flops. Ordinary video-to-serializer data paths remain fully timed.
set_false_path -from [get_regs {por_count[18]}] -to [get_clocks {video_clk hdmi_5x_clk}]
