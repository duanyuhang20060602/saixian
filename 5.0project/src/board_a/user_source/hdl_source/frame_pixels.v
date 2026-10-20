`timescale 1ns/1ps
// Match the one-clock registered FIFO output to two clocks of protocol delay.
module frame_pixels(input clk,rst,de,high_color,input [11:0] x,input [10:0] y,
 input image_valid,read_ack,empty,input [31:0] data,
 output reg read_req,output read_en,output reg [23:0] rgb,
 output reg armed,output reg output_started,output reg underflow);
reg ack_meta,ack_sync,pop_previous,pair_ok,frame_bad;
reg [15:0] color_tail;reg [23:0] color_last;reg [1:0] color_phase_previous;
reg [15:0] low_pixel;reg active_previous,phase_previous;
wire need_word=high_color ? x[1:0]!=2'd3:!x[0];
wire blank_start=x==0 && y==720;
assign read_en=de && need_word && armed && !empty && !frame_bad;
function [23:0] expand;
 input [15:0] pixel;
 begin expand={{pixel[15:11],pixel[15:13]},
               {pixel[10:5],pixel[10:9]},{pixel[4:0],pixel[4:2]}};end
endfunction
always @(posedge clk or posedge rst)begin
 if(rst)begin read_req<=0;ack_meta<=0;ack_sync<=0;pop_previous<=0;pair_ok<=0;low_pixel<=0;
  armed<=0;output_started<=0;underflow<=0;frame_bad<=0;rgb<=24'h101010;active_previous<=0;phase_previous<=0;color_tail<=0;color_last<=0;color_phase_previous<=0;end
 else begin
  ack_meta<=read_ack;ack_sync<=ack_meta;
  pop_previous<=read_en;active_previous<=de;phase_previous<=x[0];color_phase_previous<=x[1:0];
  if(ack_sync)read_req<=0;
  if(blank_start && image_valid)begin
   read_req<=1;armed<=1;frame_bad<=0;
   if(armed && !frame_bad)output_started<=1;
  end
  if(de && need_word && armed && empty && !frame_bad)begin underflow<=1;frame_bad<=1;end
  if(!active_previous || !armed || frame_bad)begin rgb<=24'h101010;pair_ok<=0;end
  else if(high_color)begin
   case(color_phase_previous)
    0:begin pair_ok<=pop_previous;color_tail<={8'd0,data[7:0]};rgb<=pop_previous ? data[31:8]:24'h101010;end
    1:begin pair_ok<=pair_ok && pop_previous;color_tail<=data[15:0];rgb<=pair_ok && pop_previous ? {color_tail[7:0],data[31:16]}:24'h101010;end
    2:begin pair_ok<=pair_ok && pop_previous;color_last<=data[23:0];rgb<=pair_ok && pop_previous ? {color_tail,data[31:24]}:24'h101010;end
    3:rgb<=pair_ok ? color_last:24'h101010;
   endcase
  end
  else if(!phase_previous)begin
   pair_ok<=pop_previous;low_pixel<=data[15:0];rgb<=pop_previous ? expand(data[31:16]) : 24'h101010;
  end else rgb<=pair_ok ? expand(low_pixel) : 24'h101010;
 end
end
endmodule
