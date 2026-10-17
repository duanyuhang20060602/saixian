create_clock -name clk -period 20.000 [get_ports {clk}]
derive_clocks
rename_clock -name sd_clk -source [get_ports {clk}] -master_clock clk [get_pins {sys/pll_inst.clkc[0]}]
rename_clock -name pixel_clk -source [get_ports {clk}] -master_clock clk [get_pins {video/pll_inst.clkc[0]}]
rename_clock -name serial_clk -source [get_ports {clk}] -master_clock clk [get_pins {video/pll_inst.clkc[1]}]
# Mechanical keys and HPD enter explicit two-stage synchronizers.
set_false_path -from [get_ports {key[*] sw[*] hdmi_hpd}]

# Payload crosses only the official asynchronous FIFOs; configuration is
# stable through a two-flop request/acknowledgement transaction.
rename_clock -name mem_clk -source [get_ports {clk}] -master_clock clk [get_pins {sys/pll_inst.clkc[1]}]
rename_clock -name mem_shift -source [get_ports {clk}] -master_clock clk [get_pins {sys/pll_inst.clkc[2]}]
set_clock_groups -asynchronous -group [get_clocks {sd_clk mem_clk mem_shift}] -group [get_clocks {pixel_clk serial_clk}]
# Asynchronous reset assertion only; retain local synchronous D paths.
set_false_path -from [get_pins {sys/pll_inst.extlock video/pll_inst.extlock}] -to [get_regs {*sync_ff*}]
# Mode 3, divider zero: DCLK changes once every TWO 50MHz clocks;
# MISO is sampled on the rising DCLK, TWO sys_clk edges after launch on
# falling DCLK. This exception applies only to the external MISO input.
# 12ns = 4ns output-clock pad/PCB allowance + 8ns card/return allowance.
# These external budgets still require verification with the actual TF card.
set_input_delay -clock sd_clk -max 12.000 [get_ports {sd_miso}]
set_input_delay -clock sd_clk -min 0.000 [get_ports {sd_miso}]
set_multicycle_path -setup -from [get_ports {sd_miso}] 2
set_multicycle_path -hold -from [get_ports {sd_miso}] 1
set_output_delay -clock sd_clk -max 2.000 [get_ports {sd_ncs sd_dclk sd_mosi}]
set_output_delay -clock sd_clk -min 0.000 [get_ports {sd_ncs sd_dclk sd_mosi}]
# Quasi-static DDC and diagnostic LEDs are not synchronous interfaces.
set_false_path -from [get_ports {HDMI_DDC_SDA}]
set_false_path -to [get_ports {HDMI_DDC_SDA HDMI_DDC_SCL seg_sel[*] seg_data[*] led[*]}]
