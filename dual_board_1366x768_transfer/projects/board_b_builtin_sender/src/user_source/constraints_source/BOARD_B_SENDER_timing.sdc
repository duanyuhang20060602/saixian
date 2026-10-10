create_clock -name clk -period 20.000 -waveform {0.000 10.000} [get_ports {clk}]
derive_clocks
rename_clock -name {link_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_link_pll/pll_inst.clkc[0]}]
set_output_delay -clock {link_clk} -clock_fall -max 2.000 [get_ports {link_data[*] link_valid link_sof link_eof}]
set_output_delay -clock {link_clk} -clock_fall -min 0.000 [get_ports {link_data[*] link_valid link_sof link_eof}]
set_input_delay -clock {link_clk} -max 2.000 [get_ports {link_ready}]
set_input_delay -clock {link_clk} -min 0.500 [get_ports {link_ready}]
set_false_path -from [get_ports {image_ack}]
