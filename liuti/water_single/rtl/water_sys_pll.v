// Board adapter derived from pinned vendor PLL configurations.
// Internal VCO feedback; fbclk is unused and tied low, never locally routed.
`timescale 1 ns / 100 fs

module water_sys_pll (
  refclk,
  reset,
  clk0_out,
  clk1_out,
  clk2_out,
  locked
);

  input refclk;
  input reset;
  output clk0_out;
  output clk1_out;
  output clk2_out;
  output locked;

  wire clk0_buf;wire clk1_buf,clk2_buf;
  EG_LOGIC_BUFG bufg_mem(.i(clk1_buf),.o(clk1_out));
  EG_LOGIC_BUFG bufg_mem_shift(.i(clk2_buf),.o(clk2_out));

  EG_LOGIC_BUFG bufg_feedback (
    .i(clk0_buf),
    .o(clk0_out) 
  );

  EG_PHY_PLL #(
    .DPHASE_SOURCE("DISABLE"),
    .DYNCFG("DISABLE"),
    .FIN("50.000000"),
    .FEEDBK_MODE("NOCOMP"),
    .FEEDBK_PATH("VCO_PHASE_0"),
    .STDBY_ENABLE("DISABLE"),
    .PLLRST_ENA("ENABLE"),
    .SYNC_ENABLE("DISABLE"),
    .GMC_GAIN(4),
    .ICP_CURRENT(29),
    .KVCO(4),
    .LPF_CAPACITOR(1),
    .LPF_RESISTOR(2),
    .REFCLK_DIV(1),
    .FBCLK_DIV(20),
    .CLKC0_ENABLE("ENABLE"),
    .CLKC0_DIV(20),
    .CLKC0_CPHASE(19),
    .CLKC0_FPHASE(0),
    .CLKC1_ENABLE("ENABLE"),
    .CLKC1_DIV(20),
    .CLKC1_CPHASE(19),
    .CLKC1_FPHASE(0),
    .CLKC2_ENABLE("ENABLE"),
    .CLKC2_DIV(20),
    .CLKC2_CPHASE(7),
    .CLKC2_FPHASE(0) 
  ) pll_inst (
    .refclk(refclk),
    .reset(reset),
    .stdby(1'b0),
    .extlock(locked),
    .load_reg(1'b0),
    .psclk(1'b0),
    .psdown(1'b0),
    .psstep(1'b0),
    .psclksel(3'b000),
    .psdone(open),
    .dclk(1'b0),
    .dcs(1'b0),
    .dwe(1'b0),
    .di(8'b00000000),
    .daddr(6'b000000),
    .do({open, open, open, open, open, open, open, open}),
    .fbclk(1'b0),
    .clkc({open, open, clk2_buf, clk1_buf, clk0_buf}) 
  );

endmodule


`timescale 1 ns / 100 fs


