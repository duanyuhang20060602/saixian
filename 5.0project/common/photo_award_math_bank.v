// The foil shader needs these multipliers only for nonzero opacity.
// A trophy's first valid table arrives after the disabled foil pipeline drains.
// Keep one-clock product latency for both clients, with no new clock or FIFO.
module photo_award_math_bank(input clk,rst,blend_request,
 input signed [8:0] blend_r,blend_g,input [3:0] alpha,
 input signed [5:0] normal_x,normal_y,light_x,light_y,
 output signed [14:0] product_x,product_y);
wire signed [8:0] a=blend_request ? blend_r:{{3{normal_x[5]}},normal_x};
wire signed [8:0] c=blend_request ? blend_g:{{3{normal_y[5]}},normal_y};
wire signed [5:0] b=blend_request ? $signed({2'b00,alpha}):light_x;
wire signed [5:0] d=blend_request ? $signed({2'b00,alpha}):light_y;
photo_award_shared_product x(.clk(clk),.rst(rst),.a(a),.b(b),.p(product_x));
photo_award_shared_product y(.clk(clk),.rst(rst),.a(c),.b(d),.p(product_y));
endmodule

module photo_award_shared_product(input clk,rst,input signed [8:0] a,input signed [5:0] b,
 output signed [14:0] p);
`ifdef SHARED_DSP_NATIVE
 localparam NATIVE=1;
`elsif WATER_SIM
 localparam NATIVE=0;
`elsif RELIEF_SIM
 localparam NATIVE=0;
`else
 localparam NATIVE=1;
`endif
generate if(NATIVE)begin:native
 wire [35:0] wide;
 EG_PHY_MULT18 #(.INPUTREGA("DISABLE"),.INPUTREGB("DISABLE"),
  .OUTPUTREG("ENABLE"),.SRMODE("SYNC")) multiply(
  .a({{9{a[8]}},a}),.b({{12{b[5]}},b}),.p(wide),.signeda(1'b1),.signedb(1'b1),
  .acin(18'd0),.bcin(18'd0),.sourcea(1'b1),.sourceb(1'b1),.acout(),.bcout(),
  .cea(1'b1),.ceb(1'b1),.cepd(1'b1),.clk(clk),.rstan(1'b1),.rstbn(1'b1),.rstpdn(!rst));
 assign p=wide[14:0];
end else begin:simulation
 reg signed [14:0] product;
 always @(posedge clk)if(rst)product<=0;else product<=a*b;
 assign p=product;
end endgenerate
endmodule
