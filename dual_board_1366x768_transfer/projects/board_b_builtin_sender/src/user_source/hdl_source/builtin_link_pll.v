`timescale 1ns/1ps
module builtin_link_pll(input wire refclk,input wire reset,
 output wire clk0_out,output wire locked);
wire clk0_buf; wire [3:0] unused_clocks;
EG_LOGIC_BUFG bufg_feedback(.i(clk0_buf),.o(clk0_out));
EG_PHY_PLL #(
 .DPHASE_SOURCE("DISABLE"),.DYNCFG("DISABLE"),.FIN("50.000000"),
 .FEEDBK_MODE("NORMAL"),.FEEDBK_PATH("CLKC0_EXT"),
 .STDBY_ENABLE("DISABLE"),.PLLRST_ENA("ENABLE"),.SYNC_ENABLE("DISABLE"),
 .GMC_GAIN(2),.ICP_CURRENT(9),.KVCO(2),.LPF_CAPACITOR(1),.LPF_RESISTOR(8),
 .REFCLK_DIV(4),.FBCLK_DIV(1),.CLKC0_ENABLE("ENABLE"),
 .CLKC0_DIV(40),.CLKC0_CPHASE(39),.CLKC0_FPHASE(0),
 .CLKC1_ENABLE("DISABLE"),.CLKC1_DIV(2),.CLKC1_CPHASE(1),.CLKC1_FPHASE(0)
) pll_inst(
 .refclk(refclk),.reset(reset),.stdby(1'b0),.extlock(locked),
 .load_reg(1'b0),.psclk(1'b0),.psdown(1'b0),.psstep(1'b0),.psclksel(3'b000),
 .psdone(),.dclk(1'b0),.dcs(1'b0),.dwe(1'b0),.di(8'd0),.daddr(6'd0),.do(),
 .fbclk(clk0_out),.clkc({unused_clocks,clk0_buf})
);
endmodule
