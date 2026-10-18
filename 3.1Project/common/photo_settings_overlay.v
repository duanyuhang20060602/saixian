`timescale 1ns/1ps
// One frame-locked menu for image, audio and playback controls.
module photo_settings_overlay #(parameter VIDEO_DELAY=21)(
 input clk,rst,frame_tick,de,settings_mode,updating,
 input [11:0] x,input [10:0] y,input [3:0] setting_item,
 input [3:0] volume,brightness,contrast,saturation,input [1:0] sharpness,enhancement,
 input invert,vintage,input [4:0] effect,input edge_enable,auto_enable,waveform_mode,high_color,audio_repair_enable,
 input [23:0] rgb_in,output [23:0] rgb_out
);
reg visible,pending;reg [3:0] selected;
reg [4:0] values[0:13];
always @(posedge clk or posedge rst)begin
 if(rst)begin visible<=0;pending<=0;selected<=0;
  values[0]<=5;values[1]<=4;values[2]<=4;values[3]<=1;values[4]<=4;
  values[5]<=0;values[6]<=0;values[7]<=1;values[8]<=0;values[9]<=0;values[10]<=0;values[11]<=0;values[12]<=0;values[13]<=0;
 end else if(frame_tick)begin
  visible<=settings_mode;pending<=updating;selected<=setting_item;
  values[0]<=volume;values[1]<=brightness;values[2]<=contrast;values[3]<={2'd0,sharpness};values[4]<=saturation;
  values[5]<={3'd0,invert};values[6]<={3'd0,vintage};values[7]<={2'd0,enhancement};
  values[8]<=effect;values[9]<={3'd0,auto_enable};values[10]<={3'd0,waveform_mode};values[11]<={3'd0,high_color};values[12]<={4'd0,audio_repair_enable};values[13]<={4'd0,edge_enable};
 end
end
function [6:0] text_glyph;
 input [5:0] text_id;input [4:0] index;
 begin text_glyph=0;case(text_id)
   0:case(index)
    0:text_glyph=7'd48;
    1:text_glyph=7'd49;
    2:text_glyph=7'd50;
    3:text_glyph=7'd51;
    default:text_glyph=0;
   endcase
   1:case(index)
    0:text_glyph=7'd5;
    1:text_glyph=7'd6;
    default:text_glyph=0;
   endcase
   2:case(index)
    0:text_glyph=7'd7;
    1:text_glyph=7'd8;
    default:text_glyph=0;
   endcase
   3:case(index)
    0:text_glyph=7'd9;
    1:text_glyph=7'd10;
    default:text_glyph=0;
   endcase
   4:case(index)
    0:text_glyph=7'd11;
    1:text_glyph=7'd12;
    default:text_glyph=0;
   endcase
   5:case(index)
    0:text_glyph=7'd13;
    1:text_glyph=7'd14;
    default:text_glyph=0;
   endcase
   6:case(index)
    0:text_glyph=7'd15;
    1:text_glyph=7'd16;
    default:text_glyph=0;
   endcase
   7:case(index)
    0:text_glyph=7'd17;
    1:text_glyph=7'd18;
    default:text_glyph=0;
   endcase
   8:case(index)
    0:text_glyph=7'd52;
    1:text_glyph=7'd53;
    2:text_glyph=7'd54;
    3:text_glyph=7'd55;
    default:text_glyph=0;
   endcase
   9:case(index)
    0:text_glyph=7'd56;
    1:text_glyph=7'd57;
    2:text_glyph=7'd58;
    3:text_glyph=7'd59;
    default:text_glyph=0;
   endcase
   10:case(index)
    0:text_glyph=7'd23;
    1:text_glyph=7'd24;
    2:text_glyph=7'd25;
    default:text_glyph=0;
   endcase
   11:case(index)
    0:text_glyph=7'd26;
    1:text_glyph=7'd27;
    2:text_glyph=7'd28;
    default:text_glyph=0;
   endcase
   12:case(index)
    0:text_glyph=7'd45;
    1:text_glyph=7'd46;
    2:text_glyph=7'd47;
    3:text_glyph=7'd36;
    4:text_glyph=7'd29;
    5:text_glyph=7'd30;
    6:text_glyph=7'd0;
    7:text_glyph=7'd0;
    8:text_glyph=7'd45;
    9:text_glyph=7'd46;
    10:text_glyph=7'd47;
    11:text_glyph=7'd37;
    12:text_glyph=7'd31;
    default:text_glyph=0;
   endcase
   13:case(index)
    0:text_glyph=7'd45;
    1:text_glyph=7'd46;
    2:text_glyph=7'd47;
    3:text_glyph=7'd38;
    4:text_glyph=7'd32;
    5:text_glyph=7'd33;
    6:text_glyph=7'd0;
    7:text_glyph=7'd0;
    8:text_glyph=7'd45;
    9:text_glyph=7'd46;
    10:text_glyph=7'd47;
    11:text_glyph=7'd39;
    12:text_glyph=7'd34;
    default:text_glyph=0;
   endcase
   14:case(index)
    0:text_glyph=7'd60;
    1:text_glyph=7'd61;
    default:text_glyph=0;
   endcase
   15:case(index)
    0:text_glyph=7'd60;
    1:text_glyph=7'd62;
    2:text_glyph=7'd63;
    3:text_glyph=7'd64;
    default:text_glyph=0;
   endcase
   16:case(index)
    0:text_glyph=7'd62;
    1:text_glyph=7'd65;
    default:text_glyph=0;
   endcase
   17:case(index)
    0:text_glyph=7'd66;
    1:text_glyph=7'd67;
    default:text_glyph=0;
   endcase
   18:case(index)
    0:text_glyph=7'd68;
    1:text_glyph=7'd69;
    default:text_glyph=0;
   endcase
   19:case(index)
    0:text_glyph=7'd70;
    1:text_glyph=7'd71;
    default:text_glyph=0;
   endcase
   20:case(index)
    0:text_glyph=7'd72;
    1:text_glyph=7'd73;
    default:text_glyph=0;
   endcase
   21:case(index)
    0:text_glyph=7'd74;
    1:text_glyph=7'd75;
    2:text_glyph=7'd76;
    3:text_glyph=7'd57;
    default:text_glyph=0;
   endcase
   22:case(index)
    0:text_glyph=7'd77;
    1:text_glyph=7'd78;
    2:text_glyph=7'd79;
    3:text_glyph=7'd70;
    default:text_glyph=0;
   endcase
   23:case(index)
    0:text_glyph=7'd80;
    1:text_glyph=7'd81;
    2:text_glyph=7'd82;
    default:text_glyph=0;
   endcase
   24:case(index)
    0:text_glyph=7'd83;
    1:text_glyph=7'd84;
    default:text_glyph=0;
   endcase
   25:case(index)
    0:text_glyph=7'd85;
    1:text_glyph=7'd86;
    default:text_glyph=0;
   endcase
   26:case(index)
    0:text_glyph=7'd87;
    1:text_glyph=7'd88;
    default:text_glyph=0;
   endcase
   27:case(index)
    0:text_glyph=7'd89;
    1:text_glyph=7'd90;
    2:text_glyph=7'd91;
    3:text_glyph=7'd92;
    default:text_glyph=0;
   endcase
   28:case(index)
    0:text_glyph=7'd93;
    1:text_glyph=7'd94;
    default:text_glyph=0;
   endcase
   29:case(index)
    0:text_glyph=7'd95;
    1:text_glyph=7'd91;
    2:text_glyph=7'd92;
    default:text_glyph=0;
   endcase
   30:case(index)
    0:text_glyph=7'd60;
    1:text_glyph=7'd62;
    2:text_glyph=7'd96;
    3:text_glyph=7'd97;
    default:text_glyph=0;
   endcase
   31:case(index)
    0:text_glyph=7'd98;
    1:text_glyph=7'd99;
    2:text_glyph=7'd66;
    3:text_glyph=7'd100;
    default:text_glyph=0;
   endcase
   32:case(index)
    0:text_glyph=7'd101;
    1:text_glyph=7'd102;
    2:text_glyph=7'd103;
    3:text_glyph=7'd104;
    default:text_glyph=0;
   endcase
   33:case(index)
    0:text_glyph=7'd105;
    1:text_glyph=7'd106;
    default:text_glyph=0;
   endcase
   34:case(index)
    0:text_glyph=7'd107;
    1:text_glyph=7'd108;
    2:text_glyph=7'd109;
    3:text_glyph=7'd110;
    default:text_glyph=0;
   endcase
   35:case(index)
    0:text_glyph=7'd60;
    1:text_glyph=7'd111;
    2:text_glyph=7'd112;
    3:text_glyph=7'd113;
    default:text_glyph=0;
   endcase
   36:case(index)
    0:text_glyph=7'd114;
    1:text_glyph=7'd115;
    2:text_glyph=7'd109;
    3:text_glyph=7'd110;
    default:text_glyph=0;
   endcase
   37:case(index)
    0:text_glyph=7'd116;
    1:text_glyph=7'd117;
    2:text_glyph=7'd118;
    default:text_glyph=0;
   endcase
   38:case(index)
    0:text_glyph=7'd119;
    1:text_glyph=7'd120;
    default:text_glyph=0;
   endcase
   default:text_glyph=0;
 endcase end
endfunction

wire panel=de && visible && x>=64 && x<864 && y>=80 && y<688;
wire [10:0] row_y=y-11'd144;
wire [3:0] row_index=row_y[8:5];
wire [4:0] row_local=row_y[4:0];
wire [11:0] label_x=x-12'd96,value_x=x-12'd608;
wire [10:0] label_y=y-11'd96,footer_y=y-11'd608;
reg [6:0] glyph;reg [3:0] font_row,font_col;
reg text_on,highlight,bar,track;reg [4:0] value;reg [8:0] bar_width;
reg [5:0] value_label;
reg [23:0] text_color;
always @*begin
 glyph=0;font_row=0;font_col=0;text_on=0;highlight=0;bar=0;track=0;
 value=0;bar_width=0;value_label=0;text_color=24'hebebeb;
 if(panel)begin
  if(y>=96 && y<128 && x>=96 && x<224)begin
   glyph=text_glyph(0,label_x[8:5]);font_row=label_y[4:1];font_col=label_x[4:1];text_on=1;text_color=24'h7de3ff;
  end else if(y>=96 && y<128 && x>=688 && x<784)begin
   glyph=text_glyph(pending ? 10:11,(x-688)>>5);font_row=label_y[4:1];font_col=(x-688)>>1;text_on=1;
   text_color=pending ? 24'hffd166:24'h7de3ff;
  end else if(y>=144 && y<592 && row_index<=13)begin
   value=values[row_index];highlight=row_index==selected;
   case(row_index)
    0,1,2,4:bar_width={5'd0,value}*9'd28;
    3:bar_width={5'd0,value}*9'd72;
    7:bar_width={5'd0,value}*9'd112;
    default:bar_width=0;
   endcase
   case(row_index)
    5,6,9,12,13:value_label=value==0 ? 18:19;
    8:value_label=value>=11 ? 6'd25+value:value>=7 ? 6'd24+value:6'd20+value;
    10:value_label=value==0 ? 16:17;
    11:value_label=value==0 ? 28:29;
    default:value_label=0;
   endcase
   if(x>=96 && x<288)begin
    glyph=text_glyph(row_index==13 ? 6'd35:row_index==12 ? 6'd30:row_index==0 ? 5'd14:row_index==10 ? 5'd15:row_index==11 ? 5'd27:{1'b0,row_index},label_x[8:5]);
    font_col=label_x[4:1];font_row=row_local[4:1];text_on=1;
   end else if(x>=608 && x<800)begin
    glyph=value_label!=0 ? text_glyph(value_label,value_x[8:5]):value_x[8:5]==0 ? 7'd35+value:7'd0;
    font_col=value_x[4:1];font_row=row_local[4:1];text_on=1;text_color=24'hffd166;
   end
   if(value_label==0 && row_local>=10 && row_local<22 && x>=320 && x<544)begin track=1;bar=x-320<bar_width;end
  end else if(y>=608 && y<648 && x>=96 && x<400)begin
   if((y<624) || (y>=632))begin
    glyph=text_glyph(y<624 ? 12:13,label_x[8:4]);font_col=label_x[3:0];
    font_row=y<624 ? footer_y[3:0]:(y-632);text_on=1;text_color=24'h7de3ff;
   end
  end
 end
end
reg [6:0] glyph_s1;reg [3:0] row_s1,col_s1,col_s2;
reg panel_s1,panel_s2,text_s1,text_s2,ink_s3;
reg [23:0] bg_s3,color_s3;
reg [23:0] bg_s1,bg_s2,color_s1,color_s2;
wire [15:0] font_bits;
photo_menu_font font(.clk(clk),.glyph(glyph_s1),.row(row_s1),.bits(font_bits));
reg [VIDEO_DELAY-3:0] panel_pipe;
reg [23:0] color_pipe[0:VIDEO_DELAY-4];integer i;
always @(posedge clk or posedge rst)begin
 if(rst)begin
  glyph_s1<=0;row_s1<=0;col_s1<=0;col_s2<=0;panel_s1<=0;panel_s2<=0;text_s1<=0;text_s2<=0;
  bg_s1<=0;bg_s2<=0;color_s1<=0;color_s2<=0;bg_s3<=0;color_s3<=0;ink_s3<=0;panel_pipe<=0;
  for(i=0;i<VIDEO_DELAY-3;i=i+1)color_pipe[i]<=0;
 end else begin
  glyph_s1<=glyph;row_s1<=font_row;col_s1<=font_col;
  panel_s1<=panel;text_s1<=text_on;color_s1<=text_color;
  bg_s1<=bar ? 24'h32b8d4:track ? 24'h334456:highlight ? 24'h20405a:24'h142332;
  panel_s2<=panel_s1;text_s2<=text_s1;col_s2<=col_s1;color_s2<=color_s1;bg_s2<=bg_s1;
  panel_pipe<={panel_pipe[VIDEO_DELAY-4:0],panel_s2};
  // Split BRAM bit selection and colour fanout; remove one later delay
  // stage to preserve the established VIDEO_DELAY at the output.
  ink_s3<=text_s2 && font_bits[15-col_s2];bg_s3<=bg_s2;color_s3<=color_s2;
  color_pipe[0]<=ink_s3 ? color_s3:bg_s3;
  for(i=1;i<VIDEO_DELAY-3;i=i+1)color_pipe[i]<=color_pipe[i-1];
 end
end
assign rgb_out=panel_pipe[VIDEO_DELAY-3] ? color_pipe[VIDEO_DELAY-4]:rgb_in;
endmodule
