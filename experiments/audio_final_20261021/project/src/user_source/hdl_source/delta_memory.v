// Arbitration around the successful 2.0 sdram wrapper. The SDRAM protocol,
// clocks, phase and refresh implementation are reused unchanged.
module delta_memory #(parameter VERIFY_CACHE=0,parameter RUN_BUS_TEST=1,parameter BASE_ADDR=0,parameter VIDEO_REFILL_LIMIT=256)(
 input clk,input rst,input init,input refreshing,input busy,
 output app_rd,output [20:0] rd_addr,input rd_valid,input [31:0] rd_data,
 output app_wr,output [20:0] wr_addr,output [31:0] wr_data,
 input upload_done,input [20:0] file_words,input up_empty,input [8:0] up_count,
 input [31:0] up_data,output up_pop,output reg cache_ready,
 input frame_toggle,input display_valid,input active_slot,
 output reg video_reset,output video_push,output [31:0] video_data,input [8:0] video_count,
 input stream_start,input [20:0] stream_offset,input [20:0] stream_words,
 output reg stream_ack,output reg stream_reset,output cmd_push,output [31:0] cmd_data,
 input [8:0] cmd_count,
 input patch_valid,input [20:0] patch_addr,input [31:0] patch_data,output patch_ready,
 output reg [3:0] error,output idle,input [31:0] payload_crc,
 output [159:0] debug_data,output [3:0] wr_dm,output patch_drained,output local_clear
);
localparam IDLE=0,READ_RUN=1,READ_DRAIN=2,UPLOAD_RUN=3,WRITE_DRAIN=4,
 PATCH_RUN=5,PATCH_ACK=6,VIDEO_CLEAR=7,COMMAND_CLEAR=8,TEST_WRITE=9;
localparam VIDEO=0,COMMAND=1,UPLOAD=2,PATCH=3,VERIFY=4,TEST=5;
reg [3:0] state;reg [2:0] owner;
reg [20:0] address,upload_written,video_next,command_next,command_remaining;
reg [16:0] video_remaining;
reg [7:0] left,expected,responses;
reg [4:0] quiet;reg [3:0] clear_count;reg frame_seen,start_seen;
reg [1:0] patch_lane;
// Native SDRAM transactions use aligned 64-word reads even for an eight-word
// index or a one-word no-op stream. Discard prefix/padding in this arbiter.
wire [7:0] command_capacity=8'd64-{2'd0,command_next[5:0]};
wire [7:0] command_take=command_remaining<command_capacity ? command_remaining[7:0] : command_capacity;
reg [7:0] command_first,command_end;
reg verify_started;reg [20:0] verify_next,verify_remaining,verify_received;
reg [31:0] verify_crc;
reg [31:0] upload_crc,first_actual,first_expected;
reg [20:0] first_address;
reg test_started,test_written_done,test_done,test_bad,test_late,test_early,test_zero,test_ones;
reg [6:0] test_written;
// Header words 0..63 are scratch after upload. Header metadata is already
// latched; descriptors start at word 128, which is also the CRC boundary.
function [31:0] test_pattern;
 input [5:0] index;
 begin test_pattern=32'hA55A0000^32'd230400^{26'd0,index};end
endfunction
assign debug_data={{11'd0,first_address},first_expected,first_actual,
 verify_crc^32'hffffffff,upload_crc^32'hffffffff};
function [31:0] crc_word;
 input [31:0] old,word;
 reg [31:0] mix;
 reg [64:0] terms;
 begin
  mix=old^word;
  terms[0]=mix[0]^mix[22];
  terms[1]=mix[2]^mix[7];
  terms[2]=mix[1]^mix[23];
  terms[3]=mix[3]^mix[6];
  terms[4]=mix[4]^terms[0];
  terms[5]=mix[5]^mix[8];
  terms[6]=mix[17]^mix[24];
  terms[7]=mix[18]^mix[25];
  terms[8]=mix[10]^mix[26];
  terms[9]=mix[11]^mix[27];
  terms[10]=mix[12]^mix[28];
  terms[11]=mix[13]^mix[29];
  terms[12]=mix[14]^mix[30];
  terms[13]=mix[15]^mix[31];
  terms[14]=mix[20]^terms[1];
  terms[15]=mix[9]^mix[21];
  terms[16]=mix[16]^terms[4];
  terms[17]=mix[7]^mix[19];
  terms[18]=mix[5]^terms[13];
  terms[19]=mix[24]^mix[28];
  terms[20]=mix[25]^mix[29];
  terms[21]=terms[2]^terms[8];
  terms[22]=mix[0]^terms[10];
  terms[23]=mix[16]^mix[23];
  terms[24]=terms[6]^terms[11];
  terms[25]=terms[7]^terms[12];
  terms[26]=mix[19]^mix[27];
  terms[27]=mix[8]^mix[26];
  terms[28]=mix[3]^mix[4];
  terms[29]=terms[1]^terms[15];
  terms[30]=terms[5]^terms[6];
  terms[31]=mix[2]^mix[9];
  terms[32]=terms[3]^terms[5];
  terms[33]=mix[9]^mix[11];
  terms[34]=mix[6]^mix[30];
  terms[35]=mix[31]^terms[9];
  terms[36]=mix[13]^terms[4];
  terms[37]=terms[0]^terms[18];
  terms[38]=terms[2]^terms[14];
  terms[39]=terms[3]^terms[16];
  terms[40]=mix[10]^terms[31];
  terms[41]=mix[4]^terms[17];
  terms[42]=mix[5]^terms[21];
  terms[43]=mix[4]^terms[14];
  terms[44]=mix[12]^terms[5];
  terms[45]=mix[24]^terms[8];
  terms[46]=terms[9]^terms[34];
  terms[47]=mix[25]^terms[22];
  terms[48]=terms[35]^terms[47];
  terms[49]=mix[3]^mix[20];
  terms[50]=mix[14]^terms[23];
  terms[51]=mix[1]^mix[21];
  terms[52]=mix[10]^mix[15];
  terms[53]=terms[12]^terms[24];
  terms[54]=terms[16]^terms[25];
  terms[55]=mix[17]^terms[36];
  terms[56]=mix[14]^mix[18];
  terms[57]=mix[22]^terms[26];
  terms[58]=mix[15]^terms[19];
  terms[59]=mix[3]^mix[21];
  terms[60]=terms[20]^terms[30];
  terms[61]=mix[31]^terms[26];
  terms[62]=mix[2]^terms[10];
  terms[63]=mix[30]^terms[7];
  terms[64]=mix[28]^terms[12];
  crc_word[0]=terms[27]^terms[38]^terms[39];
  crc_word[1]=mix[27]^terms[2]^terms[28]^terms[29]^terms[30];
  crc_word[2]=terms[4]^terms[7]^terms[19]^terms[32]^terms[40];
  crc_word[3]=terms[3]^terms[20]^terms[33]^terms[41]^terms[42];
  crc_word[4]=terms[43]^terms[44]^terms[45]^terms[46];
  crc_word[5]=mix[7]^mix[13]^terms[15]^terms[32]^terms[48];
  crc_word[6]=terms[11]^terms[22]^terms[40]^terms[49]^terms[50];
  crc_word[7]=mix[11]^terms[28]^terms[51]^terms[52]^terms[53];
  crc_word[8]=mix[2]^mix[11]^mix[12]^terms[18]^terms[54];
  crc_word[9]=mix[19]^terms[13]^terms[14]^terms[44]^terms[55];
  crc_word[10]=mix[5]^mix[26]^terms[29]^terms[36]^terms[56];
  crc_word[11]=mix[14]^terms[2]^terms[32]^terms[52]^terms[57];
  crc_word[12]=mix[6]^terms[23]^terms[33]^terms[43]^terms[58];
  crc_word[13]=mix[0]^mix[7]^mix[10]^mix[12]^mix[16]^terms[59]^terms[60];
  crc_word[14]=mix[1]^terms[7]^terms[27]^terms[33]^terms[34]^terms[55];
  crc_word[15]=mix[9]^mix[12]^terms[1]^terms[42]^terms[56]^terms[61];
  crc_word[16]=mix[13]^mix[16]^mix[22]^terms[9]^terms[21]^terms[41]^terms[58];
  crc_word[17]=mix[20]^terms[9]^terms[50]^terms[60]^terms[62];
  crc_word[18]=mix[15]^mix[26]^terms[3]^terms[15]^terms[22]^terms[24]^terms[63];
  crc_word[19]=mix[1]^mix[27]^mix[31]^terms[8]^terms[11]^terms[17]^terms[54];
  crc_word[20]=mix[17]^terms[9]^terms[17]^terms[18]^terms[39]^terms[64];
  crc_word[21]=mix[3]^mix[17]^mix[18]^mix[26]^mix[29]^terms[37]^terms[62];
  crc_word[22]=mix[18]^mix[30]^terms[11]^terms[14]^terms[27]^terms[57];
  crc_word[23]=mix[0]^mix[8]^mix[23]^terms[15]^terms[49]^terms[61]^terms[64];
  crc_word[24]=mix[8]^mix[29]^terms[3]^terms[8]^terms[13]^terms[19]^terms[23]^terms[29];
  crc_word[25]=mix[20]^terms[6]^terms[20]^terms[21]^terms[31]^terms[46];
  crc_word[26]=terms[1]^terms[10]^terms[35]^terms[45]^terms[59]^terms[63];
  crc_word[27]=mix[6]^mix[16]^mix[19]^terms[11]^terms[38]^terms[48];
  crc_word[28]=mix[6]^mix[21]^mix[23]^terms[10]^terms[16]^terms[53];
  crc_word[29]=mix[7]^terms[2]^terms[24]^terms[25]^terms[37];
  crc_word[30]=mix[20]^mix[22]^mix[24]^terms[13]^terms[17]^terms[25]^terms[28];
  crc_word[31]=mix[19]^mix[25]^terms[1]^terms[3]^terms[37]^terms[51];
 end
endfunction
wire [7:0] upload_burst=up_count>=64 ? 8'd64 : {1'b0,up_count[6:0]};
// Upload and readback are separate bus states; both checks share one network.
wire [31:0] crc_mix=state==UPLOAD_RUN ? upload_crc^wr_data : verify_crc^rd_data;
wire [31:0] crc_next=crc_word(32'd0,crc_mix);
assign app_rd=state==READ_RUN && left!=0;
assign idle=state==IDLE;
// FIFO-only housekeeping never owns the shared physical SDRAM bus.
assign local_clear=state==VIDEO_CLEAR || state==COMMAND_CLEAR;
assign rd_addr=BASE_ADDR+address;
assign app_wr=state==PATCH_RUN || (RUN_BUS_TEST && state==TEST_WRITE) || (state==UPLOAD_RUN && !up_empty && left!=0);
assign wr_addr=BASE_ADDR+(state==PATCH_RUN ? {address[20:2],patch_lane} : RUN_BUS_TEST && state==TEST_WRITE ? 21'd230400+test_written : 21'd230400+upload_written);
assign wr_data=state==PATCH_RUN ? patch_data : RUN_BUS_TEST && state==TEST_WRITE ? test_pattern(test_written[5:0]) : up_data;
// APUG011: random addresses are legal at FOUR-word boundaries. A single-word
// patch is a complete aligned four-beat write, with three fully masked beats.
wire patch_live=state==PATCH_RUN && patch_valid && patch_addr=={address[20:2],patch_lane};
assign wr_dm=state==PATCH_RUN && !patch_live ? 4'hf : 4'h0;
assign up_pop=state==UPLOAD_RUN && app_wr;
// Consecutive decoded words in the SAME aligned group share one transaction.
// Gaps or commands mask unused beats. Publication waits for patch_drained.
assign patch_ready=patch_live;
assign patch_drained=state==IDLE && !busy && !refreshing && error==0;
assign video_push=rd_valid && owner==VIDEO && (state==READ_RUN || state==READ_DRAIN);
assign video_data=rd_data;
assign cmd_push=rd_valid && owner==COMMAND && responses>=command_first && responses<command_end &&
 (state==READ_RUN || state==READ_DRAIN);
assign cmd_data=rd_data;
always @(posedge clk)begin
 if(rst)begin
  state<=IDLE;owner<=VIDEO;address<=0;upload_written<=0;video_next<=0;command_next<=0;
  command_remaining<=0;video_remaining<=0;left<=0;expected<=0;responses<=0;
  quiet<=0;clear_count<=0;frame_seen<=0;start_seen<=0;patch_lane<=0;
  video_reset<=1;stream_reset<=1;stream_ack<=0;cache_ready<=0;error<=0;
  command_first<=0;command_end<=0;verify_started<=0;verify_next<=230400;
  verify_remaining<=0;verify_received<=0;verify_crc<=32'hffffffff;
  upload_crc<=32'hffffffff;first_actual<=0;first_expected<=0;first_address<=0;
  test_started<=0;test_written_done<=0;test_done<=0;test_written<=0;
  test_bad<=0;test_late<=1;test_early<=1;test_zero<=1;test_ones<=1;
 end else begin
  stream_ack<=0;
  if(!stream_start)start_seen<=0;
  if(rd_valid && (state==READ_RUN || state==READ_DRAIN))responses<=responses+1'b1;
  if(rd_valid && owner==VERIFY && (state==READ_RUN || state==READ_DRAIN))begin
   if(verify_received>=128)verify_crc<=crc_next;
   verify_received<=verify_received+1'b1;
  end
  if(app_wr && state==UPLOAD_RUN && upload_written>=128)upload_crc<=crc_next;
  if(RUN_BUS_TEST && rd_valid && owner==TEST && (state==READ_RUN || state==READ_DRAIN))begin
   if(rd_data!=test_pattern(responses[5:0]))begin
    test_bad<=1;
    if(!test_bad)begin first_actual<=rd_data;first_expected<=test_pattern(responses[5:0]);first_address<=21'd230400+responses;end
   end
   if(responses!=0 && rd_data!=test_pattern(responses[5:0]-6'd1))test_late<=0;
   if(responses!=63 && rd_data!=test_pattern(responses[5:0]+6'd1))test_early<=0;
   if(rd_data!=0)test_zero<=0;
   if(rd_data!=32'hffffffff)test_ones<=0;
  end
  if(error==0)case(state)
   IDLE:begin
    if(upload_done && upload_written==file_words && up_empty && !cache_ready && !verify_started)begin
     if(VERIFY_CACHE)begin
      if((upload_crc^32'hffffffff)!=payload_crc)error<=10;
      else if(!RUN_BUS_TEST || test_done)begin verify_started<=1;verify_next<=230400;verify_remaining<=file_words;end
      else if(!test_started)test_started<=1;
     end
     else cache_ready<=1;
    end
    if(frame_toggle!=frame_seen)begin
     frame_seen<=frame_toggle;video_reset<=1;clear_count<=0;state<=VIDEO_CLEAR;
     video_next<=active_slot ? 21'd115200 : 21'd0;
     video_remaining<=display_valid ? 17'd115200 : 17'd0;
    end else if(stream_start && !start_seen)begin
     start_seen<=1;stream_reset<=1;clear_count<=0;state<=COMMAND_CLEAR;
     command_next<=21'd230400+stream_offset;command_remaining<=stream_words;
    end else if(init && !busy && !refreshing)begin
     if(video_remaining!=0 && video_count<=VIDEO_REFILL_LIMIT)begin
      owner<=VIDEO;address<=video_next;left<=128;expected<=128;responses<=0;
      video_next<=video_next+128;video_remaining<=video_remaining-128;state<=READ_RUN;
     end else if(!cache_ready && !up_empty && (up_count>=64 || upload_done))begin
      owner<=UPLOAD;left<=upload_burst;state<=UPLOAD_RUN;
     end else if(VERIFY_CACHE && RUN_BUS_TEST && test_started && !test_done)begin
      owner<=TEST;
      if(!test_written_done)begin test_written<=0;state<=TEST_WRITE;end
      else begin address<=230400;left<=64;expected<=64;responses<=0;state<=READ_RUN;end
     end else if(VERIFY_CACHE && verify_remaining!=0)begin
      owner<=VERIFY;address<=verify_next;left<=64;expected<=64;responses<=0;
      verify_next<=verify_next+64;verify_remaining<=verify_remaining-64;state<=READ_RUN;
     end else if(cache_ready && command_remaining!=0 && cmd_count<=128)begin
      owner<=COMMAND;address<={command_next[20:6],6'd0};left<=64;expected<=64;responses<=0;
      command_first<={2'd0,command_next[5:0]};command_end<={2'd0,command_next[5:0]}+command_take;
      command_next<=command_next+command_take;command_remaining<=command_remaining-command_take;state<=READ_RUN;
     end else if(cache_ready && patch_valid)begin
      if(patch_addr>=230400 || (display_valid &&
          ((active_slot && patch_addr>=115200)||(!active_slot && patch_addr<115200))))error<=7;
      else begin owner<=PATCH;address<={patch_addr[20:2],2'b00};patch_lane<=0;state<=PATCH_RUN;end
     end
    end
   end
   VIDEO_CLEAR:begin
    clear_count<=clear_count+1'b1;
    if(clear_count==3)video_reset<=0;
    if(clear_count==7)state<=IDLE;
   end
   COMMAND_CLEAR:begin
    clear_count<=clear_count+1'b1;
    if(clear_count==3)stream_reset<=0;
    if(clear_count==7)begin state<=IDLE;stream_ack<=1;end
   end
   READ_RUN:begin
    address<=address+1'b1;left<=left-1'b1;
    if(left==1)begin state<=READ_DRAIN;quiet<=0;end
   end
   READ_DRAIN:begin
    if(rd_valid)quiet<=0;else if(quiet<10)quiet<=quiet+1'b1;
    else if(!busy && !refreshing)begin
     if(responses!=expected)error<=6;
     else if(RUN_BUS_TEST && owner==TEST)begin
      if(!test_bad)test_done<=1;
      else if(test_zero)error<=14;
      else if(test_ones)error<=15;
      else if(test_late)error<=12;
      else if(test_early)error<=13;
      else error<=11;
     end else if(owner==VERIFY && verify_remaining==0)begin
      if((verify_crc^32'hffffffff)==payload_crc)cache_ready<=1;
      else error<=9;
     end
     state<=IDLE;
    end
   end
   UPLOAD_RUN:begin
    if(up_empty)error<=8;
    else begin
     upload_written<=upload_written+1'b1;left<=left-1'b1;
     if(left==1)begin state<=WRITE_DRAIN;quiet<=0;end
    end
   end
   PATCH_RUN:begin
    patch_lane<=patch_lane+1'b1;
    if(patch_lane==3)begin state<=WRITE_DRAIN;quiet<=0;end
   end
   TEST_WRITE:begin
    test_written<=test_written+1'b1;
    if(test_written==63)begin state<=WRITE_DRAIN;quiet<=0;end
   end
   WRITE_DRAIN:begin
    if(quiet<10)quiet<=quiet+1'b1;
    else if(!busy && !refreshing)begin
     if(owner==TEST)test_written_done<=1;
     state<=IDLE;
    end
   end
   PATCH_ACK:state<=IDLE;
  endcase
 end
end
endmodule
