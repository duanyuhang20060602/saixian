`timescale 1ns/1ps
// 24-byte frame: A5 5A, 20-byte big-endian payload, CRC16-CCITT.
// All messages use the same layout; receivers discard bad CRC/framing/timeout.
module v4_port_ref_photo_uart #(parameter CLK_HZ=75000000, BAUD=115200)(
 input clk,rst,rx, output tx, input send,input [159:0] message,
 output busy,output reg received,output reg [159:0] received_message,
 output reg bad_packet
);
localparam DIV=(CLK_HZ+BAUD/2)/BAUD;
function [15:0] crc_byte;
 input [15:0] c;input [7:0] b;reg [15:0] t;integer j;
 begin t=c^{b,8'd0};for(j=0;j<8;j=j+1)t=t[15] ? (t<<1)^16'h1021 : t<<1;crc_byte=t;end
endfunction
reg [9:0] tx_bits;reg [31:0] tx_count;reg [3:0] tx_bit;
reg [4:0] tx_pos;reg [159:0] tx_payload;reg [15:0] tx_crc;
reg tx_active;
assign busy=tx_active;
assign tx=tx_active ? tx_bits[0] : 1'b1;
function [7:0] get_byte;
 input [4:0] pos;input [159:0] payload;input [15:0] check;
 begin
  if(pos==0)get_byte=8'ha5;else if(pos==1)get_byte=8'h5a;
  else if(pos==22)get_byte=check[15:8];else if(pos==23)get_byte=check[7:0];
  else get_byte=payload[159-(pos-2)*8 -:8];
 end
endfunction
always @(posedge clk or posedge rst)begin
 if(rst)begin tx_bits<=10'h3ff;tx_count<=0;tx_bit<=0;tx_pos<=0;tx_payload<=0;tx_crc<=16'hffff;tx_active<=0;end
 else if(!tx_active)begin
  if(send)begin tx_payload<=message;tx_crc<=16'hffff;tx_pos<=0;tx_bit<=0;tx_count<=0;tx_bits<={1'b1,8'ha5,1'b0};tx_active<=1;end
 end else if(tx_count==DIV-1)begin
  tx_count<=0;
  if(tx_bit==9)begin
   tx_bit<=0;
   if(tx_pos==23)tx_active<=0;
   else begin
    tx_pos<=tx_pos+1'b1;
    if(tx_pos>=1 && tx_pos<21)begin
     tx_crc<=crc_byte(tx_crc,get_byte(tx_pos+1'b1,tx_payload,tx_crc));
    end
    tx_bits<={1'b1,get_byte(tx_pos+1'b1,tx_payload,tx_crc),1'b0};
   end
  end else begin tx_bit<=tx_bit+1'b1;tx_bits<={1'b1,tx_bits[9:1]};end
 end else tx_count<=tx_count+1'b1;
end
reg rx_meta,rx_sync;reg rx_active;reg [31:0] rx_count;
reg [3:0] rx_bit;reg [7:0] rx_byte;reg byte_valid;
always @(posedge clk or posedge rst)begin
 if(rst)begin rx_meta<=1;rx_sync<=1;rx_active<=0;rx_count<=0;rx_bit<=0;rx_byte<=0;byte_valid<=0;end
 else begin
  rx_meta<=rx;rx_sync<=rx_meta;byte_valid<=0;
  if(!rx_active)begin if(!rx_sync)begin rx_active<=1;rx_count<=DIV/2;rx_bit<=0;end end
  else if(rx_count!=0)rx_count<=rx_count-1'b1;
  else begin
   rx_count<=DIV-1;
   if(rx_bit==0)begin if(rx_sync)rx_active<=0;else rx_bit<=1;end
   else if(rx_bit<=8)begin rx_byte[rx_bit-1]<=rx_sync;rx_bit<=rx_bit+1'b1;end
   else begin rx_active<=0;if(rx_sync)byte_valid<=1;end
  end
 end
end
reg [4:0] rx_pos;reg [159:0] rx_payload;reg [15:0] rx_crc;reg [7:0] check_hi;
reg [31:0] timeout;
always @(posedge clk or posedge rst)begin
 if(rst)begin received<=0;received_message<=0;bad_packet<=0;rx_pos<=0;rx_payload<=0;rx_crc<=16'hffff;check_hi<=0;timeout<=0;end
 else begin
  received<=0;bad_packet<=0;
  if(rx_pos==0 || byte_valid)timeout<=0;else timeout<=timeout+1'b1;
  if(timeout>DIV*40)begin rx_pos<=0;bad_packet<=1;timeout<=0;end
  else if(byte_valid)begin
   if(rx_pos==0)begin if(rx_byte==8'ha5)rx_pos<=1;end
   else if(rx_pos==1)begin
    if(rx_byte==8'h5a)begin rx_pos<=2;rx_crc<=16'hffff;end
    else rx_pos<=rx_byte==8'ha5 ? 1 : 0;
   end else if(rx_pos<22)begin rx_payload<={rx_payload[151:0],rx_byte};rx_crc<=crc_byte(rx_crc,rx_byte);rx_pos<=rx_pos+1'b1;end
   else if(rx_pos==22)begin check_hi<=rx_byte;rx_pos<=23;end
   else begin
    rx_pos<=0;
    if({check_hi,rx_byte}==rx_crc)begin received<=1;received_message<=rx_payload;end
    else bad_packet<=1;
   end
  end
 end
end
endmodule
