`timescale 1ns/1ps
// Chinese settings panel at native HDMI 720p; masks run parallel to video.
module photo_settings_overlay #(parameter VIDEO_DELAY=21)(
 input clk,rst,frame_tick,de,settings_mode,updating,
 input [11:0] x,input [10:0] y,input [3:0] setting_item,
 input [3:0] brightness,contrast,saturation,input [1:0] sharpness,enhancement,
 input invert,vintage,input [2:0] effect,input auto_enable,
 input [23:0] rgb_in,output [23:0] rgb_out
);
reg visible,pending;reg [3:0] selected;
reg [3:0] values[1:9];
always @(posedge clk or posedge rst)begin
 if(rst)begin visible<=0;pending<=0;selected<=1;
  values[1]<=4;values[2]<=4;values[3]<=1;values[4]<=4;
  values[5]<=0;values[6]<=0;values[7]<=1;values[8]<=0;values[9]<=0;
 end else if(frame_tick)begin
  visible<=settings_mode;pending<=updating;selected<=setting_item;
  values[1]<=brightness;values[2]<=contrast;values[3]<={2'd0,sharpness};values[4]<=saturation;
  values[5]<={3'd0,invert};values[6]<={3'd0,vintage};values[7]<={2'd0,enhancement};
  values[8]<={1'b0,effect};values[9]<={3'd0,auto_enable};
 end
end
function [5:0] text_glyph;
 input [3:0] text_id;input [4:0] index;
 begin text_glyph=0;case(text_id)
   0:case(index)
    0:text_glyph=6'd1;
    1:text_glyph=6'd2;
    2:text_glyph=6'd3;
    3:text_glyph=6'd4;
    default:text_glyph=0;
   endcase
   1:case(index)
    0:text_glyph=6'd5;
    1:text_glyph=6'd6;
    default:text_glyph=0;
   endcase
   2:case(index)
    0:text_glyph=6'd7;
    1:text_glyph=6'd8;
    default:text_glyph=0;
   endcase
   3:case(index)
    0:text_glyph=6'd9;
    1:text_glyph=6'd10;
    default:text_glyph=0;
   endcase
   4:case(index)
    0:text_glyph=6'd11;
    1:text_glyph=6'd12;
    default:text_glyph=0;
   endcase
   5:case(index)
    0:text_glyph=6'd13;
    1:text_glyph=6'd14;
    default:text_glyph=0;
   endcase
   6:case(index)
    0:text_glyph=6'd15;
    1:text_glyph=6'd16;
    default:text_glyph=0;
   endcase
   7:case(index)
    0:text_glyph=6'd17;
    1:text_glyph=6'd18;
    default:text_glyph=0;
   endcase
   8:case(index)
    0:text_glyph=6'd19;
    1:text_glyph=6'd20;
    default:text_glyph=0;
   endcase
   9:case(index)
    0:text_glyph=6'd21;
    1:text_glyph=6'd22;
    default:text_glyph=0;
   endcase
   10:case(index)
    0:text_glyph=6'd23;
    1:text_glyph=6'd24;
    2:text_glyph=6'd25;
    default:text_glyph=0;
   endcase
   11:case(index)
    0:text_glyph=6'd26;
    1:text_glyph=6'd27;
    2:text_glyph=6'd28;
    default:text_glyph=0;
   endcase
   12:case(index)
    0:text_glyph=6'd45;
    1:text_glyph=6'd46;
    2:text_glyph=6'd47;
    3:text_glyph=6'd36;
    4:text_glyph=6'd29;
    5:text_glyph=6'd30;
    6:text_glyph=6'd0;
    7:text_glyph=6'd0;
    8:text_glyph=6'd45;
    9:text_glyph=6'd46;
    10:text_glyph=6'd47;
    11:text_glyph=6'd37;
    12:text_glyph=6'd31;
    default:text_glyph=0;
   endcase
   13:case(index)
    0:text_glyph=6'd45;
    1:text_glyph=6'd46;
    2:text_glyph=6'd47;
    3:text_glyph=6'd38;
    4:text_glyph=6'd32;
    5:text_glyph=6'd33;
    6:text_glyph=6'd0;
    7:text_glyph=6'd0;
    8:text_glyph=6'd45;
    9:text_glyph=6'd46;
    10:text_glyph=6'd47;
    11:text_glyph=6'd39;
    12:text_glyph=6'd34;
    default:text_glyph=0;
   endcase
   default:text_glyph=0;
 endcase end
endfunction

wire panel=de && visible && x>=64 && x<624 && y>=80 && y<672;
wire [10:0] row_y=y-11'd160;
wire [3:0] row_index=row_y/48+1'b1;
wire [5:0] row_local=row_y%48;
wire [11:0] label_x=x-12'd96,value_x=x-12'd544;
wire [10:0] label_y=y-11'd96,footer_y=y-11'd616;
reg [5:0] glyph;reg [3:0] font_row,font_col;
reg text_on,highlight,bar,track;reg [3:0] value;reg [8:0] bar_width;
reg [23:0] text_color;
always @*begin
 glyph=0;font_row=0;font_col=0;text_on=0;highlight=0;bar=0;track=0;
 value=0;bar_width=0;text_color=24'hebebeb;
 if(panel)begin
  if(y>=96 && y<128 && x>=96 && x<224)begin
   glyph=text_glyph(0,label_x[8:5]);font_row=label_y[4:1];font_col=label_x[4:1];text_on=1;text_color=24'h7de3ff;
  end else if(y>=96 && y<128 && x>=400 && x<496)begin
   glyph=text_glyph(pending ? 10:11,(x-400)>>5);font_row=label_y[4:1];font_col=(x-400)>>1;text_on=1;
   text_color=pending ? 24'hffd166:24'h7de3ff;
  end else if(y>=160 && y<592 && row_index>=1 && row_index<=9)begin
   value=values[row_index];highlight=row_index==selected;
   case(row_index)
    1,2,4:bar_width={5'd0,value}*9'd28;
    3:bar_width={5'd0,value}*9'd72;
    7:bar_width={5'd0,value}*9'd112;
    8:bar_width={5'd0,value}*9'd36;
    default:bar_width=value==0 ? 0:224;
   endcase
   if(row_local<32)begin
    if(x>=96 && x<224)begin
     glyph=text_glyph(row_index,label_x[8:5]);font_col=label_x[4:1];font_row=row_local[4:1];text_on=1;
    end else if(x>=544 && x<576)begin
     glyph=6'd35+value;font_col=value_x[4:1];font_row=row_local[4:1];text_on=1;text_color=24'hffd166;
    end
    if(row_local>=10 && row_local<22 && x>=272 && x<496)begin track=1;bar=x-272<bar_width;end
   end
  end else if(y>=616 && y<656 && x>=96 && x<400)begin
   if((y<632) || (y>=640))begin
    glyph=text_glyph(y<632 ? 12:13,label_x[8:4]);font_col=label_x[3:0];
    font_row=y<632 ? footer_y[3:0]:(y-640);text_on=1;text_color=24'h7de3ff;
   end
  end
 end
end
reg [5:0] glyph_s1;reg [3:0] row_s1,col_s1,col_s2;
reg panel_s1,panel_s2,text_s1,text_s2;
reg [23:0] bg_s1,bg_s2,color_s1,color_s2;
wire [15:0] font_bits;
photo_menu_font font(.clk(clk),.glyph(glyph_s1),.row(row_s1),.bits(font_bits));
reg [VIDEO_DELAY-3:0] panel_pipe;
reg [23:0] color_pipe[0:VIDEO_DELAY-3];integer i;
always @(posedge clk or posedge rst)begin
 if(rst)begin
  glyph_s1<=0;row_s1<=0;col_s1<=0;col_s2<=0;panel_s1<=0;panel_s2<=0;text_s1<=0;text_s2<=0;
  bg_s1<=0;bg_s2<=0;color_s1<=0;color_s2<=0;panel_pipe<=0;
  for(i=0;i<VIDEO_DELAY-2;i=i+1)color_pipe[i]<=0;
 end else begin
  glyph_s1<=glyph;row_s1<=font_row;col_s1<=font_col;
  panel_s1<=panel;text_s1<=text_on;color_s1<=text_color;
  bg_s1<=bar ? 24'h32b8d4:track ? 24'h334456:highlight ? 24'h20405a:24'h142332;
  panel_s2<=panel_s1;text_s2<=text_s1;col_s2<=col_s1;color_s2<=color_s1;bg_s2<=bg_s1;
  panel_pipe<={panel_pipe[VIDEO_DELAY-4:0],panel_s2};
  color_pipe[0]<=text_s2 && font_bits[15-col_s2] ? color_s2:bg_s2;
  for(i=1;i<VIDEO_DELAY-2;i=i+1)color_pipe[i]<=color_pipe[i-1];
 end
end
assign rgb_out=panel_pipe[VIDEO_DELAY-3] ? color_pipe[VIDEO_DELAY-3]:rgb_in;
endmodule
