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
 wire[4:0] r,b;wire[5:0] g;
 water_light_pair_channel rb(rgb[i*16+11+:5],rgb[i*16+:5],shade,shine,r,b);
 water_light_channel lg(rgb[i*16+5+:6],1'b1,shade,shine,g);
 assign lit[i*16+:16]={r,g,b};
end endgenerate
endmodule


// Exact two-slot lighting: one RGB arithmetic unit serves both packed pixels.
module water_surface_light(input clk,rst,valid,input[31:0] rgb,
 input[4:0] shade,input[2:0] shine,output reg out_valid,output reg[31:0] lit,input color_mode);
reg pending;reg[15:0] lower,upper;reg[4:0] saved_shade;reg[2:0] saved_shine;
wire[15:0] pixel=valid ? rgb[31:16]:lower;
wire[31:0] calculated;
water_color_light scalar(.color_mode(color_mode),.rgb({pixel,pixel}),.shade(valid ? shade:saved_shade),
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

// Two 5x5 shade products fit one 18x18 DSP. Each product is at most
// 31*31=961 (<2^10), so the ten-bit separator prevents channel cross-carry.
// Outputs, saturation, and combinational latency match two original channels.
module water_light_pair_channel(input[4:0] r,b,shade,input[2:0] shine,
 output[4:0] red,blue);
wire[35:0] loss;
`ifdef FX11_NATIVE_DSP
EG_PHY_MULT18 #(.INPUTREGA("DISABLE"),.INPUTREGB("DISABLE"),.OUTPUTREG("DISABLE")) multiply(
 .a({3'd0,r,5'd0,b}),.b({13'd0,shade}),.p(loss),.signeda(1'b0),.signedb(1'b0),
 .acin(18'd0),.bcin(18'd0),.sourcea(1'b1),.sourceb(1'b1),.acout(),.bcout(),
 .cea(1'b1),.ceb(1'b1),.cepd(1'b1),.clk(1'b0),.rstan(1'b1),.rstbn(1'b1),.rstpdn(1'b1));
`else
assign loss={3'd0,r,5'd0,b}*shade;
`endif
wire[6:0] rr={2'd0,r}-{2'd0,loss[19:15]}+{2'd0,shine,2'd0};
wire[6:0] bb={2'd0,b}-{2'd0,loss[9:5]}+{2'd0,shine,2'd0};
assign red=rr>31 ? 5'd31:rr[4:0];
assign blue=bb>31 ? 5'd31:bb[4:0];
endmodule

module water_color_light(input[31:0] rgb,input[4:0] shade,input[2:0] shine,
 output[31:0] lit,input color_mode);
function[6:0] dodge;input[4:0] s;begin case(s)
 0:dodge=7'd32;
 1:dodge=7'd33;
 2:dodge=7'd34;
 3:dodge=7'd34;
 4:dodge=7'd35;
 5:dodge=7'd36;
 6:dodge=7'd37;
 7:dodge=7'd38;
 8:dodge=7'd39;
 9:dodge=7'd41;
 10:dodge=7'd42;
 11:dodge=7'd43;
 12:dodge=7'd45;
 13:dodge=7'd46;
 14:dodge=7'd48;
 15:dodge=7'd49;
 16:dodge=7'd51;
 17:dodge=7'd53;
 18:dodge=7'd56;
 19:dodge=7'd58;
 20:dodge=7'd60;
 21:dodge=7'd63;
 22:dodge=7'd66;
 23:dodge=7'd70;
 24:dodge=7'd74;
 25:dodge=7'd78;
 26:dodge=7'd83;
 27:dodge=7'd88;
 28:dodge=7'd94;
 29:dodge=7'd101;
 30:dodge=7'd109;
 31:dodge=7'd119;
 endcase end endfunction
wire[6:0] coefficient=color_mode ? dodge(shade):7'd32-{2'd0,shade};
wire[4:0] r=rgb[31:27],b=rgb[20:16];wire[5:0] g=rgb[26:21];
wire[35:0] rbprod,gprod;
`ifdef FX11_NATIVE_DSP
EG_PHY_MULT18 #(.INPUTREGA("DISABLE"),.INPUTREGB("DISABLE"),.OUTPUTREG("DISABLE")) rb(
 .a({1'b0,r,7'd0,b}),.b({11'd0,coefficient}),.p(rbprod),.signeda(1'b0),.signedb(1'b0),
 .acin(18'd0),.bcin(18'd0),.sourcea(1'b1),.sourceb(1'b1),.acout(),.bcout(),
 .cea(1'b1),.ceb(1'b1),.cepd(1'b1),.clk(1'b0),.rstan(1'b1),.rstbn(1'b1),.rstpdn(1'b1));
EG_PHY_MULT18 #(.INPUTREGA("DISABLE"),.INPUTREGB("DISABLE"),.OUTPUTREG("DISABLE")) green(
 .a({12'd0,g}),.b({11'd0,coefficient}),.p(gprod),.signeda(1'b0),.signedb(1'b0),
 .acin(18'd0),.bcin(18'd0),.sourcea(1'b1),.sourceb(1'b1),.acout(),.bcout(),
 .cea(1'b1),.ceb(1'b1),.cepd(1'b1),.clk(1'b0),.rstan(1'b1),.rstbn(1'b1),.rstpdn(1'b1));
`else
assign rbprod={1'b0,r,7'd0,b}*coefficient;
assign gprod=g*coefficient;
`endif
wire[4:0] bias=color_mode ? 5'd16:5'd31;
wire[12:0] rounded_r={1'b0,rbprod[23:12]}+{8'd0,bias};
wire[12:0] rounded_b={1'b0,rbprod[11:0]}+{8'd0,bias};
wire[13:0] rounded_g={1'b0,gprod[12:0]}+{9'd0,bias};
// ceil(c*(32-s)/32) == c-floor(c*s/32), including shade zero.
wire[8:0] red={1'b0,rounded_r[12:5]}+(color_mode ? 9'd0:{4'd0,shine,2'd0});
wire[8:0] blue={1'b0,rounded_b[12:5]}+(color_mode ? 9'd0:{4'd0,shine,2'd0});
wire[8:0] grn=rounded_g[13:5]+(color_mode ? 9'd0:{3'd0,shine,3'd0});
wire[15:0] value={red>31 ? 5'd31:red[4:0],grn>63 ? 6'd63:grn[5:0],blue>31 ? 5'd31:blue[4:0]};
assign lit={value,value};
endmodule

// Spatial RGB separation after mixing, at the reader's two-clock cadence.
// Sixteen pairs in small LUT RAM provide seven texels of lookahead/history.
// Green stays at the nominal position. Red and blue sample opposite sides.
module water_color_fringe(input clk,rst,enabled,valid,last,input[2:0] amount,
 input[31:0] rgb,output out_valid,out_last,output[31:0] pixels);
reg[8:0] written,position;reg sealed,gap,ov,ol;reg[31:0] pixel_q;
wire[2:0] ca;wire[11:0] green;
wire push=enabled&&valid&&!rst;
wire emit=enabled&&!gap&&(written>position+9'd4||(sealed&&position<written));
function[8:0] clamp_pair;input signed[10:0] v;begin clamp_pair=v<0 ? 0:v>319 ? 319:v[8:0];end endfunction
// Two-texel steps match the row-cache word granularity, avoiding four
// independently addressed parity lanes. Maximum separation is 12 screen pixels.
wire signed[10:0] shift=position<160 ? $signed({9'd0,ca[2:1]}):-$signed({9'd0,ca[2:1]});
wire[8:0] ri=clamp_pair($signed({2'd0,position})+shift);
wire[8:0] bi=clamp_pair($signed({2'd0,position})-shift);
wire[9:0] red_pair,blue_pair;
water_color_lutram #(10) reds(clk,push,written[3:0],{rgb[31:27],rgb[15:11]},ri[3:0],red_pair);
water_color_lutram #(10) blues(clk,push,written[3:0],{rgb[20:16],rgb[4:0]},bi[3:0],blue_pair);
water_color_lutram #(12) greens(clk,push,written[3:0],{rgb[26:21],rgb[10:5]},position[3:0],green);
water_color_lutram #(3) amounts(clk,push,written[3:0],amount,position[3:0],ca);
wire[4:0] red0=red_pair[9:5],red1=red_pair[4:0];
wire[4:0] blue0=blue_pair[9:5],blue1=blue_pair[4:0];
always @(posedge clk)begin
 ov<=emit&&!rst;ol<=emit&&position==319;
 gap<=emit;
 if(push)begin written<=written+1'b1;if(last)sealed<=1;end
 if(emit)begin
  pixel_q<={red0,green[11:6],blue0,red1,green[5:0],blue1};
  position<=position+1'b1;
  if(position==319)begin written<=0;position<=0;sealed<=0;end
 end
 if(rst||!enabled)begin written<=0;position<=0;sealed<=0;gap<=0;ov<=0;ol<=0;end
end
assign out_valid=enabled ? ov:valid;
assign out_last=enabled ? ol:last;
assign pixels=enabled ? pixel_q:rgb;
`ifdef WATER_SIM
always @(posedge clk)if(!rst&&enabled)begin
 if(push&&sealed)$fatal(1,"chroma row overlap");
 if(written-position>15)$fatal(1,"chroma window overflow");
 if(emit&&!sealed&&written<=position+4)$fatal(1,"chroma lookahead underrun");
end
`endif
endmodule
