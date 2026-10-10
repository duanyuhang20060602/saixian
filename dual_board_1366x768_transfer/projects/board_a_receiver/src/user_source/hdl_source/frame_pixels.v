`timescale 1ns/1ps
// Match the one-clock registered FIFO output to two clocks of protocol delay.
module frame_pixels(input clk,rst,de,input [11:0] x,input [10:0] y,
 input image_valid,read_ack,empty,input [31:0] data,
 output reg read_req,output read_en,output reg [23:0] rgb,
 output reg armed,output reg output_started,output reg underflow);
reg ack_meta,ack_sync,pop_previous,pair_ok,frame_bad;
reg [15:0] low_pixel;reg active_previous,phase_previous;
wire blank_start=x==0 && y==768;
assign read_en=de && !x[0] && armed && !empty && !frame_bad;
function [7:0] limited;
 input [7:0] value;
 // 16 + round(219 * value / 256): full-range RGB565 to AVI limited RGB.
 reg [15:0] product;
 begin product=value*8'd219+16'd128;limited=8'd16+product[15:8];end
endfunction
function [23:0] expand;
 input [15:0] pixel;
 begin expand={limited({pixel[15:11],pixel[15:13]}),
               limited({pixel[10:5],pixel[10:9]}),limited({pixel[4:0],pixel[4:2]})};end
endfunction
always @(posedge clk or posedge rst)begin
 if(rst)begin read_req<=0;ack_meta<=0;ack_sync<=0;pop_previous<=0;pair_ok<=0;low_pixel<=0;
  armed<=0;output_started<=0;underflow<=0;frame_bad<=0;rgb<=24'h101010;active_previous<=0;phase_previous<=0;end
 else begin
  ack_meta<=read_ack;ack_sync<=ack_meta;
  pop_previous<=read_en;active_previous<=de;phase_previous<=x[0];
  if(ack_sync)read_req<=0;
  if(blank_start && image_valid)begin
   read_req<=1;armed<=1;frame_bad<=0;
   if(armed && !frame_bad)output_started<=1;
  end
  if(de && !x[0] && armed && empty && !frame_bad)begin underflow<=1;frame_bad<=1;end
  if(!active_previous || !armed || frame_bad)begin rgb<=24'h101010;pair_ok<=0;end
  else if(!phase_previous)begin
   pair_ok<=pop_previous;low_pixel<=data[15:0];rgb<=pop_previous ? expand(data[31:16]) : 24'h101010;
  end else rgb<=pair_ok ? expand(low_pixel) : 24'h101010;
 end
end
endmodule
