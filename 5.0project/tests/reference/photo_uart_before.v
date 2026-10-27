`timescale 1ns/1ps
// 24-byte frame: A5 5A, 20-byte big-endian payload, CRC16-CCITT.
// All messages use the same layout; receivers discard bad CRC/framing/timeout.
module photo_uart_before #(parameter CLK_HZ=75000000, BAUD=115200,PULSE_PAYLOAD=0)(
 input clk,rst,rx, output tx, input send,input [159:0] message,
 output busy,output reg received,output [159:0] received_message,
 output reg bad_packet
);
localparam DIV=(CLK_HZ+BAUD/2)/BAUD;
// V4 port: size counters to their reachable ranges; packet semantics stay unchanged.
localparam COUNT_BITS=($clog2(DIV+1)>0) ? $clog2(DIV+1):1;
localparam TIMEOUT_BITS=($clog2(DIV*40+2)>0) ? $clog2(DIV*40+2):1;
function [15:0] crc_byte;
 input [15:0] c;input [7:0] b;reg [15:0] t;integer j;
 begin t=c^{b,8'd0};for(j=0;j<8;j=j+1)t=t[15] ? (t<<1)^16'h1021 : t<<1;crc_byte=t;end
endfunction
reg [9:0] tx_bits;reg [COUNT_BITS-1:0] tx_count;reg [3:0] tx_bit;
reg [4:0] tx_pos;reg [159:0] tx_payload;reg [15:0] tx_crc;
reg tx_active;
assign busy=tx_active;
assign tx=tx_active ? tx_bits[0] : 1'b1;
// Fixed byte slices preserve constant packet fields and share TX/CRC selection.
reg [7:0] next_byte;
always @* begin
 case(tx_pos)
  0:next_byte=8'h5a;
  1:next_byte=tx_payload[159:152];
  2:next_byte=tx_payload[151:144];
  3:next_byte=tx_payload[143:136];
  4:next_byte=tx_payload[135:128];
  5:next_byte=tx_payload[127:120];
  6:next_byte=tx_payload[119:112];
  7:next_byte=tx_payload[111:104];
  8:next_byte=tx_payload[103:96];
  9:next_byte=tx_payload[95:88];
  10:next_byte=tx_payload[87:80];
  11:next_byte=tx_payload[79:72];
  12:next_byte=tx_payload[71:64];
  13:next_byte=tx_payload[63:56];
  14:next_byte=tx_payload[55:48];
  15:next_byte=tx_payload[47:40];
  16:next_byte=tx_payload[39:32];
  17:next_byte=tx_payload[31:24];
  18:next_byte=tx_payload[23:16];
  19:next_byte=tx_payload[15:8];
  20:next_byte=tx_payload[7:0];
  21:next_byte=tx_crc[15:8];
  default:next_byte=tx_crc[7:0];
 endcase
end
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
     tx_crc<=crc_byte(tx_crc,next_byte);
    end
    tx_bits<={1'b1,next_byte,1'b0};
   end
  end else begin tx_bit<=tx_bit+1'b1;tx_bits<={1'b1,tx_bits[9:1]};end
 end else tx_count<=tx_count+1'b1;
end
reg rx_meta,rx_sync;reg rx_active;reg [COUNT_BITS-1:0] rx_count;
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
// Control consumers read only on the verified received pulse. Removing
// the second packet bank preserves CRC gating and full-duplex UART timing.
reg [159:0] published_message;
assign received_message=PULSE_PAYLOAD ? rx_payload:published_message;
reg [TIMEOUT_BITS-1:0] timeout;
always @(posedge clk or posedge rst)begin
 if(rst)begin received<=0;published_message<=0;bad_packet<=0;rx_pos<=0;rx_payload<=0;rx_crc<=16'hffff;check_hi<=0;timeout<=0;end
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
    if({check_hi,rx_byte}==rx_crc)begin received<=1;if(!PULSE_PAYLOAD)published_message<=rx_payload;end
    else bad_packet<=1;
   end
  end
 end
end
endmodule
