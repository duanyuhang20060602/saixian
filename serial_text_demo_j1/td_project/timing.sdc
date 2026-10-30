create_clock -name clk -period 20.000 [get_ports {clk}]
derive_clocks
set_false_path -to [get_regs -nowarn {uart/m}]
set_false_path -from [get_regs -nowarn {reset_video/sync_ff*}] -to [get_pins -nowarn {*.sr}]
