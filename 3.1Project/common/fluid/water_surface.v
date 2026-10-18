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
 wire[5:0] r=channel({1'b0,rgb[i*16+11+:5]},0,shade,shine);
 wire[5:0] g=channel(rgb[i*16+5+:6],1,shade,shine);
 wire[5:0] b=channel({1'b0,rgb[i*16+:5]},0,shade,shine);
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
