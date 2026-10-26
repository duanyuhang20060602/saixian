// Integrates the 20261010 QuadWrite player without a second SDRAM controller.
// Upload/video FIFOs are owned exclusively and reused from frame_read_write.
module saixian_tf_animation #(parameter EXTERNAL_SD_HOST=0)(
 input sd_clk,mem_clk,video_clk,input rst_sd,rst_mem,rst_video,input active,
 output mode_sd,mode_mem,output photo_reset_sd,photo_reset_video,output memory_reset,
 output sd_cs,sd_sck,sd_mosi,input sd_miso,
 output shared_sd_reset,sector_req,output [31:0] sector_addr,
 input shared_sd_initialized,input [7:0] sector_data,input sector_valid,sector_end,
 input sdr_init,sdr_refresh,sdr_busy,input rd_valid,input [31:0] rd_data,
 output app_rd,output [20:0] rd_addr,output app_wr,output [20:0] wr_addr,
 output [31:0] wr_data,output [3:0] wr_dm,
 output upload_reset,upload_we,output [31:0] upload_data,input upload_full,
 input upload_empty,input [8:0] upload_count,input [31:0] upload_head,output upload_pop,
 output video_reset,video_push,output [31:0] video_data,input [8:0] video_count,
 input [31:0] video_head,input video_empty,output video_pop,
 output [23:0] rgb,output de,vs,frame_tick,output initialized,visible,
 output [2:0] sd_error,output [3:0] memory_error,player_error,output underflow
);
wire sd_handoff,mem_handoff;
saixian_media_handoff sd_owner(sd_clk,rst_sd,active,mode_sd,sd_handoff);
saixian_media_handoff mem_owner(mem_clk,rst_mem,active,mode_mem,mem_handoff);
wire delta_rst_sd=rst_sd || !mode_sd || sd_handoff;
wire delta_rst_mem=rst_mem || !mode_mem || mem_handoff;
wire delta_rst_video=rst_video || !active;
assign photo_reset_sd=rst_sd || mode_sd || sd_handoff;
assign photo_reset_video=rst_video || active;
assign memory_reset=rst_mem || mem_handoff;
assign upload_reset=delta_rst_sd || delta_rst_mem;
wire sec_req,sec_valid,sec_end;wire [31:0] sec_addr;wire [7:0] sec_data;
assign shared_sd_reset=rst_sd || sd_handoff;
assign sector_req=sec_req;assign sector_addr=sec_addr;
generate if(EXTERNAL_SD_HOST)begin:shared_host
 assign initialized=shared_sd_initialized;
 assign sec_data=sector_data;assign sec_valid=sector_valid;assign sec_end=sector_end;
 assign sd_cs=1'b1;assign sd_sck=1'b0;assign sd_mosi=1'b1;
end else begin:private_host
sd_card_top #(.SPI_LOW_SPEED_DIV(248),.SPI_HIGH_SPEED_DIV(2)) sd_host(
 .clk(sd_clk),.rst(delta_rst_sd),.SD_nCS(sd_cs),.SD_DCLK(sd_sck),.SD_MOSI(sd_mosi),.SD_MISO(sd_miso),
 .sd_init_done(initialized),.init_stage(),.sd_sec_read(sec_req),.sd_sec_read_addr(sec_addr),
 .sd_sec_read_data(sec_data),.sd_sec_read_data_valid(sec_valid),.sd_sec_read_end(sec_end),
 .sd_sec_write(1'b0),.sd_sec_write_addr(32'd0),.sd_sec_write_data(8'd0),.sd_sec_write_data_req(),.sd_sec_write_end());
end endgenerate
wire upload_done;wire [20:0] file_words_sd;wire [5:0] frame_count_sd;wire [31:0] payload_crc_sd;
delta_loader loader(sd_clk,delta_rst_sd,initialized,sec_req,sec_addr,sec_valid,sec_data,sec_end,
 upload_full,upload_we,upload_data,upload_done,file_words_sd,frame_count_sd,sd_error,,payload_crc_sd,1'b0,32'd0);
(* async_reg="true",keep="true" *) reg done_meta,done_sync;
reg [20:0] words_meta,words_sync;reg [5:0] frames_meta,frames_sync;
reg [31:0] crc_meta,crc_sync;
wire publish,publish_slot,commit,frame,active_slot;
(* async_reg="true",keep="true" *) reg [2:0] frame_sync,commit_sync;
(* async_reg="true",keep="true" *) reg active_meta,active_sync,visible_meta,visible_sync;
always @(posedge mem_clk)begin
 if(delta_rst_mem)begin
  done_meta<=0;done_sync<=0;words_meta<=0;words_sync<=0;frames_meta<=0;frames_sync<=0;
  crc_meta<=0;crc_sync<=0;frame_sync<=0;commit_sync<=0;
  active_meta<=0;active_sync<=0;visible_meta<=0;visible_sync<=0;
 end else begin
  done_meta<=upload_done;done_sync<=done_meta;words_meta<=file_words_sd;words_sync<=words_meta;
  frames_meta<=frame_count_sd;frames_sync<=frames_meta;crc_meta<=payload_crc_sd;crc_sync<=crc_meta;
  frame_sync<={frame_sync[1:0],frame};commit_sync<={commit_sync[1:0],commit};
  active_meta<=active_slot;active_sync<=active_meta;visible_meta<=visible;visible_sync<=visible_meta;
 end
end
wire [31:0] captured_data;
delta_read_capture capture(mem_clk,delta_rst_mem,rd_data,captured_data);
wire cache_ready,stream_start,stream_ack,stream_reset,cmd_push,cmd_pop,cmd_empty;
wire [31:0] cmd_data,cmd_head;wire [8:0] cmd_count;
wire [20:0] stream_offset,stream_words,patch_addr;wire [31:0] patch_data;
wire patch_valid,patch_ready,patch_drained,bus_video_reset;
delta_memory #(.VERIFY_CACHE(1),.RUN_BUS_TEST(0)) memory_bus(mem_clk,delta_rst_mem,sdr_init,sdr_refresh,sdr_busy,
 app_rd,rd_addr,rd_valid,captured_data,app_wr,wr_addr,wr_data,
 done_sync,words_sync,upload_empty,upload_count,upload_head,upload_pop,cache_ready,
 frame_sync[2],visible_sync,active_sync,bus_video_reset,video_push,video_data,video_count,
 stream_start,stream_offset,stream_words,stream_ack,stream_reset,cmd_push,cmd_data,cmd_count,
 patch_valid,patch_addr,patch_data,patch_ready,memory_error,,crc_sync,,wr_dm,patch_drained);
assign video_reset=delta_rst_mem || delta_rst_video || bus_video_reset;
// Only one additional RAM FIFO: maximum command occupancy is 128+64 words.
wire [7:0] command_count;
assign cmd_count={1'b0,command_count};
wfifo_32_32_512 #(.ADDR_WIDTH_W(8),.ADDR_WIDTH_R(8),.AL_FULL_NUM(253)) command_fifo(
 .rst(delta_rst_mem|stream_reset),.clkw(mem_clk),.clkr(mem_clk),.we(cmd_push),.di(cmd_data),
 .re(cmd_pop),.dout(cmd_head),.full_flag(),.empty_flag(cmd_empty),.rdusedw(command_count),
 .wrusedw(),.valid(),.afull(),.aempty());
delta_player #(.INITIAL_HOLD_TICKS(0),.VERIFY_STREAM(1),.WAIT_PATCH_DRAIN(1)) player(
 mem_clk,delta_rst_mem,cache_ready,words_sync,frames_sync,stream_start,stream_offset,stream_words,
 stream_ack,cmd_head,!cmd_empty,cmd_pop,patch_valid,patch_addr,patch_data,patch_ready,
 publish,publish_slot,commit_sync[2],1'b0,player_error,,,,,,patch_drained);
delta_video #(.SHOW_BOOT_SPINNER(0),.MIN_BOOT_FRAMES(0)) video_scan(
 video_clk,delta_rst_video,publish,publish_slot,video_head,video_empty,video_pop,
 rgb,de,vs,commit,frame,active_slot,visible,underflow,frame_tick,1'b1,11'd0,10'd0,1'b0,1'b0,1'b0);
endmodule

// Mode is a stable level, sampled through three destination clock edges.
// Both clients and the shared SDRAM controller reset across every handoff.
module saixian_media_handoff(input clk,rst,request,output reg mode,output hold);
(* async_reg="true",keep="true" *) reg [2:0] mode_sync;
reg [3:0] reset_count;
// Assert on the original request immediately: SD must not clear the upload
// FIFO a destination clock earlier than the memory client's cancellation.
// Release still waits for the synchronized mode and 15 destination clocks.
assign hold=rst || request!=mode || mode_sync[2]!=mode || reset_count!=0;
always @(posedge clk or posedge rst)begin
 if(rst)begin mode_sync<=0;mode<=0;reset_count<=15;end
 else begin
  mode_sync<={mode_sync[1:0],request};
  if(mode_sync[2]!=mode)begin mode<=mode_sync[2];reset_count<=15;end
  else if(reset_count!=0)reset_count<=reset_count-1'b1;
 end
end
endmodule
