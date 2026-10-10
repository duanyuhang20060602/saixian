`timescale 1ns/1ps
// 1366x768 exact 60 Hz clock generation from a 50 MHz board oscillator.
// Stage 1: PFD=25 MHz, VCO=675 MHz, output=135 MHz.
// Stage 2: PFD=45 MHz, VCO=720 MHz, outputs=72/360 MHz.
// Both stages use VCO feedback: output divider is outside the PLL loop.
module video_pll(input wire refclk,input wire reset,
 output wire clk0_out,output wire clk1_out,output wire locked);
 reg [7:0] startup_count=8'd0;
 always @(posedge refclk or posedge reset)
  if(reset) startup_count<=8'd0;
  else if(!(&startup_count)) startup_count<=startup_count+1'b1;
 wire [3:0] pre_unused;
 wire [2:0] video_unused;
 wire pre_clk_raw,pre_clk,pre_locked,pixel_raw,serial_raw,video_locked;
 wire pre_reset=reset || !(&startup_count);
 wire video_reset=pre_reset || !pre_locked;
 EG_LOGIC_BUFG pre_buf(.i(pre_clk_raw),.o(pre_clk));
 EG_LOGIC_BUFG pixel_buf(.i(pixel_raw),.o(clk0_out));
 assign clk1_out=serial_raw;
 assign locked=pre_locked && video_locked;
 EG_PHY_PLL #(
 .DPHASE_SOURCE("DISABLE"),.DYNCFG("DISABLE"),.FIN("50.000000"),
 .FEEDBK_MODE("NOCOMP"),.FEEDBK_PATH("VCO_PHASE_0"),
 .STDBY_ENABLE("DISABLE"),.PLLRST_ENA("ENABLE"),.SYNC_ENABLE("DISABLE"),
 .GMC_GAIN(2),.ICP_CURRENT(9),.KVCO(2),.LPF_CAPACITOR(1),.LPF_RESISTOR(8),
 .REFCLK_DIV(2),.FBCLK_DIV(27),
 .CLKC0_ENABLE("ENABLE"),.CLKC0_DIV(5),.CLKC0_CPHASE(4),.CLKC0_FPHASE(0)
 ) pre_pll_inst(.refclk(refclk),.reset(pre_reset),.stdby(1'b0),
 .extlock(pre_locked),.load_reg(5'b00000),.psclk(1'b0),.psdown(1'b0),
 .psstep(1'b0),.psclksel(3'b000),.psdone(),.dclk(1'b0),.dcs(1'b0),
 .dwe(1'b0),.di(8'd0),.daddr(6'd0),.do(),.fbclk(1'b0),
 .clkc({pre_unused,pre_clk_raw}));
 EG_PHY_PLL #(
 .DPHASE_SOURCE("DISABLE"),.DYNCFG("DISABLE"),.FIN("135.000000"),
 .FEEDBK_MODE("NOCOMP"),.FEEDBK_PATH("VCO_PHASE_0"),
 .STDBY_ENABLE("DISABLE"),.PLLRST_ENA("ENABLE"),.SYNC_ENABLE("DISABLE"),
 .GMC_GAIN(2),.ICP_CURRENT(9),.KVCO(2),.LPF_CAPACITOR(1),.LPF_RESISTOR(8),
 .REFCLK_DIV(3),.FBCLK_DIV(16),
 .CLKC0_ENABLE("ENABLE"),.CLKC0_DIV(10),.CLKC0_CPHASE(9),.CLKC0_FPHASE(0),
 .CLKC1_ENABLE("ENABLE"),.CLKC1_DIV(2),.CLKC1_CPHASE(1),.CLKC1_FPHASE(0)
 ) pll_inst(.refclk(pre_clk),.reset(video_reset),.stdby(1'b0),
 .extlock(video_locked),.load_reg(5'b00000),.psclk(1'b0),.psdown(1'b0),
 .psstep(1'b0),.psclksel(3'b000),.psdone(),.dclk(1'b0),.dcs(1'b0),
 .dwe(1'b0),.di(8'd0),.daddr(6'd0),.do(),.fbclk(1'b0),
 .clkc({video_unused,serial_raw,pixel_raw}));
endmodule
