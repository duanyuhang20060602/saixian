// RGB565 pair interpolation, alpha 0..256. SDRAM returns two reads per
// blended word, so valid is separated by at least one clock. Use that clock
// for the second pixel, reusing three channel multipliers without throttling
// the reader. Output latency is four edges including the accepting edge.
`ifndef WATER_SIM
`define WATER_BLEND_DSP
`endif
`ifdef BLEND_DSP_SIM
`define WATER_BLEND_DSP
`endif
module water_blend(input clk,rst,valid,input[31:0] old_word,new_word,input[8:0] alpha,
 output reg out_valid,output reg[31:0] word_out);
// Use spare FPGA multipliers for the exact signed RGB565 differences.
// Arithmetic simulation and native hardware share the same 17-bit result.
function signed[16:0] alpha_product;
 input signed[6:0] d;input[8:0] w;
 begin alpha_product=d*$signed({1'b0,w});end
endfunction
reg pending;reg[15:0] old_low,new_low;reg[8:0] alpha_low;
wire[15:0] a=valid ? old_word[31:16]:old_low;
wire[15:0] b=valid ? new_word[31:16]:new_low;
wire[8:0] selected_alpha=valid ? alpha:alpha_low;
wire[5:0] ac[0:2],bc[0:2];
assign ac[0]={1'b0,a[15:11]};assign ac[1]=a[10:5];assign ac[2]={1'b0,a[4:0]};
assign bc[0]={1'b0,b[15:11]};assign bc[1]=b[10:5];assign bc[2]={1'b0,b[4:0]};
reg v0,v1,low0,low1;reg[8:0] aq;reg[15:0] upper;
wire signed[17:0] sum[0:2];genvar g;generate for(g=0;g<3;g=g+1)begin:s
 // Scalar registers prevent tiny channel arrays becoming dedicated BRAMs.
 reg signed[6:0] diff;reg[5:0] old,old2;
 wire signed[16:0] prod;
`ifdef WATER_BLEND_DSP
 wire[35:0] dsp_product;
 EG_PHY_MULT18 #(.INPUTREGA("DISABLE"),.INPUTREGB("DISABLE"),.OUTPUTREG("ENABLE")) multiply(
  .a({{11{diff[6]}},diff}),.b({9'd0,aq}),.p(dsp_product),.signeda(1'b1),.signedb(1'b0),
  .acin(18'd0),.bcin(18'd0),.sourcea(1'b1),.sourceb(1'b1),.acout(),.bcout(),
  .cea(1'b1),.ceb(1'b1),.cepd(1'b1),.clk(clk),.rstan(1'b1),.rstbn(1'b1),.rstpdn(1'b1));
 assign prod=dsp_product[16:0];
`else
 reg signed[16:0] sim_product;
 always @(posedge clk)sim_product<=alpha_product(diff,aq);
 assign prod=sim_product;
`endif
 always @(posedge clk)begin
  old<=ac[g];diff<=$signed({1'b0,bc[g]})-$signed({1'b0,ac[g]});
  old2<=old;
 end
 assign sum[g]=$signed({4'd0,old2,8'd0})+$signed(prod)+18'sd128;
end endgenerate
always @(posedge clk)begin
 pending<=valid&&!rst;
 if(valid)begin old_low<=old_word[15:0];new_low<=new_word[15:0];alpha_low<=alpha;end
 aq<=selected_alpha;v0<=(valid||pending)&&!rst;low0<=!valid;
 v1<=v0&&!rst;low1<=low0;out_valid<=v1&&low1&&!rst;
 if(v1&&!low1)upper<={sum[0][12:8],sum[1][13:8],sum[2][12:8]};
 if(v1&&low1)word_out<={upper,sum[0][12:8],sum[1][13:8],sum[2][12:8]};
end
endmodule
