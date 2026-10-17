// Updated by prepare_assets.py for the selected music; zero accepts all AUDs.
module top_water_single #(parameter SELECTED_AUDIO_BYTES=32'd35230400)(input clk,input[3:0] key,input[1:0] sw,input hdmi_hpd,
 output[3:0] led,output[5:0] seg_sel,output[7:0] seg_data,
 output HDMI_CLK_P,HDMI_D2_P,HDMI_D1_P,HDMI_D0_P,HDMI_DDC_SCL,inout HDMI_DDC_SDA,
 output sd_ncs,sd_dclk,sd_mosi,input sd_miso);
wire sd_clk,mem_clk,mem_shift,pixel_clk,serial_clk,sys_lock,vid_lock;
water_sys_pll sys(.refclk(clk),.reset(1'b0),.clk0_out(sd_clk),.clk1_out(mem_clk),.clk2_out(mem_shift),.locked(sys_lock));
fluid_video_pll video(.refclk(clk),.reset(1'b0),.clk0_out(pixel_clk),.clk1_out(serial_clk),.locked(vid_lock));
wire rs,rm,rp,rt;wire ar=!sys_lock||!vid_lock;
saixian_reset_sync reset_sd(.clk(sd_clk),.arst(ar),.rst(rs));
saixian_reset_sync reset_mem(.clk(mem_clk),.arst(ar),.rst(rm));
saixian_reset_sync reset_pixel(.clk(pixel_clk),.arst(ar),.rst(rp));
saixian_reset_sync reset_serial(.clk(serial_clk),.arst(ar),.rst(rt));
// Register reset release; do not drive the media's asynchronous resets through
// a wide startup-counter comparator and high-fanout combinational logic.
reg[25:0] startup;reg media_reset;
always @(posedge sd_clk)begin
 if(rs)begin startup<=0;media_reset<=1;end
 else if(startup<50000000)begin startup<=startup+1'b1;media_reset<=1;end
 else media_reset<=0;
end
wire[3:0] press;genvar k;generate for(k=0;k<4;k=k+1)begin:keys
 saixian_key_debounce #(.CLK_FREQ_HZ(75000000)) debounce(.clk(pixel_clk),.rst(rp),.key_n(key[k]),.press_pulse(press[k]));
end endgenerate
wire drop_short,audio_mode_cycle;
saixian_key_short_long #(.CLK_FREQ_HZ(75000000)) audio_key(.clk(pixel_clk),.rst(rp),.key_n(key[1]),.press_pulse(press[1]),.short_pulse(drop_short),.long_pulse(audio_mode_cycle));
reg prev_toggle,next_toggle,waves;
(* async_reg="true" *)reg[1:0] sw_meta,sw_sync;
always @(posedge pixel_clk)begin
 if(rp)begin prev_toggle<=0;next_toggle<=0;waves<=1;sw_meta<=0;sw_sync<=0;end
 else begin
  sw_meta<=sw;sw_sync<=sw_meta;
  if(press[0])waves<=~waves;
  if(press[2])prev_toggle<=~prev_toggle;
  if(press[3])next_toggle<=~next_toggle;
 end
end
reg[11:0] x;reg[9:0] y;reg read_req;reg ack0,ack1;
wire read_ack;wire frame_tick=x==0&&y==720;
// Keep the approved wave and transition durations at approximately 30 updates
// per second while HDMI scans at approximately 60 frames per second.
reg animation_phase;
always @(posedge pixel_clk)if(rp)animation_phase<=0;else if(frame_tick)animation_phase<=~animation_phase;
wire animation_tick=frame_tick&&!animation_phase;
wire raw_de=x<1280&&y<720&&!rp;
wire vs=y>=725&&y<730;
always @(posedge pixel_clk)begin
 if(rp)begin x<=0;y<=720;read_req<=0;ack0<=0;ack1<=0;end
 else begin
  ack0<=read_ack;ack1<=ack0;
  if(x==1649)begin x<=0;y<=y==749 ? 0:y+1'b1;end else x<=x+1'b1;
  // One cycle after the scene/transition snapshot has updated in blanking.
  if(x==4&&y==720)read_req<=1;else if(ack1)read_req<=0;
 end
end
wire ready_toggle,ready_right,commit,display_valid,transition_active,slide_right;
wire[1:0] ready_buf,write_buf,active_buf,new_buf;
wire[3:0] effect;wire[10:0] offset;wire[5:0] darkness;wire[8:0] progress;
water_transition transition(.clk(pixel_clk),.rst(rp),.frame_tick(animation_tick),.frame_ready_toggle(ready_toggle),
 .ready_buf_idx(ready_buf),.ready_slide_right(ready_right),.active_buf_idx(active_buf),.slide_new_buf_idx(new_buf),
 .frame_commit_toggle(commit),.display_valid(display_valid),.transition_active(transition_active),.transition_mode(effect),
 .slide_offset(offset),.slide_right(slide_right),.transition_level(darkness),.water_progress(progress));
wire[76:0] cfg;
water_scene scene(.clk(pixel_clk),.rst(rp),.frame_tick(animation_tick),.display_valid(display_valid),.transition_active(transition_active),
 .wave_enable(waves&&!sw_sync[1]),.manual_drop(drop_short),.progress(progress),.cfg(cfg));
wire write_req,write_ack,raw_write_en,write_en,write_full,write_finish,sd_ready,scan_done;
wire[31:0] raw_write_data,packed_write_data;wire packed_write_en,write_overflow,small_write_en;wire[31:0] small_write_data;
reg write_finish_toggle;
wire[2:0] image_count,error_code,track_count;wire[3:0] sd_state;
wire[15:0] source_width,source_height;wire vga,bv0,bv1;
wire audio_we,audio_found;wire[31:0] audio_word;wire[10:0] audio_used;
sd_card_bmp #(.CLK_FREQ_HZ(50000000),.SCAN_MAX_SECTOR(1048575),.SCAN_TARGET_COUNT(5),
 .NATIVE_720_ONLY(0),.FRAME_OUT_WIDTH(1280),.FRAME_OUT_HEIGHT(720),.AUDIO_FIFO_BITS(11),.AUDIO_REFILL_LEVEL(1536),.AUDIO_EXPECTED_BYTES(SELECTED_AUDIO_BYTES)) media(
 .clk(sd_clk),.rst(media_reset),.prev_req_toggle(prev_toggle),.next_req_toggle(next_toggle),.carousel_mode(1'b1),
 .display_commit_toggle(commit),.state_code(sd_state),.sd_init_done_o(sd_ready),.scan_done_o(scan_done),
 .image_count(image_count),.error_code(error_code),.source_width(source_width),.source_height(source_height),
 .frame_ready_toggle(ready_toggle),.ready_buf_idx(ready_buf),.ready_slide_right(ready_right),.write_buf_idx(write_buf),
 .write_vga(vga),.buffer0_vga(bv0),.buffer1_vga(bv1),.sprint_background_ready(),
 .bmp_width(16'd1280),.bmp_height(16'd720),.write_finish_toggle(write_finish_toggle),
 .write_req(write_req),.write_req_ack(write_ack),.write_en(raw_write_en),.write_data(raw_write_data),
 .audio_fifo_wrusedw(audio_used),.audio_pcm_we(audio_we),.audio_pcm_word(audio_word),.audio_found_o(audio_found),
 .audio_track_index(3'd0),.audio_track_toggle(1'b0),.audio_track_count_o(track_count),
 .SD_nCS(sd_ncs),.SD_DCLK(sd_dclk),.SD_MOSI(sd_mosi),.SD_MISO(sd_miso));
water_pack packer(.clk(sd_clk),.rst(rs),.write_req(write_req),.pixel_valid(raw_write_en),
 .pixel(raw_write_data[31:8]),.full(write_full),.valid(packed_write_en),.data(packed_write_data),.overflow(write_overflow),.small_valid(small_write_en),.small_data(small_write_data));
always @(posedge mem_clk)if(rm)write_finish_toggle<=0;else if(write_finish)write_finish_toggle<=~write_finish_toggle;
wire initialized,refresh,busy,app_re,sdr_valid,app_we;
wire[20:0] app_ra,app_wa;wire[31:0] sdr_data,app_wd;wire[3:0] app_mask;
wire read_enable,read_empty;wire[31:0] read_data,read_timeouts;
frame_read_write #(.WRITE_V_FLIP(1),.FRAME_WIDTH(640),.FRAME_HEIGHT(720)) frames(
 .mem_clk(mem_clk),.rst(rm),.Sdr_init_done(initialized),.Sdr_init_ref_vld(refresh),.Sdr_busy(busy),
 .App_rd_en(app_re),.App_rd_addr(app_ra),.Sdr_rd_en(sdr_valid),.Sdr_rd_dout(sdr_data),
 .read_clk(pixel_clk),.read_req(read_req),.read_req_ack(read_ack),.read_finish(),
 .read_addr_0(21'd0),.read_addr_1(21'd691200),.read_addr_2(21'd0),.read_addr_3(21'd1382400),
 .read_addr_index(active_buf),.read_len(21'd460800),.read_en(read_enable),.read_data(read_data),.read_fifo_empty(read_empty),
 .slide_active(transition_active),.slide_old_index(active_buf),.slide_new_index(new_buf),
 .slide_offset({1'b0,offset[10:1]}),.slide_right(slide_right),.transition_mode(effect),.buffer0_vga(bv0),.buffer1_vga(bv1),
 // SW2 high keeps the 640-point effect texture after every transition.
 // SW2 low restores native dwell. This isolates the two image origins on board.
 .water_cfg(cfg),.force_effect_plane(sw_sync[1]),.read_timeouts(read_timeouts),
 .App_wr_en(app_we),.App_wr_addr(app_wa),.App_wr_din(app_wd),.App_wr_dm(app_mask),
 .write_clk(sd_clk),.write_req(write_req),.write_req_ack(write_ack),.write_finish(write_finish),
 .write_addr_0(21'd0),.write_addr_1(21'd691200),.write_addr_2(21'd0),.write_addr_3(21'd1382400),
 .write_addr_index(write_buf),.write_len(21'd460800),.write_vga(1'b0),.write_en(packed_write_en),.write_data(packed_write_data),.write_fifo_full(write_full),.small_write_en(small_write_en),.small_write_data(small_write_data));
sdram memory(.Clk(mem_clk),.Clk_sft(mem_shift),.Rst(rm),.Sdr_init_done(initialized),.Sdr_init_ref_vld(refresh),.Sdr_busy(busy),
 .App_wr_en(app_we),.App_wr_addr(app_wa),.App_wr_dm(app_mask),.App_wr_din(app_wd),
 .App_rd_en(app_re),.App_rd_addr(app_ra),.Sdr_rd_en(sdr_valid),.Sdr_rd_dout(sdr_data));
wire pcm_fifo_empty,pcm_fifo_valid,pcm_re;wire[31:0] pcm_data;
rfifo_32_32_512 #(.ADDR_WIDTH_W(11),.ADDR_WIDTH_R(11),.AL_FULL_NUM(2045)) pcm_fifo(.rst(rs||rp||!sd_ready),.clkw(sd_clk),.clkr(pixel_clk),.we(audio_we),.di(audio_word),
 .re(pcm_re),.dout(pcm_data),.valid(pcm_fifo_valid),.full_flag(),.empty_flag(pcm_fifo_empty),.afull(),.aempty(),.wrusedw(audio_used),.rdusedw());
reg[26:0] audio_phase;wire audio_tick=audio_phase>=75000000-48000;
always @(posedge pixel_clk)if(rp)audio_phase<=0;else audio_phase<=audio_tick ? audio_phase-(75000000-48000):audio_phase+48000;
wire[23:0] left_pcm,right_pcm,hdmi_left,hdmi_right;wire hdmi_audio_valid;wire[1:0] audio_mode;wire[31:0] audio_underruns;
saixian_pcm_player player(.clk(pixel_clk),.rst(rp),.play_enable(display_valid),.sample_tick(audio_tick),
 .fifo_empty(pcm_fifo_empty),.fifo_data(pcm_data),.fifo_valid(pcm_fifo_valid),.fifo_read(pcm_re),
 .audio_left(left_pcm),.audio_right(right_pcm),.audio_level(),.audio_active(),.spectrum_tone_bin(),.underrun_count(audio_underruns));
water_audio_output audio_output(.clk(pixel_clk),.rst(rp),.sample_tick(audio_tick),.cycle_mode(audio_mode_cycle),
 .source_left(left_pcm),.source_right(right_pcm),.pcm_valid(hdmi_audio_valid),.pcm_left(hdmi_left),.pcm_right(hdmi_right),.mode(audio_mode));
wire[23:0] picture;wire pic_de,pic_vs,underflow;
water_expand unpack(.video_clk(pixel_clk),.rst(rp),.read_en(read_enable),.read_data(read_data),.read_empty(read_empty),
 .display_valid(display_valid),.underflow_latched(underflow),.hs(1'b0),.vs(vs),.de(raw_de),.hs_r(),.vs_r(pic_vs),.de_r(pic_de),.vout_data(picture));
reg[10:0] xq[0:20];reg[9:0] yq[0:20];integer t;
always @(posedge pixel_clk)begin xq[0]<=x;yq[0]<=y;for(t=1;t<21;t=t+1)begin xq[t]<=xq[t-1];yq[t]<=yq[t-1];end end
wire[23:0] edge_rgb;wire edge_de,edge_sof,edge_eol;wire[7:0] edge_level;
water_edge lighting(.clk(pixel_clk),.rst(rp),.frame_tick(animation_tick),.music_drive(!sw_sync[0]),.pcm_valid(hdmi_audio_valid),
 .pcm_left(hdmi_left[23:8]),.pcm_right(hdmi_right[23:8]),.x(xq[20]),.y(yq[20]),.de(pic_de),
 .sof(pic_de&&xq[20]==0&&yq[20]==0),.eol(pic_de&&xq[20]==1279),.rgb(picture),.darkness(darkness),
 .de_out(edge_de),.sof_out(edge_sof),.eol_out(edge_eol),.rgb_out(edge_rgb),.level(edge_level));
wire[23:0] limited;reg[1:0] de_q,sof_q,eol_q;
fluid_rgb_limited range(.clk(pixel_clk),.rgb(edge_rgb),.limited_rgb(limited));
always @(posedge pixel_clk)begin de_q<={de_q[0],edge_de};sof_q<={sof_q[0],edge_sof};eol_q<={eol_q[0],edge_eol};if(rp)begin de_q<=0;sof_q<=0;eol_q<=0;end end
wire acr_valid,hdmi_locked;wire[19:0] cts,n;wire[9:0] blue,green,red,clock_data;
audio_arc_calculate acr(.I_clk(pixel_clk),.I_rst(rp),.I_audio_valid(hdmi_audio_valid),.O_acr_valid(acr_valid),.O_acr_cts(cts),.O_acr_n(n));
reg hpd0,hpd1,hpd2;always @(posedge pixel_clk)begin hpd0<=hdmi_hpd;hpd1<=hpd0;hpd2<=hpd1;if(rp)begin hpd0<=0;hpd1<=0;hpd2<=0;end end
hdmi_1_4b_transmitter_core_wrapper #(.DEVICE("EG"),.HTOTAL(1650),.HSA(40),.HFP(110),.HBP(220),.HACTIVE(1280),
 .VTOTAL(750),.VSA(5),.VFP(5),.VBP(20),.VACTIVE(720),.VIDEO_VIC(4),.VIDEO_TPG("Disable"),.VIDEO_FORMAT("RGB"),.AUDIO_SAMPLE_RATE("48K"),.IIC_SCL_DIV(375)) hdmi(
 .I_pixel_clk(pixel_clk),.I_rst(rp),.I_edid_read_trig(hpd1&&!hpd2),.O_edid_read_valid(),.O_edid_read_data(),
 .I_axis_s_user(sof_q[1]),.I_axis_s_valid(de_q[1]),.I_axis_s_last(eol_q[1]),.I_axis_s_data(limited),.O_axis_s_ready(),
 .I_audio_valid(hdmi_audio_valid),.I_audio_left_data(hdmi_left),.I_audio_right_data(hdmi_right),.I_acr_valid(acr_valid),.I_acr_cts(cts),.I_acr_n(n),.O_video_locked(hdmi_locked),
 .O_ch0_tmds_data(blue),.O_ch1_tmds_data(green),.O_ch2_tmds_data(red),.O_clk_tmds_data(clock_data),.O_ddc_scl(HDMI_DDC_SCL),.IO_ddc_sda(HDMI_DDC_SDA));
water_hdmi_phy phy(.I_pixel_clk(pixel_clk),.I_serial_clk(serial_clk),.I_pixel_rst(rp),.I_serial_rst(rt),.I_tmds_channel_0(blue),.I_tmds_channel_1(green),.I_tmds_channel_2(red),.I_tmds_channel_clk(clock_data),
 .O_tmds_ch0_p(HDMI_D0_P),.O_tmds_ch1_p(HDMI_D1_P),.O_tmds_ch2_p(HDMI_D2_P),.O_tmds_clk_p(HDMI_CLK_P));
assign led={underflow||write_overflow||error_code!=0||read_timeouts!=0||audio_underruns!=0,transition_active||sw_sync[1],display_valid,sd_ready};
water_status diagnostic(.clk(sd_clk),.rst(rs),.state(sd_state),.images(image_count),.audio(track_count),.error_code(error_code),
 .asynchronous_status({initialized,hdmi_locked,underflow,write_overflow,audio_mode,|audio_underruns,|read_timeouts}),.seg_sel(seg_sel),.seg_data(seg_data));
endmodule
