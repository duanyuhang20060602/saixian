// Permanent SDRAM partition: photos 0..1382399; TF 1382400..2097151.
// The host and upload FIFO are leased only at a completed photo transaction.
// A successful file remains cached across playback exits; the player alone
// restarts to prepare frame zero again while the next result is showing.
module saixian_tf_preload #(
 parameter BASE_ADDR=1382400,parameter MAX_FILE_BYTES=1937408
)(
 input sd_clk,mem_clk,video_clk,input rst_sd,rst_mem,rst_video,
 input prepare,active,show,input photo_idle,photo_bus_claim,
 input shared_sd_initialized,input [7:0] sector_data,input sector_valid,sector_end,
 input [31:0] observed_sector,
 output shared_sd_reset,sector_req,output [31:0] sector_addr,
 output mode_sd,mode_mem,photo_reset_sd,photo_reset_video,memory_reset,photo_pause,
 input sdr_init,sdr_refresh,sdr_busy,input rd_valid,input [31:0] rd_data,
 output app_rd,output [20:0] rd_addr,output app_wr,output [20:0] wr_addr,
 output [31:0] wr_data,output [3:0] wr_dm,
 output upload_reset,upload_we,output [31:0] upload_data,input upload_full,
 input upload_empty,input [8:0] upload_count,input [31:0] upload_head,output upload_pop,
 output video_reset,video_push,output [31:0] video_data,video_head,
 output [8:0] video_count,output video_empty,video_pop,
 input [10:0] raster_x,input [9:0] raster_y,input raster_de,raster_vs,raster_frame,
 output [23:0] rgb,output de,vs,frame_tick,initialized,visible,
 output [2:0] sd_error,output [3:0] memory_error,player_error,output underflow
);
(* async_reg="true",keep="true" *) reg [2:0] prepare_sd,prepare_mem,show_mem;
(* async_reg="true",keep="true" *) reg [2:0] session_mem,cache_sd,idle_sd,busy_sd;
(* async_reg="true",keep="true" *) reg [2:0] active_mem;
reg active_seen;reg [3:0] restart_count;
reg session,upload_owner;
reg had_sd_init,had_mem_init,had_video_init;
(* async_reg="true",keep="true" *) reg [2:0] initialized_mem,initialized_video;
wire bus_idle,cache_ready,upload_done,local_clear;
wire session_rst_sd=rst_sd || !session;
wire session_rst_mem=memory_reset || !session_mem[2];
wire player_rst=session_rst_mem || !prepare_mem[2] || restart_count!=0;
reg [5:0] failed_quiet;
wire failed=sd_error!=0 || memory_error!=0;
assign photo_pause=prepare_sd[2] || upload_owner;
assign mode_sd=upload_owner;
// Local FIFO clears may overlap outstanding photo reads and responses.
assign mode_mem=session_mem[2] && !bus_idle && !local_clear;
// Only a real host reset/card fault invalidates metadata and cancels the
// physical bus. Ordinary entry, exit and preload never reset these clients.
assign photo_reset_sd=rst_sd || (had_sd_init && !shared_sd_initialized);
assign photo_reset_video=rst_video || (had_video_init && !initialized_video[2]);
assign memory_reset=rst_mem || (had_mem_init && !initialized_mem[2]);
assign shared_sd_reset=rst_sd;
assign initialized=shared_sd_initialized;
assign upload_reset=session_rst_sd || session_rst_mem;
always @(posedge sd_clk or posedge rst_sd) begin
 if(rst_sd)begin
  prepare_sd<=0;cache_sd<=0;idle_sd<=0;busy_sd<=0;
  session<=0;upload_owner<=0;failed_quiet<=0;had_sd_init<=0;
 end else begin
  prepare_sd<={prepare_sd[1:0],prepare};cache_sd<={cache_sd[1:0],cache_ready};
  if(shared_sd_initialized)had_sd_init<=1;
  idle_sd<={idle_sd[1:0],bus_idle};busy_sd<={busy_sd[1:0],sdr_busy};
  if(failed && !busy_sd[2])begin if(failed_quiet!=63)failed_quiet<=failed_quiet+1'b1;end
  else failed_quiet<=0;
  if(!session && prepare_sd[2] && photo_idle && shared_sd_initialized)begin session<=1;upload_owner<=1;end
  if(upload_owner && cache_sd[2] && idle_sd[2])upload_owner<=0;
  // Errors never publish a frame. Keep the retained photograph, then permit
  // a fresh attempt after the result is cancelled and all bus beats drain.
  if(session && failed && !prepare_sd[2] && failed_quiet==63)begin session<=0;upload_owner<=0;end
  if(!shared_sd_initialized)begin session<=0;upload_owner<=0;end
 end
end
always @(posedge mem_clk or posedge rst_mem)begin
 if(rst_mem)begin session_mem<=0;prepare_mem<=0;show_mem<=0;active_mem<=0;active_seen<=0;restart_count<=0;initialized_mem<=0;had_mem_init<=0;end
 else begin
  session_mem<={session_mem[1:0],session};prepare_mem<={prepare_mem[1:0],prepare};show_mem<={show_mem[1:0],show};
  active_mem<={active_mem[1:0],active};active_seen<=active_mem[2];
  initialized_mem<={initialized_mem[1:0],shared_sd_initialized};
  if(initialized_mem[2])had_mem_init<=1;
  if(active_seen && !active_mem[2])restart_count<=15;
  else if(restart_count!=0)restart_count<=restart_count-1'b1;
 end
end
always @(posedge video_clk or posedge rst_video)begin
 if(rst_video)begin initialized_video<=0;had_video_init<=0;end
 else begin initialized_video<={initialized_video[1:0],shared_sd_initialized};if(initialized_video[2])had_video_init<=1;end
end

// Learn the DLT start sector while the normal boot scan crosses its header.
// The loader validates every header field and CRC before trusting this hint.
reg [9:0] observed_byte;
reg magic_match,hint_valid;reg [31:0] hint_sector;
function [7:0] magic_byte;
 input [2:0] n;
 begin case(n)0:magic_byte="S";1:magic_byte="X";2:magic_byte="D";3:magic_byte="L";
 4:magic_byte="T";5,6:magic_byte="0";default:magic_byte="1";endcase end
endfunction
always @(posedge sd_clk or posedge rst_sd)begin
 if(rst_sd)begin observed_byte<=0;magic_match<=0;hint_valid<=0;hint_sector<=0;end
 else begin
  if(sector_valid && !upload_owner)begin
   if(observed_byte==0)magic_match<=sector_data==magic_byte(0);
   else if(observed_byte<8)magic_match<=magic_match && sector_data==magic_byte(observed_byte[2:0]);
   observed_byte<=observed_byte+1'b1;
  end
  if(sector_end)begin
   if(!upload_owner && !hint_valid && observed_byte==512 && magic_match)begin hint_valid<=1;hint_sector<=observed_sector;end
   observed_byte<=0;
  end
  if(!shared_sd_initialized)begin hint_valid<=0;observed_byte<=0;end
 end
end
wire [20:0] file_words_sd;wire [5:0] frame_count_sd;wire [31:0] payload_crc_sd;
delta_loader #(.MAX_FILE_BYTES(MAX_FILE_BYTES),.USE_START_HINT(1),.SKIP_KNOWN_MEDIA(1)) loader(
 sd_clk,session_rst_sd,shared_sd_initialized,sector_req,sector_addr,
 sector_valid && upload_owner,sector_data,sector_end && upload_owner,
 upload_full,upload_we,upload_data,upload_done,file_words_sd,frame_count_sd,sd_error,,payload_crc_sd,hint_valid,hint_sector);
(* async_reg="true",keep="true" *) reg done_meta,done_sync;
reg [20:0] words_meta,words_sync;reg [5:0] frames_meta,frames_sync;reg [31:0] crc_meta,crc_sync;
(* async_reg="true",keep="true" *) reg [2:0] frame_sync,commit_sync;
(* async_reg="true",keep="true" *) reg active_meta,active_sync,visible_meta,visible_sync;
wire publish,publish_slot,commit,frame,active_slot;
always @(posedge mem_clk)begin
 if(session_rst_mem)begin
  done_meta<=0;done_sync<=0;words_meta<=0;words_sync<=0;frames_meta<=0;frames_sync<=0;
  crc_meta<=0;crc_sync<=0;frame_sync<=0;commit_sync<=0;
  active_meta<=0;active_sync<=0;visible_meta<=0;visible_sync<=0;
 end else begin
  done_meta<=upload_done;done_sync<=done_meta;words_meta<=file_words_sd;words_sync<=words_meta;
  frames_meta<=frame_count_sd;frames_sync<=frames_meta;crc_meta<=payload_crc_sd;crc_sync<=crc_meta;
  frame_sync<={frame_sync[1:0],frame};commit_sync<={commit_sync[1:0],commit};
  active_meta<=active_slot;active_sync<=active_meta;visible_meta<=visible && active;visible_sync<=visible_meta;
 end
end
wire [31:0] captured_data;
delta_read_capture capture(mem_clk,session_rst_mem,rd_data,captured_data);
wire stream_start,stream_ack,stream_reset,cmd_push,cmd_pop,cmd_empty;
wire [31:0] cmd_data,cmd_head,patch_data;wire [8:0] cmd_count;
wire [20:0] stream_offset,stream_words,patch_addr;
wire patch_valid,patch_ready,patch_drained,bus_video_reset;
delta_memory #(.VERIFY_CACHE(1),.RUN_BUS_TEST(0),.BASE_ADDR(BASE_ADDR),.VIDEO_REFILL_LIMIT(96)) memory_bus(
 mem_clk,session_rst_mem,sdr_init,sdr_refresh,sdr_busy || (bus_idle && photo_bus_claim),
 app_rd,rd_addr,rd_valid,captured_data,app_wr,wr_addr,wr_data,
 done_sync,words_sync,!upload_owner || upload_empty,upload_count,upload_head,upload_pop,cache_ready,
 frame_sync[2],visible_sync,active_sync,bus_video_reset,video_push,video_data,video_count,
 stream_start,stream_offset,stream_words,stream_ack,stream_reset,cmd_push,cmd_data,cmd_count,
 patch_valid,patch_addr,patch_data,patch_ready,memory_error,bus_idle,crc_sync,,wr_dm,patch_drained,local_clear);
assign video_reset=session_rst_mem || rst_video || bus_video_reset;
wire [7:0] command_count,scan_count;
assign cmd_count={1'b0,command_count};assign video_count={1'b0,scan_count};
wfifo_32_32_512 #(.ADDR_WIDTH_W(8),.ADDR_WIDTH_R(8),.AL_FULL_NUM(253)) command_fifo(
 .rst(session_rst_mem|stream_reset),.clkw(mem_clk),.clkr(mem_clk),.we(cmd_push),.di(cmd_data),
 .re(cmd_pop),.dout(cmd_head),.empty_flag(cmd_empty),.rdusedw(command_count));
saixian_shared_video_fifo #(.ADDR_WIDTH_W(8),.ADDR_WIDTH_R(8),.AL_FULL_NUM(253)) scan_fifo(
 .read_ahead(1'b1),.rst(video_reset),.clkw(mem_clk),.clkr(video_clk),.we(video_push),.di(video_data),
 .re(video_pop),.dout(video_head),.empty_flag(video_empty),.wrusedw(scan_count));
delta_player #(.INITIAL_HOLD_TICKS(0),.VERIFY_STREAM(1),.WAIT_PATCH_DRAIN(1)) player(
 mem_clk,player_rst,cache_ready,words_sync,frames_sync,stream_start,stream_offset,stream_words,
 stream_ack,cmd_head,!cmd_empty,cmd_pop,patch_valid,patch_addr,patch_data,patch_ready,
 publish,publish_slot,commit_sync[2],!show_mem[2],player_error,,,,,,patch_drained);
delta_video #(.SHOW_BOOT_SPINNER(0),.MIN_BOOT_FRAMES(0),.CONTROLLED_PRESENTATION(1),.EXTERNAL_TIMING(1)) video_scan(
 video_clk,photo_reset_video,publish,publish_slot,video_head,video_empty,video_pop,
 rgb,de,vs,commit,frame,active_slot,visible,underflow,frame_tick,
 active,raster_x,raster_y,raster_de,raster_vs,raster_frame);
endmodule
