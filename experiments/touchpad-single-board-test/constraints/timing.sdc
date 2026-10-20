create_clock -name clk -period 20.000 -waveform {0.000 10.000} [get_ports {clk}]
derive_clocks
rename_clock -name {board_pixel_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_video_pll/pll_inst.clkc[0]}]
rename_clock -name {hdmi_5x_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_video_pll/pll_inst.clkc[1]}]
# External UART is asynchronous; its receiver retains two synchronization flops.
set_false_path -from [get_ports {hmi_uart_rx}]
# Pixel/5x clocks are derived from the same PLL and remain timed.
