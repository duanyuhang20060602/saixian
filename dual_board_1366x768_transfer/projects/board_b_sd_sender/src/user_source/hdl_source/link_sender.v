`timescale 1ns/1ps
// Registered-output SDRAM FIFO; falling-edge launch, rising-edge acceptance.
module link_sender #(parameter FRAME_PIXELS=1049088)(
 input clk,rst,start,input [31:0] data,input empty,read_ack,link_ready,
 output reg read_req,output read_en,
 output reg [15:0] link_data,output reg link_valid,link_sof,link_eof,
 output reg sent,output busy
);
localparam IDLE=0,REQUEST=1,DRAIN_ACK=2,FETCH=3,LATCH=4,HIGH=5,LOW=6,DONE=7;
reg [2:0] state;reg [20:0] index;reg [31:0] word_data;
reg ack_meta,ack_sync;reg [2:0] settle;
assign read_en=(state==FETCH) && !empty;
assign busy=state!=IDLE && state!=DONE;
always @(posedge clk or posedge rst) begin
 if(rst)begin state<=IDLE;index<=0;word_data<=0;read_req<=0;sent<=0;ack_meta<=0;ack_sync<=0;settle<=0;end
 else begin
  ack_meta<=read_ack;ack_sync<=ack_meta;
  case(state)
   IDLE:if(start)begin read_req<=1;index<=0;state<=REQUEST;end
   REQUEST:if(ack_sync)begin read_req<=0;settle<=0;state<=DRAIN_ACK;end
   DRAIN_ACK:if(!ack_sync)begin if(settle==4)state<=FETCH;else settle<=settle+1'b1;end
   FETCH:if(!empty)state<=LATCH;
   LATCH:begin word_data<=data;state<=HIGH;end
   HIGH:if(link_valid && link_ready)state<=LOW;
   LOW:if(link_valid && link_ready)begin
    if(index==FRAME_PIXELS-2)begin sent<=1;state<=DONE;end
    else begin index<=index+2;state<=FETCH;end
   end
   DONE:state<=DONE;
   default:state<=IDLE;
  endcase
 end
end
always @(negedge clk or posedge rst)begin
 if(rst)begin link_data<=0;link_valid<=0;link_sof<=0;link_eof<=0;end
 else begin
  link_valid<=state==HIGH || state==LOW;
  link_data<=state==LOW ? word_data[15:0] : word_data[31:16];
  link_sof<=state==HIGH && index==0;
  link_eof<=state==LOW && index==FRAME_PIXELS-2;
 end
end
endmodule
