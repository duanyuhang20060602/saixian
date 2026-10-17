// Four scene effects. All external reads remain sequential; geometry accesses
// only the on-chip row caches. Coordinates are 1280x720 screen pixels, packed
// into native two-pixel words on the module boundary.
module water_base_effect_map(input clk,rst,valid,enabled,right,input[2:0] effect,
 input[8:0] progress,input[9:0] ox,oy,wx,wy,
 output reg out_valid,output reg[9:0] old_x,old_y,new_x,out_x,out_y,
 output reg[8:0] alpha,output reg[4:0] shade,output reg[2:0] shine,
 input signed[33:0] shared_product,input[8:0] shared_t,shared_scale,input signed[17:0] shared_bend);
reg[13:0] roll_curve[0:31];
initial $readmemh("water_roll.hex",roll_curve);
wire[10:0] px={ox,1'b0};
wire[10:0] u=right ? 11'd1279-px:px;
wire signed[12:0] centered=$signed({2'd0,px})-13'sd640;
wire[8:0] t=shared_t,flip_scale=shared_scale;
wire[10:0] half_width=({2'd0,flip_scale}<<1)+(flip_scale>>1);
wire[10:0] absolute_x=centered<0 ? -centered:centered;
// Classification and the small wave product are shared with extra effects.
reg signed[33:0] product;
reg signed[17:0] bend_product;
reg[9:0] x0,y0,wx0,wy0;reg[10:0] u0,half0,abs0;reg[8:0] p0,t0,s0;
reg e0,r0,v0;reg[2:0] fx0;
always @(posedge clk)begin
 product<=shared_product;x0<=ox;y0<=oy;wx0<=wx;wy0<=wy;u0<=u;
 bend_product<=shared_bend;
 half0<=half_width;abs0<=absolute_x;p0<=progress;t0<=t;s0<=flip_scale;
 e0<=enabled;r0<=right;fx0<=effect;v0<=valid&&!rst;
end
function[9:0] word_clip;input signed[14:0] x;begin word_clip=x<0 ? 0:x>1278 ? 639:x[10:1];end endfunction
function[8:0] soft_weight;input signed[14:0] n;begin soft_weight=n<=0 ? 0:n>=256 ? 256:n[8:0];end endfunction
reg signed[14:0] a,b,front,distance,travel,ease,projection;
reg[8:0] mix;reg[4:0] darkness;reg[2:0] glint;reg[13:0] curve;
always @*begin
 a=$signed({4'd0,x0,1'b0});b=a;mix=p0;darkness=0;glint=0;
 front=0;distance=0;travel=0;ease=0;projection=0;curve=0;
 if(e0)case(fx0)
  0:begin // A reflected curl with a rounded highlight and a cast shadow.
   front=($signed({6'd0,p0})<<<2)+($signed({6'd0,p0})<<<1)-15'sd128;
   distance=$signed({4'd0,u0})-front;
   mix=soft_weight(15'sd128-(distance<<<3));
   if(distance>=0&&distance<128)begin
    curve=roll_curve[distance[6:2]];a=front+$signed({7'd0,curve[7:0]});
    darkness=curve[12:8];glint={2'd0,curve[13]};
   end else a=$signed({4'd0,u0});
   if(r0)a=15'sd1279-a;
  end
  1:begin // Orthographic 3D card: projected texture, edge and specular light.
   if(abs0<=half0&&s0>=16)begin
    projection=product>>>10;a=15'sd640+projection;b=a;
    mix=p0<112 ? 0:p0>=144 ? 256:{p0[4:0],4'd0};
    // In the centre interval p0-112, not the low five bits of p0.
    if(p0>=112&&p0<144)mix=(p0-9'd112)<<3;
    darkness=(9'd256-s0)>>4;
    if(half0-abs0<8)glint=3;
   end else begin darkness=28;mix=p0;end
  end
  2:begin // Eight broad ribbons weave and travel on an eased trajectory.
   ease=($signed({6'd0,t0})<<<1)-(product>>>8);
   travel=(ease<<<2)+ease+(bend_product>>>7);front=15'sd1280-travel;
   distance=$signed({4'd0,u0})-front;
   mix=soft_weight(15'sd128+(distance<<<3));
   a=$signed({4'd0,u0})+travel;b=a-15'sd1280;
   if(r0)begin a=15'sd1279-a;b=15'sd1279-b;end
   if(t0>0&&t0<256)begin
    darkness=2;if(distance>-12&&distance<12)glint=2;
   end
  end
  default:begin a=$signed({4'd0,wx0,1'b0});mix=p0;end
 endcase
 if(!e0||p0==0||p0==256)begin
  a=$signed({4'd0,wx0,1'b0});b=$signed({4'd0,x0,1'b0});
  if(!e0)mix=0;else mix=p0;
  darkness=0;glint=0;
 end
end
always @(posedge clk)begin
 out_valid<=v0&&!rst;old_x<=word_clip(a);old_y<=e0&&fx0!=6 ? y0:wy0;
 new_x<=word_clip(b);out_x<=x0;out_y<=y0;alpha<=mix;shade<=darkness;shine<=glint;
end
endmodule

// Per-block lighting using shift/add products, so highlights/shadows do not
// allocate six more DSP multipliers. Lighting is applied only to effect pixels.
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
