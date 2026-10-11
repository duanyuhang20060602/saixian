module top(
 input clk,input [3:0] key,input [1:0] sw,input hdmi_hpd,
 output [3:0] led,output [5:0] seg_sel,output [7:0] seg_data,
 output HDMI_CLK_P,output HDMI_D2_P,output HDMI_D1_P,output HDMI_D0_P,
 output HDMI_DDC_SCL,inout HDMI_DDC_SDA,
 output sd_ncs,output sd_dclk,output sd_mosi,input sd_miso,
 input hmi_uart_rx,output hmi_uart_tx
);
wire sd_card_clk,ext_mem_clk,ext_mem_clk_sft,video_clk,hdmi_5x_clk,sys_lock,video_lock;
sys_pll u_sys_pll(clk,1'b0,sd_card_clk,ext_mem_clk,ext_mem_clk_sft,sys_lock);
video_pll u_video_pll(clk,1'b0,video_clk,hdmi_5x_clk,video_lock);
reg [22:0] por_count=0;
always @(posedge clk)if(!por_count[22])por_count<=por_count+1'b1;
wire reset_request=!por_count[22] || !sys_lock || !video_lock;
reg [2:0] sd_reset=7,mem_reset=7,video_reset=7,hdmi_reset=7;
always @(posedge sd_card_clk or posedge reset_request)
 if(reset_request)sd_reset<=7;else sd_reset<={sd_reset[1:0],1'b0};
always @(posedge ext_mem_clk or posedge reset_request)
 if(reset_request)mem_reset<=7;else mem_reset<={mem_reset[1:0],1'b0};
always @(posedge video_clk or posedge reset_request)
 if(reset_request)video_reset<=7;else video_reset<={video_reset[1:0],1'b0};
always @(posedge hdmi_5x_clk or posedge reset_request)
 if(reset_request)hdmi_reset<=7;else hdmi_reset<={hdmi_reset[1:0],1'b0};
wire rst_mem=mem_reset[2],rst_video=video_reset[2];
reg [26:0] sd_hold=0;reg sd_hold_done=0;
always @(posedge sd_card_clk)begin
 if(sd_reset[2])begin sd_hold<=0;sd_hold_done<=0;end
 else if(!sd_hold_done)begin
  sd_hold<=sd_hold+1'b1;
  if(sd_hold==99999999)sd_hold_done<=1;
 end
end
wire rst_sd=sd_reset[2] || !sd_hold_done;
wire sd_init,sec_req,sec_valid,sec_end;wire [31:0] sec_addr;wire [7:0] sec_data;
wire [2:0] sd_init_stage;
sd_card_top #(.SPI_LOW_SPEED_DIV(248),.SPI_HIGH_SPEED_DIV(2)) sd_host(
 .clk(sd_card_clk),.rst(rst_sd),.SD_nCS(sd_ncs),.SD_DCLK(sd_dclk),.SD_MOSI(sd_mosi),.SD_MISO(sd_miso),
  .sd_init_done(sd_init),.init_stage(sd_init_stage),.sd_sec_read(sec_req),.sd_sec_read_addr(sec_addr),
 .sd_sec_read_data(sec_data),.sd_sec_read_data_valid(sec_valid),.sd_sec_read_end(sec_end),
 .sd_sec_write(1'b0),.sd_sec_write_addr(32'd0),.sd_sec_write_data(8'd0),.sd_sec_write_data_req(),.sd_sec_write_end());
wire upload_we,upload_full,upload_empty,upload_pop,upload_done;
wire [31:0] upload_data,upload_head;wire [8:0] upload_count;
wire [20:0] file_words_sd;wire [5:0] frame_count_sd;wire [2:0] sd_error;
wire [31:0] payload_crc_sd;reg [31:0] payload_crc_meta,payload_crc_sync;
delta_loader #(.WIDTH(1280),.HEIGHT(720),.FORMAT_VERSION(3)) loader(sd_card_clk,rst_sd,sd_init,sec_req,sec_addr,sec_valid,sec_data,sec_end,upload_full,
  upload_we,upload_data,upload_done,file_words_sd,frame_count_sd,sd_error,,payload_crc_sd);
wfifo_32_32_512 upload_fifo(.rst(rst_sd|rst_mem),.clkw(sd_card_clk),.clkr(ext_mem_clk),
 .we(upload_we),.di(upload_data),.re(upload_pop),.dout(upload_head),.full_flag(upload_full),
 .empty_flag(upload_empty),.rdusedw(upload_count),.wrusedw(),.valid(),.afull(),.aempty());
(* async_reg="true",keep="true" *)reg upload_done_meta,upload_done_sync;
reg [20:0] file_words_meta,file_words_sync;reg [5:0] frame_count_meta,frame_count_sync;
always @(posedge ext_mem_clk)begin
 if(rst_mem)begin upload_done_meta<=0;upload_done_sync<=0;file_words_meta<=0;file_words_sync<=0;
   frame_count_meta<=0;frame_count_sync<=0;payload_crc_meta<=0;payload_crc_sync<=0;end
 else begin upload_done_meta<=upload_done;upload_done_sync<=upload_done_meta;
  file_words_meta<=file_words_sd;file_words_sync<=file_words_meta;
   frame_count_meta<=frame_count_sd;frame_count_sync<=frame_count_meta;
   payload_crc_meta<=payload_crc_sd;payload_crc_sync<=payload_crc_meta;end
end
wire app_rd,app_wr,sdr_init,sdr_ref,sdr_busy,sdr_valid;
wire [20:0] rd_addr,wr_addr;wire [31:0] rd_data,wr_data;
wire [3:0] wr_dm;
wire [31:0] captured_rd_data;
delta_read_capture read_capture(ext_mem_clk,rst_mem,rd_data,captured_rd_data);
sdram u_sdram(ext_mem_clk,ext_mem_clk_sft,rst_mem,sdr_init,sdr_ref,sdr_busy,
 app_wr,wr_addr,wr_dm,wr_data,app_rd,rd_addr,sdr_valid,rd_data);
wire cache_ready,video_fifo_reset,video_push;wire [31:0] video_data,video_head;
wire [8:0] video_count;wire video_empty,video_full;
wire stream_start,stream_ack,stream_reset,cmd_push,cmd_pop,cmd_empty;wire [31:0] cmd_data,cmd_head;
wire [8:0] cmd_count;wire [20:0] stream_offset,stream_words;
wire patch_valid,patch_ready,patch_drained;wire [20:0] patch_addr;wire [31:0] patch_data;
wire [3:0] memory_error,player_error;wire [31:0] late_count;wire [159:0] memory_debug;
wire [191:0] player_debug;
wire publish_toggle,publish_slot,commit_toggle,frame_toggle,active_slot,display_valid;
(* async_reg="true",keep="true" *)reg [2:0] frame_sync,commit_sync;
(* async_reg="true",keep="true" *)reg active_meta,active_sync,display_meta,display_sync,pause_meta,pause_sync;
always @(posedge ext_mem_clk)begin
 if(rst_mem)begin frame_sync<=0;commit_sync<=0;active_meta<=0;active_sync<=0;
  display_meta<=0;display_sync<=0;pause_meta<=0;pause_sync<=0;end
 else begin frame_sync<={frame_sync[1:0],frame_toggle};commit_sync<={commit_sync[1:0],commit_toggle};
  active_meta<=active_slot;active_sync<=active_meta;display_meta<=display_valid;display_sync<=display_meta;
  pause_meta<=sw[0];pause_sync<=pause_meta;end
end
delta_memory #(.VERIFY_CACHE(1),.FRAME_WORDS(460800)) memory_bus(ext_mem_clk,rst_mem,sdr_init,sdr_ref,sdr_busy,
 app_rd,rd_addr,sdr_valid,captured_rd_data,app_wr,wr_addr,wr_data,
 upload_done_sync,file_words_sync,upload_empty,upload_count,upload_head,upload_pop,cache_ready,
 frame_sync[2],display_sync,active_sync,video_fifo_reset,video_push,video_data,video_count,
 stream_start,stream_offset,stream_words,stream_ack,stream_reset,cmd_push,cmd_data,cmd_count,
  patch_valid,patch_addr,patch_data,patch_ready,memory_error,,payload_crc_sync,memory_debug,wr_dm,patch_drained);
wfifo_32_32_512 command_fifo(.rst(rst_mem|stream_reset),.clkw(ext_mem_clk),.clkr(ext_mem_clk),
 .we(cmd_push),.di(cmd_data),.re(cmd_pop),.dout(cmd_head),.full_flag(),.empty_flag(cmd_empty),
 .rdusedw(cmd_count),.wrusedw(),.valid(),.afull(),.aempty());
delta_player #(.FRAME_WORDS(460800),.INITIAL_HOLD_TICKS(50000000),.VERIFY_STREAM(1),.WAIT_PATCH_DRAIN(1)) player(ext_mem_clk,rst_mem,cache_ready,file_words_sync,frame_count_sync,
 stream_start,stream_offset,stream_words,stream_ack,cmd_head,!cmd_empty,cmd_pop,
 patch_valid,patch_addr,patch_data,patch_ready,publish_toggle,publish_slot,commit_sync[2],pause_sync,
  player_error,late_count,,,,player_debug,patch_drained);
(* async_reg="true",keep="true" *)reg hpd_meta,hpd_sync;
always @(posedge video_clk)begin
 if(rst_video)begin hpd_meta<=0;hpd_sync<=0;end
 else begin hpd_meta<=hdmi_hpd;hpd_sync<=hpd_meta;end
end
wire video_pop,underrun_latched;wire [23:0] rgb;wire render_de,render_vs;
rfifo_32_32_512 #(.SHOW_AHEAD_EN(1'b1)) video_fifo(.rst(rst_mem|rst_video|video_fifo_reset),
 .clkw(ext_mem_clk),.clkr(video_clk),.we(video_push),.di(video_data),.re(video_pop),.dout(video_head),
 .full_flag(video_full),.empty_flag(video_empty),.wrusedw(video_count),.rdusedw(),.valid(),.afull(),.aempty());
delta_video #(.SCENE_WIDTH(1280),.SCENE_HEIGHT(720),.LIVE_AWARD(1),.SHOW_BOOT_SPINNER(1),.MIN_BOOT_FRAMES(96)) video_scan(video_clk,rst_video,publish_toggle,publish_slot,video_head,video_empty,video_pop,
 rgb,render_de,render_vs,commit_toggle,frame_toggle,active_slot,display_valid,underrun_latched,sw[0]);
wire axis_user,axis_valid,axis_last,axis_ready;wire [23:0] axis_data;
video_rgb_to_axis_640x480 #(.H_ACTIVE(1280)) axis_pack(video_clk,rst_video,render_vs,render_de,rgb,
 axis_user,axis_valid,axis_last,axis_data);
reg [26:0] edid_wait;reg edid_trigger;
always @(posedge video_clk)begin
 if(rst_video)begin edid_wait<=0;edid_trigger<=0;end
 else begin edid_trigger<=0;if(!hpd_sync)edid_wait<=0;
  else if(edid_wait<75000000)edid_wait<=edid_wait+1'b1;
  else if(edid_wait==75000000)begin edid_trigger<=1;edid_wait<=edid_wait+1'b1;end
 end
end
wire [9:0] t0,t1,t2,tc;
hdmi_1_4b_transmitter_core_wrapper #(
 .DEVICE("EG"),.HTOTAL(1650),.HSA(40),.HFP(110),.HBP(220),.HACTIVE(1280),
 .VTOTAL(750),.VSA(5),.VFP(5),.VBP(20),.VACTIVE(720),.VIDEO_VIC(4),
 .VIDEO_TPG("Disable"),.VIDEO_FORMAT("RGB"),.AUDIO_SAMPLE_RATE("48K"),.IIC_SCL_DIV(375)
) u_hdmi_tx(
 .I_pixel_clk(video_clk),.I_rst(rst_video),.I_edid_read_trig(edid_trigger),.O_edid_read_valid(),.O_edid_read_data(),
 .I_axis_s_user(axis_user),.I_axis_s_valid(axis_valid),.I_axis_s_last(axis_last),.I_axis_s_data(axis_data),.O_axis_s_ready(axis_ready),
 .I_audio_valid(1'b0),.I_audio_left_data(24'd0),.I_audio_right_data(24'd0),.I_acr_valid(1'b0),.I_acr_cts(20'd0),.I_acr_n(20'd0),
 .O_video_locked(),.O_ddc_scl(HDMI_DDC_SCL),.IO_ddc_sda(HDMI_DDC_SDA),
 .O_ch0_tmds_data(t0),.O_ch1_tmds_data(t1),.O_ch2_tmds_data(t2),.O_clk_tmds_data(tc));
hdmi_phy_wrapper #(.DEVICE("EG")) u_hdmi_phy(video_clk,hdmi_5x_clk,hdmi_reset[2],t0,t1,t2,tc,
 HDMI_D0_P,HDMI_D1_P,HDMI_D2_P,HDMI_CLK_P);
assign led={sd_error!=0 || memory_error!=0 || player_error!=0 || underrun_latched,hpd_sync,sd_init,display_valid};
 delta_status diagnostics(clk,reset_request,sd_error,sd_init_stage,memory_error,player_error,underrun_latched,seg_sel,seg_data,
  sw[1],key[0],player_error!=0 && memory_error==0 && sd_error==0 ? player_debug : {payload_crc_sync,memory_debug});
 assign hmi_uart_tx=1'b1;
endmodule
