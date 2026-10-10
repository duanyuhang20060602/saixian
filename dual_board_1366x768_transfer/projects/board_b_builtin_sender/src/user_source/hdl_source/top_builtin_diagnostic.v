`timescale 1ns/1ps
// Same native pattern as A local test, directly sent without B SDRAM/SD.
module top_dual_still_sender(
 input clk,sd_miso,output sd_ncs,sd_dclk,sd_mosi,
 output link_clk,output reg [15:0] link_data,output reg link_valid,link_sof,link_eof,
 input link_ready,image_ack,output transfer_done,transfer_error,
 output [5:0] seg_sel,output [7:0] seg_data);
wire locked,rst;
builtin_link_pll u_link_pll(.refclk(clk),.reset(1'b0),.clk0_out(link_clk),.locked(locked));
dual_still_reset_sync reset_link(.clk(link_clk),.arst(!locked),.rst(rst));
reg [11:0] x;reg [10:0] y;
wire [15:0] pixel;
builtin_pattern565 generator(.clk(link_clk),.rst(rst),.x(x),.y(y),.rgb(pixel));
localparam START=0,WAIT0=1,WAIT1=2,WAIT2=3,SEND=4,DONE=5;
reg [2:0] state;reg [21:0] startup;
reg ack_meta,ack_sync;
always @(posedge link_clk or posedge rst)begin
 if(rst)begin x<=0;y<=0;state<=START;startup<=0;ack_meta<=0;ack_sync<=0;end
 else begin
  ack_meta<=image_ack;ack_sync<=ack_meta;
  case(state)
   START:if(&startup)state<=WAIT0;else startup<=startup+1'b1;
   WAIT0:state<=WAIT1;
   WAIT1:state<=WAIT2;
   WAIT2:state<=SEND;
   SEND:if(link_valid && link_ready)begin
    if(x==1365)begin x<=0;if(y==767)state<=DONE;else begin y<=y+1'b1;state<=WAIT0;end end
    else begin x<=x+1'b1;state<=WAIT0;end
   end
   DONE:state<=DONE;
   default:state<=START;
  endcase
 end
end
always @(negedge link_clk or posedge rst)begin
 if(rst)begin link_data<=0;link_valid<=0;link_sof<=0;link_eof<=0;end
 else begin
  link_data<=pixel;link_valid<=state==SEND;
  link_sof<=state==SEND && x==0 && y==0;
  link_eof<=state==SEND && x==1365 && y==767;
 end
end
assign sd_ncs=1;assign sd_dclk=0;assign sd_mosi=1;
assign transfer_done=ack_sync;assign transfer_error=0;
assign seg_sel=6'b111110;
assign seg_data=ack_sync ? 8'h92 : state==DONE ? 8'h99 : state==START ? 8'hc0 : 8'hb0;
endmodule
