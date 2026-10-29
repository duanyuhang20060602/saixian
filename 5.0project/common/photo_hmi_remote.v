`timescale 1ns/1ps
// At most one unacknowledged chunk. A busy receiver leaves the ACK unchanged,
// so the SPI polls retry without duplicating a byte on the physical HMI UART.
module photo_hmi_chunk_b #(parameter CHUNK_BYTES=12)(input clk,rst,input byte_valid,input [7:0] byte_data,
 output byte_ready,input command_done,input ack_valid,input [7:0] ack_token,
 output [31:0] header,output [95:0] payload);
reg [CHUNK_BYTES*8-1:0] bytes;reg [3:0] count;reg sealed,first;reg [7:0] token;
assign byte_ready=!sealed;
assign header={8'h48,token,(sealed ? count:4'd0),first,11'd0};
assign payload={bytes,{((12-CHUNK_BYTES)*8){1'b0}}};
always @(posedge clk or posedge rst)
 if(rst)begin bytes<=0;count<=0;sealed<=0;first<=1;token<=0;end
 else if(sealed && ack_valid && ack_token==token)begin sealed<=0;count<=0;first<=0;token<=token+1'b1;end
 else if(!sealed)begin
  if(byte_valid)begin bytes[CHUNK_BYTES*8-1-count*8 -: 8]<=byte_data;count<=count+1'b1;if(count==CHUNK_BYTES-1)sealed<=1;end
  if(command_done && count!=0)sealed<=1;
 end
endmodule

// Single 12-byte buffer shared by SPI reception and UART shifting. A candidate
// is admitted only while idle and becomes visible only after the SPI CRC passes.
module photo_hmi_relay_a #(parameter CLK_HZ=75000000,BAUD=115200,CHUNK_BYTES=12)(
 input clk,rst,input [31:0] session,input packet_begin,word_valid,
 input [1:0] word_index,input [31:0] word_data,input commit,
 output reg ack_valid,output reg [7:0] ack_token,output reg reset_request,
 output uart_tx);
localparam DIV=CLK_HZ/BAUD,DB=$clog2(DIV);

reg [CHUNK_BYTES*8-1:0] bytes;reg [7:0] candidate_token;reg [3:0] candidate_count;
reg candidate_first,candidate_magic,drop_packet;
reg [3:0] remaining,bit_index;reg [1:0] flush;
reg [9:0] serial;reg active;reg [DB-1:0] baud_count;
assign uart_tx=active ? serial[0]:1'b1;
wire busy=active || remaining!=0 || flush!=0;
always @(posedge clk or posedge rst)
 if(rst)begin
  bytes<=0;candidate_token<=0;candidate_count<=0;
  candidate_first<=0;candidate_magic<=0;drop_packet<=1;
  remaining<=0;bit_index<=0;flush<=3;serial<=10'h3ff;active<=0;baud_count<=0;
  ack_valid<=0;ack_token<=0;reset_request<=1;
 end else begin
  begin
  if(packet_begin)begin drop_packet<=busy;candidate_magic<=0;end
  if(word_valid && !drop_packet)begin
   case(word_index)
    0:begin candidate_magic<=1'b1;
      candidate_token<=word_data[23:16];candidate_count<=word_data[15:12];candidate_first<=word_data[11];end
    default:if(word_index<=(CHUNK_BYTES/4))bytes<={bytes[CHUNK_BYTES*8-33:0],word_data};
   endcase
  end
  if(commit && !drop_packet && !busy && candidate_magic && candidate_count>0 && candidate_count<=CHUNK_BYTES &&
    (ack_valid ? candidate_token==ack_token+8'd1: candidate_first && candidate_token==0))begin
   ack_valid<=1;ack_token<=candidate_token;reset_request<=0;remaining<=candidate_count;
  end
  if(active)begin
   if(baud_count==DIV-1)begin
    baud_count<=0;
    if(bit_index==9)active<=0;
    else begin serial<={1'b1,serial[9:1]};bit_index<=bit_index+1'b1;end
   end else baud_count<=baud_count+1'b1;
  end else if(flush!=0 || remaining!=0)begin
   serial<={1'b1,(flush!=0 ? 8'hff:bytes[CHUNK_BYTES*8-1 -: 8]),1'b0};active<=1;baud_count<=0;bit_index<=0;
   if(flush!=0)flush<=flush-1'b1;
   else begin bytes<={bytes[CHUNK_BYTES*8-9:0],8'd0};remaining<=remaining-1'b1;end
  end
  end

 end
endmodule
