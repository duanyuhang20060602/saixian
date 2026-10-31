`timescale 1ns/1ps
// Logical 640x360 canvas, doubled to HDMI 1280x720. Three registered
// stages carry RGB, DE and VS together; state is committed only at blanking.
module match_render(input clk,rst,frame_tick,de,vs,input [10:0] x,input [9:0] y,
 input [2:0] state,team_a,team_b,input [9:0] score_a,score_b,
 input [8:0] remaining,input [1:0] countdown,duration_index,
 output reg [23:0] rgb,output reg out_de,out_vs);
reg [2:0] fs,fa,fb;reg [9:0] sa,sb;reg [8:0] sec;
reg [1:0] cd,dur;reg [7:0] animation;
reg [3:0] a0,a1,a2,b0,b1,b2,m0,m1,s0,s1;
always @(posedge clk or posedge rst)begin
 if(rst)begin fs<=0;fa<=0;fb<=1;sa<=0;sb<=0;sec<=30;cd<=0;dur<=0;animation<=0;
  a0<=0;a1<=0;a2<=0;b0<=0;b1<=0;b2<=0;m0<=0;m1<=0;s0<=3;s1<=0;end
 else if(frame_tick)begin
  fs<=state;fa<=team_a;fb<=team_b;sa<=score_a;sb<=score_b;sec<=remaining;cd<=countdown;dur<=duration_index;
  animation<=animation+1'b1;
  a0<=score_a/100;a1<=(score_a/10)%10;a2<=score_a%10;
  b0<=score_b/100;b1<=(score_b/10)%10;b2<=score_b%10;
  m0<=(remaining/60)/10;m1<=(remaining/60)%10;s0<=(remaining%60)/10;s1<=remaining%10;
 end
end
wire [9:0] lx={1'b0,x[10:1]};wire [8:0] ly={1'b0,y[9:1]};
`include "match_text.vh"
function [6:0] segments;input [3:0] n;begin case(n)
 0:segments=7'b1111110;1:segments=7'b0110000;2:segments=7'b1101101;3:segments=7'b1111001;
 4:segments=7'b0110011;5:segments=7'b1011011;6:segments=7'b1011111;7:segments=7'b1110000;
 8:segments=7'b1111111;9:segments=7'b1111011;default:segments=0;endcase end endfunction
function big_digit;input [9:0] px;input [8:0] py;input [3:0] n;input compact_digit;
 reg [6:0] g;reg [9:0] w,h,t;begin
 g=segments(n);w=compact_digit ? 20:32;h=compact_digit ? 40:64;t=compact_digit ? 3:5;
 big_digit=(px<w && py<h) && (
  (g[6] && py<t && px>=t && px<w-t) ||
  (g[5] && px>=w-t && py>=t && py<h/2-t/2) ||
  (g[4] && px>=w-t && py>=h/2+t/2 && py<h-t) ||
  (g[3] && py>=h-t && px>=t && px<w-t) ||
  (g[2] && px<t && py>=h/2+t/2 && py<h-t) ||
  (g[1] && px<t && py>=t && py<h/2-t/2) ||
  (g[0] && py>=h/2-t/2 && py<h/2+t/2 && px>=t && px<w-t));
 end endfunction
reg [23:0] background,ink;reg [6:0] glyph;reg digit_on,cup_on;
reg [9:0] progress;reg [9:0] dx;reg [8:0] dy;
reg [23:0] bg_q,ink_q,bg_d,ink_d;reg de_q,vs_q,de_d,vs_d;
reg [3:0] col_q;wire [15:0] font_bits;
reg [15:0] font[0:2047]; /* fehdl force_ram=1, ram_style="bram" */
initial $readmemh("match_font.hex",font);
reg [15:0] font_q;
assign font_bits=font_q;
always @* begin
 background=24'h091525;ink=24'hE6EEF8;digit_on=0;cup_on=0;dx=0;dy=0;
 glyph=cell_glyph(lx[9:4],ly[8:4]);
 if(ly<56)background=24'h10253B;
 if(ly>=72 && ly<216 && lx>=40 && lx<224)background=24'h281C32;
 if(ly>=72 && ly<216 && lx>=416 && lx<600)background=24'h102C41;
 if((lx>=40 && lx<44 && ly>=72 && ly<216))background=24'hFF6978;
 if((lx>=596 && lx<600 && ly>=72 && ly<216))background=24'h50C9FF;
 if(ly>=144 && ly<208)begin
  dy=ly-144;
  if(lx>=64 && lx<96)digit_on=big_digit(lx-64,dy,a0,0);
  if(lx>=104 && lx<136)digit_on=big_digit(lx-104,dy,a1,0);
  if(lx>=144 && lx<176)digit_on=big_digit(lx-144,dy,a2,0);
  if(lx>=464 && lx<496)digit_on=big_digit(lx-464,dy,b0,0);
  if(lx>=504 && lx<536)digit_on=big_digit(lx-504,dy,b1,0);
  if(lx>=544 && lx<576)digit_on=big_digit(lx-544,dy,b2,0);
  if(digit_on)background=lx<320 ? 24'hFF8291:24'h66D2FF;
 end
 if(fs!=1 && ly>=160 && ly<200 && lx>=248 && lx<368)begin
  dy=ly-160;digit_on=0;
  if(lx<268)digit_on=big_digit(lx-248,dy,m0,1);
  else if(lx>=272 && lx<292)digit_on=big_digit(lx-272,dy,m1,1);
  else if(lx>=320 && lx<340)digit_on=big_digit(lx-320,dy,s0,1);
  else if(lx>=344 && lx<364)digit_on=big_digit(lx-344,dy,s1,1);
  else if(lx>=302 && lx<307 && ((ly>=170 && ly<175)||(ly>=185 && ly<190)))digit_on=1;
  if(digit_on)background=(sec<=10 && fs==2) ? 24'hFF694F:24'hF4D68D;
 end
 if(fs==1 && ly>=128 && ly<192 && lx>=304 && lx<336)
  if(big_digit(lx-304,ly-128,{2'd0,cd},0))background=24'hFFD16D;
 if(ly>=248 && ly<254 && lx>=64 && lx<576)begin
  case(dur)0:progress=(sec*17);1:progress=(sec*17)>>1;2:progress=(sec*91)>>5;default:progress=(sec*109)>>6;endcase
  background=(lx-64)<progress ? 24'h4FCDBB:24'h223B50;
 end else progress=0;
 if(fs==2 && sec<=10 && animation[4] && (lx<5 || lx>=635 || ly<5 || ly>=355))background=24'hFF6048;
 // Self-contained gold trophy, no TF image or pre-rendered video required.
 if(fs==4)begin
  if(ly>=64 && ly<112 && lx>=286 && lx<354 &&
    (lx>=286+(ly-64)/4) && (lx<354-(ly-64)/4))cup_on=1;
  if(ly>=106 && ly<130 && lx>=314 && lx<326)cup_on=1;
  if(ly>=130 && ly<138 && lx>=298 && lx<342)cup_on=1;
  if(ly>=138 && ly<144 && lx>=288 && lx<352)cup_on=1;
  if(ly>=72 && ly<100 && ((lx>=274 && lx<286)||(lx>=354 && lx<366)))cup_on=1;
  if(ly>=96 && ly<102 && ((lx>=278 && lx<300)||(lx>=340 && lx<362)))cup_on=1;
  if(cup_on)background=lx[4] ? 24'hFFD579:24'hD89B35;
  if(ly>56 && ly<240 && lx[4:0]<3 &&
   ((ly+{1'b0,animation}+{lx[8:5],3'b000}) & 9'd63)<5 && !cup_on)
   background=lx[5] ? 24'hFFD579:24'h60D8C4;
 end
 if(ly[8:4]==5)ink=lx<320 ? 24'hFFB4BD:24'h98DDFF;
 if(ly[8:4]==14)ink=24'hFFD579;
 if(ly>=288)ink=24'h91ACC2;
 if(ly<48)ink=24'hE5F3FF;
end
always @(posedge clk or posedge rst)begin
 if(rst)begin bg_q<=0;ink_q<=0;bg_d<=0;ink_d<=0;de_q<=0;vs_q<=0;de_d<=0;vs_d<=0;col_q<=0;rgb<=0;out_de<=0;out_vs<=0;end
 else begin
  bg_q<=background;ink_q<=ink;de_q<=de;vs_q<=vs;col_q<=lx[3:0];
  bg_d<=font_bits[15-col_q] ? ink_q:bg_q;de_d<=de_q;vs_d<=vs_q;
  rgb<=bg_d;out_de<=de_d;out_vs<=vs_d;
 end
end
always @(posedge clk)font_q<=font[{glyph,ly[3:0]}];
endmodule
