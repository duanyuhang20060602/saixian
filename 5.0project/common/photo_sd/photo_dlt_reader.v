// Read the ORIGINAL AWARD720.DLT, not a converted BMP. First verify the
// header and bootstrap descriptor, then stream-decode the key frame.
// CRC disabled by user request; structural checks and write drain remain.
// Physical sectors can be interleaved with audio by the outer arbiter.
module photo_dlt_reader #(parameter PIXEL_GAP=16)(
 input clk,rst,start,input [31:0] start_sector,
 output ready,done,output reg [3:0] error,
 output write_req,input write_ack,full,
 output reg pixel_valid,output reg [23:0] pixel,
 output req,output reg [31:0] sector,
 input byte_valid,input [7:0] byte_data,input block_end
);
localparam IDLE=0,HEADER=1,HEADER_CHECK=2,VERIFY=3,VERIFY_CHECK=4,
 INDEX_CHECK=5,WRITE=6,DATA=7,DATA_CHECK=8,CMD=9,LITERAL=10,
 FILL_WORD=11,LOW=12,HIGH=13,FINISH=14,DONE=15,FAILED=16,FETCH=17,WORD_CHECK=18,TAIL=19,TAIL_LOW=20,TAIL_HIGH=21;
reg [4:0] state,return_state,word_state;
reg [31:0] tail_offset;reg [20:0] tail_left;reg [159:0] light_header;
reg [31:0] base,total_bytes;
reg [31:0] header_sector,frame_sector,tail_sector;
reg [9:0] count;
reg [23:0] low_bytes;reg [255:0] descriptor;
reg [31:0] buffer[0:127];reg [7:0] read_index;reg [31:0] word_data;
reg [20:0] encoded_left,cursor,run;reg fill;
reg [31:0] pair;reg [3:0] pace;reg ack_meta,ack_sync;
reg input_valid,input_end;reg [7:0] input_data;
wire header_ok;wire [31:0] header_bytes,header_crc;
photo_dlt_header header(.clk(clk),.rst(rst),.valid(state==HEADER && input_valid && count<64),
 .index(count[5:0]),.data(input_data),.header_ok(header_ok),.file_bytes(header_bytes),.payload_crc(header_crc));
assign ready=state==IDLE || state==DONE || state==FAILED;
assign done=state==DONE;
assign req=state==HEADER || state==VERIFY || state==DATA || state==TAIL;
assign write_req=state==WRITE;
wire [31:0] offset=descriptor[31:0],length=descriptor[63:32];
wire [1:0] kind=word_data[31:30];wire [29:0] amount=word_data[29:0];
reg [20:0] remaining_frame,available_encoded;reg [4:0] command_checks;
reg [32:0] descriptor_end;reg [6:0] index_checks;
// Register the SD input before CRC/header/index enables. Keep async RAM
// lookup and command validation out of the same 100 MHz transition path.
always @(posedge clk or posedge rst)begin
 if(rst)begin input_valid<=0;input_end<=0;input_data<=0;word_data<=0;
  remaining_frame<=0;available_encoded<=0;command_checks<=0;descriptor_end<=0;index_checks<=0;
  header_sector<=0;frame_sector<=0;tail_sector<=0;end
 else begin
  input_valid<=byte_valid;input_end<=block_end;input_data<=byte_data;
  word_data<=buffer[read_index[6:0]];
  remaining_frame<=460800-cursor;available_encoded<=encoded_left-1'b1;
  descriptor_end<={1'b0,offset}+{1'b0,length};
  // Sector bases settle hundreds of SD clocks before their consuming states.
  // Keep the 32-bit adders ahead of the state-selected request register.
  header_sector<=base+1'b1;frame_sector<=base+(offset>>7);tail_sector<=base+(tail_offset>>7);
  index_checks[0]<=offset>=384 && offset[6:0]==0 && offset[31:21]==0;
  index_checks[1]<=length!=0 && length[31:21]==0;
  index_checks[2]<=descriptor_end<={3'd0,total_bytes[31:2]};
  index_checks[3]<=descriptor[95:64]!=0;
  index_checks[4]<=descriptor[95:64]<=500000000;
  index_checks[5]<=descriptor[191:160]==0;
  index_checks[6]<=descriptor[255:192]==0;
  if(state==WORD_CHECK)begin
   command_checks[0]<=kind==0 || kind==3;
   command_checks[1]<=amount==0;
   command_checks[2]<=amount[29:21]!=0 || amount[20:0]>remaining_frame;
   command_checks[3]<=kind==1 && (amount[29:21]!=0 || amount[20:0]>available_encoded);
   command_checks[4]<=kind==2 && encoded_left<2;
  end
 end
end
function [23:0] expand;
 input [15:0] p;begin expand={p[15:11],p[15:13],p[10:5],p[10:9],p[4:0],p[4:2]};end
endfunction
always @(posedge clk or posedge rst)begin
 if(rst)begin
  state<=IDLE;return_state<=FETCH;word_state<=CMD;error<=0;sector<=0;base<=0;total_bytes<=0;
  count<=0;
  low_bytes<=0;descriptor<=0;read_index<=0;encoded_left<=0;cursor<=0;run<=0;fill<=0;pair<=0;
  pace<=0;pixel_valid<=0;pixel<=0;tail_offset<=0;tail_left<=0;light_header<=0;ack_meta<=0;ack_sync<=0;
 end else begin
  pixel_valid<=0;ack_meta<=write_ack;ack_sync<=ack_meta;
  if(pace!=0)pace<=pace-1'b1;
  if(start && ready)begin
   state<=HEADER;sector<=start_sector;base<=start_sector;count<=0;error<=0;
   descriptor<=0;cursor<=0;read_index<=0;pace<=0;
  end else case(state)
   HEADER,VERIFY,DATA,TAIL:begin
    if(input_valid)begin
     if(state==HEADER && count>=256 && count<276)light_header[(count-256)*8+:8]<=input_data;
     if(count>=512)begin error<=2;state<=FAILED;end
     else begin
      count<=count+1'b1;
      if(state==VERIFY)begin
       if(count<32)descriptor[count*8+:8]<=input_data;
      end
      if(state==DATA || state==TAIL)begin
       if(count[1:0]==3)buffer[count[8:2]]<={input_data,low_bytes};
       else low_bytes[count[1:0]*8+:8]<=input_data;
      end
     end
    end
    if(input_end)state<=state==HEADER ? HEADER_CHECK:state==VERIFY ? VERIFY_CHECK:DATA_CHECK;
   end
   HEADER_CHECK:begin
    if(count!=512)begin error<=2;state<=FAILED;end
    else if(!header_ok || light_header[31:0]!=120 || light_header[95:64]!=230400 || light_header[127:96]!=32'h53505835 || light_header[159:128]!=6 || light_header[38:32]!=0)begin error<=1;state<=FAILED;end
    else if({1'b0,light_header[63:32]}+33'd230400>{3'd0,header_bytes[31:2]})begin error<=1;state<=FAILED;end
    else begin total_bytes<=header_bytes;tail_offset<=light_header[63:32];
     sector<=header_sector;count<=0;state<=VERIFY;end
   end
   VERIFY_CHECK:begin
    if(count!=512)begin error<=2;state<=FAILED;end
    else state<=INDEX_CHECK;
   end
   INDEX_CHECK:begin
    if(!(&index_checks))begin error<=4;state<=FAILED;end
    else begin sector<=frame_sector;encoded_left<=length[20:0];state<=WRITE;end
   end
   WRITE:if(ack_sync)begin count<=0;return_state<=FETCH;word_state<=CMD;state<=DATA;end
   DATA_CHECK:begin
    if(count!=512)begin error<=2;state<=FAILED;end
    else begin read_index<=0;state<=return_state;end
   end
   FETCH:begin
    if(encoded_left==0)begin
     if(word_state==CMD && cursor==460800)state<=FINISH;
     else begin error<=5;state<=FAILED;end
    end else if(read_index==128)begin
     return_state<=FETCH;sector<=sector+1'b1;count<=0;state<=DATA;
    end else state<=WORD_CHECK;
   end
   WORD_CHECK:state<=word_state;
   CMD,LITERAL,FILL_WORD:begin
    read_index<=read_index+1'b1;encoded_left<=encoded_left-1'b1;
    if(state==CMD)begin
     if(|command_checks)begin error<=5;state<=FAILED;end
     else begin run<=amount[20:0];fill<=kind==2;word_state<=kind==1 ? LITERAL:FILL_WORD;state<=FETCH;end
    end else begin pair<=word_data;state<=LOW;end
   end
   LOW:if(pace==0 && !full)begin pixel<=expand(pair[15:0]);pixel_valid<=1;pace<=PIXEL_GAP-1;state<=HIGH;end
   HIGH:if(pace==0 && !full)begin
    pixel<=expand(pair[31:16]);pixel_valid<=1;pace<=PIXEL_GAP-1;
    cursor<=cursor+1'b1;run<=run-1'b1;
    if(run==1)begin word_state<=CMD;state<=FETCH;end
    else if(fill)state<=LOW;else begin word_state<=LITERAL;state<=FETCH;end
   end
   FINISH:begin sector<=tail_sector;tail_left<=230400;count<=0;return_state<=TAIL_LOW;state<=TAIL;end
   TAIL_LOW:begin
    if(tail_left==0)state<=DONE;
    else if(read_index==128)begin sector<=sector+1'b1;count<=0;return_state<=TAIL_LOW;state<=TAIL;end
    else if(pace==0 && !full)begin pixel<=expand(word_data[31:16]);pixel_valid<=1;pace<=PIXEL_GAP-1;state<=TAIL_HIGH;end
   end
   TAIL_HIGH:if(pace==0 && !full)begin
    pixel<=expand(word_data[15:0]);pixel_valid<=1;pace<=PIXEL_GAP-1;
    read_index<=read_index+1'b1;tail_left<=tail_left-1'b1;state<=TAIL_LOW;
   end
  endcase
 end
end
endmodule
