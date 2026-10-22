`ifndef WATER_SIM
`ifndef FX11_NATIVE_DSP
`define FX11_NATIVE_DSP
`endif
`endif
`ifdef FX11_DSP_SIM
`ifndef FX11_NATIVE_DSP
`define FX11_NATIVE_DSP
`endif
`endif
module water_effect_light(input[31:0] rgb,input[4:0] shade,input[2:0] shine,output[31:0] lit);
function[5:0] channel;input[5:0] c;input wide;input[4:0] s;input[2:0] h;
 // 0<=shade<=31 and 0<=c<=63 imply c-floor(c*shade/32)>=0.
 // With highlight the exact result stays in 0..119; seven unsigned bits suffice.
 reg[11:0] loss;reg[6:0] result;begin
 loss=(s[0] ? {6'd0,c}:12'd0)+(s[1] ? {5'd0,c,1'b0}:12'd0)+(s[2] ? {4'd0,c,2'd0}:12'd0)+
      (s[3] ? {3'd0,c,3'd0}:12'd0)+(s[4] ? {2'd0,c,4'd0}:12'd0);
 result={1'b0,c}-loss[11:5]+(wide ? {1'b0,h,3'd0}:{2'd0,h,2'd0});
 channel=result>(wide ? 63:31) ? (wide ? 63:31):result[5:0];end endfunction
genvar i;generate for(i=0;i<2;i=i+1)begin:p
 wire[5:0] r,g,b;
 water_light_channel lr({1'b0,rgb[i*16+11+:5]},1'b0,shade,shine,r);
 water_light_channel lg(rgb[i*16+5+:6],1'b1,shade,shine,g);
 water_light_channel lb({1'b0,rgb[i*16+:5]},1'b0,shade,shine,b);
 assign lit[i*16+:16]={r[4:0],g,b[4:0]};
end endgenerate
endmodule


// Exact two-slot lighting: one RGB arithmetic unit serves both packed pixels.
module water_surface_light(input clk,rst,valid,input[31:0] rgb,
 input[4:0] shade,input[2:0] shine,output reg out_valid,output reg[31:0] lit);
reg pending;reg[15:0] lower,upper;reg[4:0] saved_shade;reg[2:0] saved_shine;
wire[15:0] pixel=valid ? rgb[31:16]:lower;
wire[31:0] calculated;
water_effect_light scalar(.rgb({pixel,pixel}),.shade(valid ? shade:saved_shade),
 .shine(valid ? shine:saved_shine),.lit(calculated));
always @(posedge clk)begin
 pending<=valid&&!rst;out_valid<=pending&&!rst;
 if(valid)begin upper<=calculated[31:16];lower<=rgb[15:0];saved_shade<=shade;saved_shine<=shine;end
 if(pending)lit<={upper,calculated[15:0]};
 if(rst)begin pending<=0;out_valid<=0;end
end
endmodule

// Identical bounded colour arithmetic; use spare DSPs for c*shade.
module water_light_channel(input[5:0] c,input wide,input[4:0] shade,input[2:0] shine,output[5:0] value);
wire[35:0] loss;
`ifdef FX11_NATIVE_DSP
EG_PHY_MULT18 #(.INPUTREGA("DISABLE"),.INPUTREGB("DISABLE"),.OUTPUTREG("DISABLE")) multiply(
 .a({12'd0,c}),.b({13'd0,shade}),.p(loss),.signeda(1'b0),.signedb(1'b0),
 .acin(18'd0),.bcin(18'd0),.sourcea(1'b1),.sourceb(1'b1),.acout(),.bcout(),
 .cea(1'b1),.ceb(1'b1),.cepd(1'b1),.clk(1'b0),.rstan(1'b1),.rstbn(1'b1),.rstpdn(1'b1));
`else
assign loss=c*shade;
`endif
wire[6:0] result={1'b0,c}-loss[11:5]+(wide ? {1'b0,shine,3'd0}:{2'd0,shine,2'd0});
assign value=result>(wide ? 63:31) ? (wide ? 63:31):result[5:0];
endmodule
