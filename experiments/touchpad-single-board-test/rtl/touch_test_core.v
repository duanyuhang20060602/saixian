`timescale 1ns/1ps
module touch_test_core #(parameter CLK_HZ=75000000)(
 input clk,rst,uart_rx,frame_tick,
 output [10:0] cursor_x,output [9:0] cursor_y,
 output [9:0] raw_x,output [8:0] raw_y,
 output reg mode_enabled,output contact,click,
 output reg [15:0] rx_count,error_count,tap_count,
 output reg [1:0] selection
);
wire valid,down,mode_valid,mode_value,bad;
saixian_hmi_uart #(.CLK_FREQ_HZ(CLK_HZ)) uart(
 .clk(clk),.rst(rst),.uart_rx(uart_rx),.touch_valid(valid),.touch_down(down),
 .touch_x(raw_x),.touch_y(raw_y),.touch_mode_valid(mode_valid),
 .touch_mode_value(mode_value),.frame_error_pulse(bad));
photo_touchpad #(.CLK_HZ(CLK_HZ)) pointer(
 .clk(clk),.rst(rst),.enable(mode_enabled),.frame_tick(frame_tick),
 .sample_valid(valid),.sample_down(down),.sample_x(raw_x),.sample_y(raw_y),
 .cursor_x(cursor_x),.cursor_y(cursor_y),.click(click),.contact(contact));
always @(posedge clk or posedge rst) begin
 if(rst)begin mode_enabled<=1;rx_count<=0;error_count<=0;tap_count<=0;selection<=0;end
 else begin
  if(mode_valid)mode_enabled<=mode_value;
  if(valid)rx_count<=rx_count+1'b1;
  if(bad)error_count<=error_count+1'b1;
  if(click)begin
   tap_count<=tap_count+1'b1;
   if(cursor_y>=400 && cursor_y<528)begin
    if(cursor_x>=128 && cursor_x<416)selection<=1;
    else if(cursor_x>=496 && cursor_x<784)selection<=2;
    else if(cursor_x>=864 && cursor_x<1152)selection<=3;
   end
   if(cursor_x>=496 && cursor_x<784 && cursor_y>=592 && cursor_y<656)begin
    rx_count<=0;error_count<=0;tap_count<=0;selection<=0;
   end
  end
 end
end
endmodule
