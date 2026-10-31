`timescale 1ns/1ps
// Logical 640x360 canvas, doubled to HDMI 1280x720. Four registered
// stages carry RGB, DE and VS together; state is committed only at blanking.
module photo_match_render(input clk,rst,frame_tick,de,vs,input [10:0] x,input [9:0] y,
 input [2:0] state,team_a,team_b,input [9:0] score_a,score_b,
 input [8:0] remaining,input [1:0] countdown,duration_index,
 output reg [23:0] rgb,output reg out_de,out_vs);
reg [2:0] fs,fa,fb;reg [9:0] sa,sb;reg [8:0] sec;
reg [1:0] cd,dur;reg [7:0] animation;
wire [3:0] a0,a1,a2,b0,b1,b2,m0,m1,s0,s1;wire [9:0] frame_progress;
always @(posedge clk or posedge rst)begin
 if(rst)begin fs<=0;fa<=0;fb<=1;sa<=0;sb<=0;sec<=30;cd<=0;dur<=0;animation<=0;
  end
 else if(frame_tick)begin
  fs<=state;fa<=team_a;fb<=team_b;sa<=score_a;sb<=score_b;sec<=remaining;cd<=countdown;dur<=duration_index;
  animation<=animation+1'b1;
 end
end
// Decimal conversion and progress arithmetic run once per frame in blanking.
photo_match_numbers numbers(.clk(clk),.rst(rst),.start(frame_tick),.score_a(sa),.score_b(sb),.seconds(sec),.duration_index(dur),
 .a0(a0),.a1(a1),.a2(a2),.b0(b0),.b1(b1),.b2(b2),.m0(m0),.m1(m1),.s0(s0),.s1(s1),.progress(frame_progress));
wire [9:0] lx={1'b0,x[10:1]};wire [8:0] ly={1'b0,y[9:1]};

function [6:0] segments;input [3:0] n;begin case(n)
 0:segments=7'b1111110;1:segments=7'b0110000;2:segments=7'b1101101;3:segments=7'b1111001;
 4:segments=7'b0110011;5:segments=7'b1011011;6:segments=7'b1011111;7:segments=7'b1110000;
 8:segments=7'b1111111;9:segments=7'b1111011;default:segments=0;endcase end endfunction
function digit_pixel;input[4:0] px;input[5:0] py;input[3:0] n;input compact_digit;
reg[6:0] g;reg left_band,right_band,center_band;reg[2:0] band;
begin
 g=segments(n);left_band=compact_digit ? px<3:px<5;right_band=compact_digit ? px>=17:px>=27;
 center_band=!left_band && !right_band;
 if(compact_digit)band=py<3 ? 0:py<19 ? 1:py<21 ? 2:py<37 ? 3:4;
 else band=py<5 ? 0:py<30 ? 1:py<34 ? 2:py<59 ? 3:4;
 case(band)
 0:digit_pixel=center_band && g[6];1:digit_pixel=(left_band && g[1])||(right_band && g[5]);
 2:digit_pixel=center_band && g[0];3:digit_pixel=(left_band && g[2])||(right_band && g[4]);
 default:digit_pixel=center_band && g[3];endcase
end endfunction
// Store five-bit palette IDs throughout the four-clock rendering pipeline.
function [23:0] palette;input[4:0] color_id;begin case(color_id)
5'd1:palette=24'h091525;
5'd2:palette=24'hE6EEF8;
5'd3:palette=24'h10253B;
5'd4:palette=24'h281C32;
5'd5:palette=24'h102C41;
5'd6:palette=24'hFF6978;
5'd7:palette=24'h50C9FF;
5'd8:palette=24'hFF8291;
5'd9:palette=24'h66D2FF;
5'd10:palette=24'hFF694F;
5'd11:palette=24'hF4D68D;
5'd12:palette=24'hFFD16D;
5'd13:palette=24'h4FCDBB;
5'd14:palette=24'h223B50;
5'd15:palette=24'hFF6048;
5'd16:palette=24'hFFD579;
5'd17:palette=24'hD89B35;
5'd18:palette=24'h60D8C4;
5'd19:palette=24'hFFB4BD;
5'd20:palette=24'h98DDFF;
5'd21:palette=24'h91ACC2;
5'd22:palette=24'hE5F3FF;
default:palette=24'd0;endcase end endfunction
reg [4:0] background,ink;reg cup_on,decoration_on;
reg digit_active,small_digit,colon;reg[4:0] digit_x;reg[5:0] digit_y;reg[3:0] digit_number;reg[4:0] digit_color;
wire[8:0] text_address;wire direct;wire[6:0] direct_glyph;
photo_match_text_query text(.col(lx[9:4]),.row(ly[8:4]),.state(fs),.team_a(fa),.team_b(fb),
 .score_a(sa),.score_b(sb),.seconds(sec),.duration_index(dur),.address(text_address),.direct(direct),.glyph(direct_glyph));
reg [9:0] progress;reg [9:0] dx;reg [8:0] dy;
reg [4:0] bg_q,ink_q,bg_lookup,ink_lookup,bg_d;reg de_q,vs_q,de_lookup,vs_lookup,de_d,vs_d;
reg [3:0] col_q,col_lookup;wire [15:0] font_bits;
photo_match_font font(.clk(clk),.text_address(text_address),.direct(direct),.direct_glyph(direct_glyph),.row(ly[3:0]),.bits(font_bits));
always @* begin
 background=5'd1;ink=5'd2;cup_on=0;decoration_on=0;dx=0;dy=0;
 if(ly<56)background=5'd3;
 if(ly>=72 && ly<216 && lx>=40 && lx<224)background=5'd4;
 if(ly>=72 && ly<216 && lx>=416 && lx<600)background=5'd5;
 if((lx>=40 && lx<44 && ly>=72 && ly<216))background=5'd6;
 if((lx>=596 && lx<600 && ly>=72 && ly<216))background=5'd7;
 if(ly>=248 && ly<254 && lx>=64 && lx<576)begin
  progress=frame_progress;
  background=(lx-64)<progress ? 5'd13:5'd14;
 end else progress=0;
 if(fs==2 && sec<=10 && animation[4] && (lx<5 || lx>=635 || ly<5 || ly>=355))background=5'd15;
 // Self-contained gold trophy, no TF image or pre-rendered video required.
 if(fs==4)begin
  if(ly>=64 && ly<112 && lx>=286 && lx<354 &&
    (lx>=286+(ly-64)/4) && (lx<354-(ly-64)/4))cup_on=1;
  if(ly>=106 && ly<130 && lx>=314 && lx<326)cup_on=1;
  if(ly>=130 && ly<138 && lx>=298 && lx<342)cup_on=1;
  if(ly>=138 && ly<144 && lx>=288 && lx<352)cup_on=1;
  if(ly>=72 && ly<100 && ((lx>=274 && lx<286)||(lx>=354 && lx<366)))cup_on=1;
  if(ly>=96 && ly<102 && ((lx>=278 && lx<300)||(lx>=340 && lx<362)))cup_on=1;
  if(cup_on)begin background=lx[4] ? 5'd16:5'd17;decoration_on=1;end
  if(ly>56 && ly<240 && lx[4:0]<3 &&
   ((ly+{1'b0,animation}+{lx[8:5],3'b000}) & 9'd63)<5 && !cup_on)
   begin background=lx[5] ? 5'd16:5'd18;decoration_on=1;end
 end
 if(ly[8:4]==5)ink=lx<320 ? 5'd19:5'd20;
 if(ly[8:4]==14)ink=5'd16;
 if(ly>=288)ink=5'd21;
 if(ly<48)ink=5'd22;
end
wire[8:0] column_data;wire[3:0] digit_group=column_data[8:5];
photo_match_columns columns(.clk(clk),.address(lx),.data(column_data));
reg score_row_q,timer_row_q,count_row_q,decoration_q;reg[5:0] digit_row_q;reg[4:0] count_x_q;
always @(posedge clk)begin
 decoration_q<=decoration_on;
 score_row_q<=ly>=144 && ly<208;
 timer_row_q<=fs!=1 && ly>=160 && ly<200;
 count_row_q<=fs==1 && ly>=128 && ly<192 && lx>=304 && lx<336;
 digit_row_q<=ly[5:0];count_x_q<=lx[4:0]^5'd16;
end

always @*begin
 digit_active=0;small_digit=0;colon=0;digit_x=column_data[4:0];digit_y=0;digit_number=0;digit_color=0;
 if(score_row_q && digit_group>=1 && digit_group<=6)begin
  digit_active=1;digit_y=digit_row_q-6'd16;digit_color=digit_group<=3 ? 5'd8:5'd9;
  case(digit_group)1:digit_number=a0;2:digit_number=a1;3:digit_number=a2;4:digit_number=b0;5:digit_number=b1;6:digit_number=b2;endcase
 end
 if(timer_row_q && digit_group>=7 && digit_group<=11)begin
  small_digit=1;digit_y=digit_row_q^6'd32;digit_active=digit_group!=9;
  digit_color=(sec<=10 && fs==2) ? 5'd10:5'd11;
  case(digit_group)7:digit_number=m0;8:digit_number=m1;10:digit_number=s0;11:digit_number=s1;endcase
  if(digit_group==9 && ((digit_y>=10 && digit_y<15)||(digit_y>=25 && digit_y<30)))colon=1;
 end
 if(count_row_q)begin digit_active=1;small_digit=0;digit_x=count_x_q;digit_y=digit_row_q;digit_number={2'd0,cd};digit_color=5'd12;end
end
// Break RAM output -> digit select -> shape into separate registered
// stages. The existing four-clock RGB/DE/VS contract is unchanged.
reg[4:0] digit_x_q,digit_color_q;reg[5:0] digit_y_q;reg[3:0] digit_number_q;
reg digit_active_q,small_digit_q,colon_q;
always @(posedge clk or posedge rst)
 if(rst)begin digit_x_q<=0;digit_y_q<=0;digit_number_q<=0;digit_color_q<=0;digit_active_q<=0;small_digit_q<=0;colon_q<=0;end
 else begin
  digit_x_q<=digit_x;digit_y_q<=digit_y;digit_number_q<=digit_number;digit_color_q<=digit_color;
  digit_active_q<=digit_active && !decoration_q;small_digit_q<=small_digit;colon_q<=colon && !decoration_q;
 end
wire digit_on=colon_q || (digit_active_q && digit_pixel(digit_x_q,digit_y_q,digit_number_q,small_digit_q));
wire[4:0] digit_background=digit_on ? digit_color_q:bg_lookup;
always @(posedge clk or posedge rst)begin
 if(rst)begin bg_q<=0;ink_q<=0;bg_lookup<=0;ink_lookup<=0;col_lookup<=0;de_lookup<=0;vs_lookup<=0;bg_d<=0;de_q<=0;vs_q<=0;de_d<=0;vs_d<=0;col_q<=0;rgb<=0;out_de<=0;out_vs<=0;end
 else begin
  bg_q<=background;ink_q<=ink;de_q<=de;vs_q<=vs;col_q<=lx[3:0];
  bg_lookup<=bg_q;ink_lookup<=ink_q;col_lookup<=col_q;de_lookup<=de_q;vs_lookup<=vs_q;
  bg_d<=font_bits[15-col_lookup] ? ink_lookup:digit_background;de_d<=de_lookup;vs_d<=vs_lookup;
  rgb<=palette(bg_d);out_de<=de_d;out_vs<=vs_d;
 end
end
endmodule
