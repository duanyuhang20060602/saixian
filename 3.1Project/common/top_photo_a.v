`timescale 1ns/1ps
module top_photo_a(
 input clk,hdmi_hpd,link_clk,input [15:0] link_data,input link_valid,link_sof,link_eof,
 input [3:0] key,input control_rx,hmi_uart_rx,output control_tx,hmi_uart_tx,
 input audio_miso,output audio_sclk,audio_cs,audio_mosi,
 output link_ready,output [5:0] seg_sel,output [7:0] seg_data,
 output HDMI_CLK_P,HDMI_D2_P,HDMI_D1_P,HDMI_D0_P,HDMI_DDC_SCL,inout HDMI_DDC_SDA);
wire unused_sd,mem_clk,mem_clk_sft,sys_lock,pixel_clk,serial_clk,video_lock;
wire rst_mem,rst_pixel,rst_serial,rst_link,rst_ref;
sys_pll u_sys_pll(.refclk(clk),.reset(1'b0),.clk0_out(unused_sd),.clk1_out(mem_clk),.clk2_out(mem_clk_sft),.locked(sys_lock));
video_pll u_video_pll(.refclk(clk),.reset(1'b0),.clk0_out(pixel_clk),.clk1_out(serial_clk),.locked(video_lock));
dual_still_reset_sync rm(.clk(mem_clk),.arst(!sys_lock),.rst(rst_mem));
dual_still_reset_sync rp(.clk(pixel_clk),.arst(!video_lock || !sys_lock),.rst(rst_pixel));
dual_still_reset_sync rh(.clk(serial_clk),.arst(!video_lock || !sys_lock),.rst(rst_serial));
dual_still_reset_sync rl(.clk(link_clk),.arst(!sys_lock || !video_lock),.rst(rst_link));
dual_still_reset_sync rr(.clk(clk),.arst(!sys_lock || !video_lock),.rst(rst_ref));
wire high_color_requested,high_color,format_changed;
wire color_mode_valid,color_mode_value;
reg [5:0] image_reset_count;
always @(posedge pixel_clk or posedge rst_pixel)
 if(rst_pixel)image_reset_count<=0;
 else if(format_changed)image_reset_count<=63;
 else if(image_reset_count!=0)image_reset_count<=image_reset_count-1'b1;
wire image_reset=image_reset_count!=0;
wire rst_image_pixel=rst_pixel || image_reset;
wire rst_image_mem,rst_image_link;
dual_still_reset_sync rcm(.clk(mem_clk),.arst(rst_mem || image_reset),.rst(rst_image_mem));
dual_still_reset_sync rcl(.clk(link_clk),.arst(rst_link || image_reset),.rst(rst_image_link));
(* async_reg="true" *)reg color_link_meta,color_link_sync;
always @(posedge link_clk or posedge rst_link)
 if(rst_link)begin color_link_meta<=0;color_link_sync<=0;end
 else begin color_link_meta<=high_color;color_link_sync<=color_link_meta;end
wire req,we,ack,full,finish,rx_done,rx_armed,rx_fault;
wire [31:0] packed_data,read_data,rx_crc;reg finish_toggle,done_toggle;
always @(posedge mem_clk or posedge rst_mem)
 if(rst_mem)finish_toggle<=0;else if(finish)finish_toggle<=~finish_toggle;
always @(posedge link_clk or posedge rst_link)
 if(rst_link)done_toggle<=0;else if(rx_done)done_toggle<=~done_toggle;
wire arm_toggle,abort_toggle,arm,abort;
wire [1:0] receive_slot,active_slot,new_slot,ready_slot;
photo_event_sync sa(.clk(link_clk),.rst(rst_link),.toggle(arm_toggle),.pulse(arm));
photo_event_sync sb(.clk(link_clk),.rst(rst_link),.toggle(abort_toggle),.pulse(abort));
photo_link_receiver #(.ENABLE_CRC(0),.LEGACY_TIMING(1)) rx(.high_color(color_link_sync),.clk(link_clk),.rst(rst_image_link),.arm(arm),.abort(abort),.data(link_data),.valid(link_valid),.sof(link_sof),.eof(link_eof),
 .ready(link_ready),.armed(rx_armed),.busy(),.write_req(req),.write_ack(ack),.full(full),.write_en(we),.write_data(packed_data),
 .finish_toggle(finish_toggle),.done(rx_done),.fault(rx_fault),.frame_crc(rx_crc));

wire read_req,read_en,read_ack,read_finish,read_empty,init_done;
wire transition_active,slide_right,display_valid,frame_commit,ready_toggle,ready_right,ready_immediate;
wire [2:0] transition_mode;wire [10:0] slide_offset;wire [5:0] darkness;
wire [2:0] effect_select;wire auto_enable;
frame_store #(.FLIP(0)) store(.high_color(high_color),.write_slot(receive_slot),.read_slot(active_slot),.new_slot(new_slot),
 .slide_active(transition_active),.slide_right(slide_right),.slide_offset({1'b0,slide_offset[10:1]}),.transition_mode(transition_mode),
 .mem_clk(mem_clk),.mem_clk_sft(mem_clk_sft),.rst(rst_image_mem),
 .write_clk(link_clk),.write_req(req),.write_en(we && !full),.write_data(packed_data),.write_ack(ack),.write_finish(finish),.write_full(full),
 .read_clk(pixel_clk),.read_req(read_req),.read_en(read_en),.read_ack(read_ack),.read_finish(read_finish),
 .read_empty(read_empty),.read_data(read_data),.init_done(init_done));
wire hs,vs,de,fs;wire [11:0] x;wire [10:0] y;wire [9:0] blue,green,red;
wire blank_start=x==0 && y==720;
wire [23:0] menu_notice_rgb;
wire [23:0] raw_rgb,final_rgb,resolution_rgb,feature_rgb,music_ui_rgb;
wire [15:0] source_width_bcd,source_height_bcd;
wire [15:0] current_source_width,current_source_height;
wire award_active=display_valid && current==3'd6 && current_source_width[15];
wire [23:0] award_rgb,award_menu_rgb;
reg award_pause;
// The FIFO reader takes two cycles, photo enhancement seven, adjustment
// eight and style/fade/multiply/range four: 21 clocks in all.
hdmi_minimal_tx #(.EXTERNAL_VIDEO(1),.VIDEO_DELAY(21)) u_tx(.clk(pixel_clk),.rst(rst_pixel),.rgb_in(final_rgb),
 .blue(),.green(),.red(),.hs(hs),.vs(vs),.de(de),.frame_start(fs),.x(x),.y(y));
wire armed,started,underflow;
frame_pixels pixels(.high_color(high_color),.clk(pixel_clk),.rst(rst_image_pixel),.de(de),.x(x),.y(y),.image_valid(display_valid),
 .read_ack(read_ack),.empty(read_empty),.data(read_data),.read_req(read_req),.read_en(read_en),.rgb(raw_rgb),
 .armed(armed),.output_started(started),.underflow(underflow));
saixian_transition #(.ALLOW_IMMEDIATE(1)) transition(.clk(pixel_clk),.rst(rst_image_pixel),.frame_tick(blank_start),.frame_ready_toggle(ready_toggle),
 .ready_buf_idx(ready_slot),.ready_slide_right(ready_right),.ready_immediate(ready_immediate),.effect_select(high_color ? 3'd6:effect_select),.active_buf_idx(active_slot),.slide_new_buf_idx(new_slot),
 .frame_commit_toggle(frame_commit),.display_valid(display_valid),.transition_active(transition_active),
 .transition_mode(transition_mode),.slide_offset(slide_offset),.slide_right(slide_right),.transition_level(darkness));
wire [3:0] presses;
genvar k;
generate for(k=0;k<4;k=k+1)begin:keys
 saixian_key_debounce #(.CLK_FREQ_HZ(75000000)) button(.clk(pixel_clk),.rst(rst_pixel),.key_n(key[k]),.press_pulse(presses[k]));
end endgenerate
wire hmi_music_next,hmi_start,hmi_pause,hmi_pause_set,hmi_resume,hmi_finish;
wire hmi_project_valid;wire [1:0] hmi_project_value;
wire key4_short,key4_long;
photo_key_hold key4_hold(.clk(pixel_clk),.rst(rst_pixel),.key_n(key[3]),.short_release(key4_short),.long_press(key4_long));
wire [3:0] event_state,countdown_value,cue_event;wire [6:0] event_minutes;wire [5:0] event_seconds;
wire carousel_mode;wire [1:0] event_project;reg [1:0] project_select;
always @(posedge pixel_clk or posedge rst_pixel)
 if(rst_pixel)project_select<=0;else if(hmi_project_valid && carousel_mode)project_select<=hmi_project_value;
wire hmi_prev,hmi_next,setting_valid,reset_defaults,page_notify;wire [2:0] setting_id,page_id;wire [7:0] setting_value;
wire effect_valid,auto_valid,auto_value;wire audio_view_valid,audio_view_value,waveform_mode;wire [2:0] effect_value;
saixian_hmi_uart #(.CLK_FREQ_HZ(75000000)) screen_rx(.clk(pixel_clk),.rst(rst_pixel),.uart_rx(hmi_uart_rx),
 .project_valid(hmi_project_valid),.project_value(hmi_project_value),
 .start_pulse(hmi_start),.pause_pulse(hmi_pause),.pause_set_pulse(hmi_pause_set),.resume_pulse(hmi_resume),.finish_pulse(hmi_finish),
 .music_next_pulse(hmi_music_next),.prev_pulse(hmi_prev),.next_pulse(hmi_next),.setting_valid(setting_valid),.setting_id(setting_id),.setting_value(setting_value),
 .effect_valid(effect_valid),.effect_value(effect_value),.auto_valid(auto_valid),.auto_value(auto_value),.audio_view_valid(audio_view_valid),.audio_view_value(audio_view_value),.color_mode_valid(color_mode_valid),.color_mode_value(color_mode_value),
 .reset_defaults_pulse(reset_defaults),.page_id(page_id),.page_notify_pulse(page_notify));
wire settings_mode;wire [3:0] setting_item;wire [3:0] brightness,contrast,saturation,volume;wire [1:0] sharpness,enhancement;wire invert,vintage;
// Match the single-board photo pipeline: enhancement owns the spatial
// smoothing/sharpening control; the later colour stage must not sharpen twice.
photo_unified_settings_controller #(.CLK_FREQ_HZ(75000000),.IMAGE_MENU(0)) settings(.clk(pixel_clk),.rst(rst_pixel),.carousel_mode(carousel_mode),
 .key_next_item(presses[0]),.key_decrease(presses[1]),.key_enter_exit(presses[2]),.key_increase(presses[3]),
 .hmi_setting_valid(setting_valid),.hmi_setting_id(setting_id),.hmi_setting_value(setting_value),.hmi_reset_defaults(reset_defaults),
 .effect_valid(effect_valid),.effect_value(effect_value),.auto_valid(auto_valid),.auto_value(auto_value),.audio_view_valid(audio_view_valid),.audio_view_value(audio_view_value),.color_mode_valid(color_mode_valid),.color_mode_value(color_mode_value),
 .effect_select(effect_select),.auto_enable(auto_enable),
 .high_color_requested(high_color_requested),.waveform_mode(waveform_mode),.settings_mode(settings_mode),.setting_item(setting_item),.volume_setting(volume),.brightness_setting(brightness),.contrast_setting(contrast),
 .saturation_setting(saturation),.sharpness_setting(sharpness),.invert_setting(invert),.vintage_setting(vintage),.enhancement_setting(enhancement));
saixian_event_controller #(.CLK_FREQ_HZ(75000000)) event_controller(.clk(pixel_clk),.rst(rst_pixel),.frame_start(blank_start),
 .key_start(!settings_mode && (hmi_start || key4_long || (!carousel_mode && presses[0]))),
 .key_pause((!carousel_mode && presses[1]) || (!(award_active && carousel_mode) && (hmi_pause || (hmi_pause_set && event_state==6) || (hmi_resume && event_state==7)))),
 .key_end((!carousel_mode && presses[2]) || hmi_finish),.project_switch(project_select),
 .state(event_state),.project_id(event_project),.minutes(event_minutes),.seconds(event_seconds),
 .countdown_value(countdown_value),.cue_event(cue_event),.carousel_mode(carousel_mode));
reg [27:0] finish_delay;
always @(posedge pixel_clk or posedge rst_pixel)
 if(rst_pixel)finish_delay<=0;else if(event_state!=8)finish_delay<=0;
 else if(finish_delay<150000000)finish_delay<=finish_delay+1'b1;
wire bg_music_enable=carousel_mode || (event_state==8 && finish_delay>=150000000);
// Register playback focus: the event-state decoder must not feed the UART
// request/cache-victim control cone in the same pixel-clock cycle.
reg photo_focus;
always @(posedge pixel_clk or posedge rst_pixel)
 if(rst_pixel)photo_focus<=0;
 else photo_focus<=settings_mode || !carousel_mode || award_active || award_loading;
reg armed_meta,armed_sync,fault_meta,fault_sync;
always @(posedge pixel_clk or posedge rst_pixel)
 if(rst_pixel)begin armed_meta<=0;armed_sync<=0;fault_meta<=0;fault_sync<=0;end
 else begin armed_meta<=rx_armed;armed_sync<=armed_meta;fault_meta<=rx_fault;fault_sync<=fault_meta;end
wire done_pixel,busy;wire [2:0] count,current;wire [3:0] error,control_state;
wire auto_next,award_available,award_scan_complete,award_loading;wire [1:0] award_notice;
photo_auto_advance auto_advance(.clk(pixel_clk),.rst(rst_pixel),.enable(auto_enable && carousel_mode && !award_active && !award_loading),
 .display_valid(display_valid),.transition_active(transition_active),.busy(busy),.enough_images(count>1),
 .settings_mode(settings_mode),.manual_event(presses[0] || key4_short || hmi_next || reset_defaults),
 .next_pulse(auto_next));
photo_event_sync sd(.clk(pixel_clk),.rst(rst_pixel),.toggle(done_toggle),.pulse(done_pixel));
reg done_pixel_registered;
always @(posedge pixel_clk or posedge rst_pixel)
 if(rst_pixel)done_pixel_registered<=0;else done_pixel_registered<=done_pixel;
wire [18:0] image_settings={high_color_requested,brightness,contrast,saturation,sharpness,enhancement,invert,vintage};
wire settings_updating;
photo_cached_control_a #(.CHECK_FRAME_CRC(0),.SETTINGS_LINK(1),.AWARD_CONTROL(1)) ctrl(.high_color(high_color),.format_changed(format_changed),.settings_mode(photo_focus),.settings_state(image_settings),.settings_updating(settings_updating),.clk(pixel_clk),.rst(rst_pixel),.uart_rx(control_rx),.uart_tx(control_tx),
 .award_toggle(carousel_mode && !settings_mode && key4_short),.award_available(award_available),.award_scan_complete(award_scan_complete),.award_loading(award_loading),.award_notice(award_notice),
 .previous(1'b0),.next(carousel_mode && !settings_mode && (presses[0] || hmi_next || auto_next)),
 .active_slot(active_slot),.new_slot(new_slot),.transition_active(transition_active),.commit_toggle(frame_commit),
 .receive_slot(receive_slot),.arm_toggle(arm_toggle),.abort_toggle(abort_toggle),.rx_armed(armed_sync),.rx_done(done_pixel_registered),
 .ready_immediate(ready_immediate),.rx_fault(fault_sync),.rx_crc(rx_crc),.ready_toggle(ready_toggle),.ready_slot(ready_slot),.ready_right(ready_right),
 .image_count(count),.current_image(current),.busy(busy),.error(error),.debug_state(control_state),
 .current_source_width(current_source_width),.current_source_height(current_source_height));
wire [2:0] music_count,music_index;wire [7:0] music_epoch;
wire [3:0] audio_diag_stage,audio_buffer_level;wire audio_header_seen,audio_pcm_seen,audio_nonzero_seen;
wire audio_sample_valid;wire [23:0] audio_left,audio_right;wire [15:0] audio_packet_errors,audio_underflows;
photo_audio_spi_a audio_link(.clk(pixel_clk),.rst(rst_pixel),.bg_enable(bg_music_enable),.volume(volume),.cue_event(cue_event),
 .next_track(carousel_mode && ((!settings_mode && !award_active && presses[1]) || hmi_music_next)),
 .spi_miso(audio_miso),.spi_sclk(audio_sclk),.spi_cs(audio_cs),.spi_mosi(audio_mosi),
 .track_count(music_count),.track_index(music_index),.desired_epoch(music_epoch),
 .diagnostic_stage(audio_diag_stage),.buffer_level(audio_buffer_level),.header_seen(audio_header_seen),.pcm_seen(audio_pcm_seen),.nonzero_seen(audio_nonzero_seen),
 .sample_valid(audio_sample_valid),.audio_left(audio_left),.audio_right(audio_right),.packet_errors(audio_packet_errors),.underflows(audio_underflows));
// Keep the known 21-cycle RGB path; send aligned AXI pixels to the single-board
// HDMI core, including an exact last-pixel marker and first-frame marker.
reg [25:0] audio_video_de,audio_video_sof,audio_video_last;
always @(posedge pixel_clk or posedge rst_pixel)begin
 if(rst_pixel)begin audio_video_de<=0;audio_video_sof<=0;audio_video_last<=0;end
 else begin audio_video_de<={audio_video_de[24:0],de};
  audio_video_sof<={audio_video_sof[24:0],de && x==0 && y==0};
  audio_video_last<={audio_video_last[24:0],de && x==1279};end
end
wire acr_valid;wire [19:0] acr_cts,acr_n;
audio_arc_calculate #(.ACR_N(6144)) acr(.I_clk(pixel_clk),.I_rst(rst_pixel),.I_audio_valid(audio_sample_valid),.O_acr_valid(acr_valid),.O_acr_cts(acr_cts),.O_acr_n(acr_n));
reg hpd_audio_meta,hpd_audio_sync,hpd_audio_previous;
always @(posedge pixel_clk or posedge rst_pixel)begin
 if(rst_pixel)begin hpd_audio_meta<=0;hpd_audio_sync<=0;hpd_audio_previous<=0;end
 else begin hpd_audio_meta<=hdmi_hpd;hpd_audio_sync<=hpd_audio_meta;hpd_audio_previous<=hpd_audio_sync;end
end
wire [9:0] hdmi_clock_data;wire axis_ready,hdmi_video_locked;
hdmi_1_4b_transmitter_core_wrapper #(.DEVICE("EG"),.HTOTAL(1650),.HSA(40),.HFP(110),.HBP(220),.HACTIVE(1280),
 .VTOTAL(750),.VSA(5),.VFP(5),.VBP(20),.VACTIVE(720),.VIDEO_VIC(4),.VIDEO_TPG("Disable"),.VIDEO_FORMAT("RGB"),.AUDIO_SAMPLE_RATE("48K"),.IIC_SCL_DIV(375)) audio_hdmi(
 .I_pixel_clk(pixel_clk),.I_rst(rst_pixel),.I_edid_read_trig(hpd_audio_sync && !hpd_audio_previous),.O_edid_read_valid(),.O_edid_read_data(),
 .I_axis_s_user(audio_video_sof[25]),.I_axis_s_valid(audio_video_de[25]),.I_axis_s_last(audio_video_last[25]),.I_axis_s_data(feature_rgb),.O_axis_s_ready(axis_ready),
 .I_audio_valid(audio_sample_valid),.I_audio_left_data(audio_left),.I_audio_right_data(audio_right),.I_acr_valid(acr_valid),.I_acr_cts(acr_cts),.I_acr_n(acr_n),.O_video_locked(hdmi_video_locked),
 .O_ddc_scl(HDMI_DDC_SCL),.IO_ddc_sda(HDMI_DDC_SDA),.O_ch0_tmds_data(blue),.O_ch1_tmds_data(green),.O_ch2_tmds_data(red),.O_clk_tmds_data(hdmi_clock_data));
saixian_hmi_status_tx #(.CLK_FREQ_HZ(75000000),.ENHANCEMENT_FEEDBACK(1)) screen_tx(.clk(pixel_clk),.rst(rst_pixel),.image_count(count),
 .audio_count(music_count),.error_code(error>7 ? 3'd7:error[2:0]),.initializing(count==0),.page_id(page_id),
 .refresh_request(page_notify || setting_valid || reset_defaults),.sharpness(sharpness),.brightness(brightness),.contrast(contrast),
 .saturation(saturation),.volume(volume),.invert(invert),.vintage(vintage),.enhancement(enhancement),.event_state(event_state),.minutes(event_minutes),.seconds(event_seconds),
 .uart_tx(hmi_uart_tx),.command_sent_pulse());
// Snapshot settings in blanking. Delay coordinates alongside the FIFO RGB.
reg [3:0] bf,cf,sf;reg [1:0] shf,ef;reg invf,vinf;
reg [1:0] de_pipe,vs_pipe;reg [10:0] x0,x1;reg [9:0] y0,y1;
always @(posedge pixel_clk or posedge rst_pixel)begin
 if(rst_pixel)begin bf<=4;cf<=4;sf<=4;shf<=1;ef<=1;invf<=0;vinf<=0;de_pipe<=0;vs_pipe<=0;x0<=0;x1<=0;y0<=0;y1<=0;end
 else begin
  de_pipe<={de_pipe[0],de};vs_pipe<={vs_pipe[0],vs};x0<=x[10:0];x1<=x0;y0<=y[9:0];y1<=y0;
  if(blank_start)begin bf<=brightness;cf<=contrast;sf<=saturation;shf<=sharpness;ef<=enhancement;invf<=invert;vinf<=vintage;end
 end
end
wire [23:0] enhanced,adjusted,styled;wire enhanced_de,enhanced_vs;wire [10:0] enhanced_x;wire [9:0] enhanced_y;
saixian_adaptive_enhance #(.WIDTH(1280),.SPLIT_X(640),.PHOTO_SMOOTH(1)) enhance(
 .clk(pixel_clk),.rst(rst_pixel),.de(de_pipe[1]),.vs(vs_pipe[1]),.frame_tick(blank_start),
 .statistics_enable(1'b0),.x(x1),.y(y1),.rgb_in(raw_rgb),.mode(2'd0),.strength(2'd0),.external_gain(2'd0),
 .rgb_out(enhanced),.de_out(enhanced_de),.vs_out(enhanced_vs),.x_out(enhanced_x),.y_out(enhanced_y),.gain_out());
saixian_picture_adjust_pipe adjust(.clk(pixel_clk),.rst(rst_pixel),.de(enhanced_de),.x(enhanced_x),.rgb_in(enhanced),
 .brightness_setting(4'd4),.contrast_setting(4'd4),.saturation_setting(4'd4),.sharpness_setting(2'd0),.rgb_out(adjusted));
saixian_hmi_color_style style(.rgb_in(adjusted),.invert(1'b0),.vintage(1'b0),.rgb_out(styled));
function [7:0] fade_channel;
 input [7:0] value;input [5:0] level;reg [15:0] p;reg [7:0] faded;
 begin faded=value>({2'd0,level}<<2) ? value-({2'd0,level}<<2):0;
 fade_channel=faded;end
endfunction
reg [23:0] style_rgb,fade_rgb,range_rgb;reg [15:0] range_r,range_g,range_b;
always @(posedge pixel_clk or posedge rst_pixel)begin
 if(rst_pixel)begin style_rgb<=0;fade_rgb<=0;range_r<=0;range_g<=0;range_b<=0;range_rgb<=24'h101010;end
 else begin
  style_rgb<=styled;
  fade_rgb<={fade_channel(style_rgb[23:16],darkness),fade_channel(style_rgb[15:8],darkness),fade_channel(style_rgb[7:0],darkness)};
  range_r<=fade_rgb[23:16]*8'd219+16'd128;range_g<=fade_rgb[15:8]*8'd219+16'd128;range_b<=fade_rgb[7:0]*8'd219+16'd128;
  range_rgb<={8'd16+range_r[15:8],8'd16+range_g[15:8],8'd16+range_b[15:8]};
 end
end
photo_resolution_overlay #(.VIDEO_DELAY(21)) resolution_overlay(.clk(pixel_clk),.rst(rst_pixel),
 .x(x),.y(y),.de(de),.display_valid(display_valid),
 .width_bcd(source_width_bcd),.height_bcd(source_height_bcd),
 .source_width({1'b0,current_source_width[14:0]}),.source_height(current_source_height),.rgb_in(range_rgb),.rgb_out(resolution_rgb));
photo_settings_overlay #(.VIDEO_DELAY(21)) menu_overlay(.clk(pixel_clk),.rst(rst_pixel),.frame_tick(blank_start),
 .x(x),.y(y),.de(de),.settings_mode(settings_mode),.setting_item(setting_item),.updating(settings_updating),
 .high_color(high_color_requested),.volume(volume),.waveform_mode(waveform_mode),.brightness(brightness),.contrast(contrast),.saturation(saturation),.sharpness(sharpness),.enhancement(enhancement),
 .invert(invert),.vintage(vintage),.effect(effect_select),.auto_enable(auto_enable),
 .rgb_in(award_active ? award_menu_rgb:resolution_rgb),.rgb_out(menu_notice_rgb));
wire [7:0] audio_level;wire spectrum_active;wire [4:0] spectrum_bin;
photo_audio_meter_a meter(.clk(pixel_clk),.rst(rst_pixel),.sample_valid(audio_sample_valid),.pcm(audio_left),
 .level(audio_level),.active(spectrum_active),.tone_bin(spectrum_bin));
reg [11:0] ui_x_pipe[0:20];reg [10:0] ui_y_pipe[0:20];integer ui_i;
always @(posedge pixel_clk or posedge rst_pixel)begin
 if(rst_pixel)begin for(ui_i=0;ui_i<21;ui_i=ui_i+1)begin ui_x_pipe[ui_i]<=0;ui_y_pipe[ui_i]<=0;end end
 else begin ui_x_pipe[0]<=x;ui_y_pipe[0]<=y;
  for(ui_i=1;ui_i<21;ui_i=ui_i+1)begin ui_x_pipe[ui_i]<=ui_x_pipe[ui_i-1];ui_y_pipe[ui_i]<=ui_y_pipe[ui_i-1];end
 end
end
photo_award_notice award_notice_osd(.notice(carousel_mode && !settings_mode ? (award_loading ? 2'd1:award_notice):2'd0),
 .x(ui_x_pipe[20]),.y(ui_y_pipe[20]),.rgb_in(menu_notice_rgb),.rgb_out(final_rgb));
wire [20:0] ui_y_scaled=ui_y_pipe[20][9:0]*11'd683;
reg settings_render_mode;
always @(posedge pixel_clk or posedge rst_pixel)
 if(rst_pixel)settings_render_mode<=0;else if(blank_start)settings_render_mode<=settings_mode;
reg [9:0] ui_x;reg [8:0] ui_y;reg ui_de;reg [23:0] ui_rgb;
always @(posedge pixel_clk or posedge rst_pixel)begin
 if(rst_pixel)begin ui_x<=0;ui_y<=0;ui_de<=0;ui_rgb<=0;end
 else begin ui_x<=ui_x_pipe[20][10:1];ui_y<=ui_y_scaled[18:10];ui_rgb<=final_rgb;
  ui_de<=audio_video_de[20] && !settings_render_mode;end
end
wire [10:0] ui_font_addr;wire [15:0] ui_font_bits;
saixian_font_rom ui_font(.clk(pixel_clk),.glyph_id(ui_font_addr[10:4]),.row(ui_font_addr[3:0]),.bits(ui_font_bits));
reg [10:0] ticker_x;
always @(posedge pixel_clk or posedge rst_pixel)
 if(rst_pixel)ticker_x<=0;else if(blank_start)ticker_x<=ticker_x>=864 ? 0:ticker_x+1'b1;
saixian_osd_overlay music_event_ui(.clk(pixel_clk),.rst(rst_pixel),.frame_tick(blank_start),.de_i(ui_de),
 .x_i(ui_x),.y_i(ui_y),.rgb_in_i(ui_rgb),.display_valid(display_valid || music_count!=0 || !carousel_mode),
 .loading_phase(3'd0),.state(event_state),.project_id(carousel_mode ? project_select:event_project),
 .minutes(event_minutes),.seconds(event_seconds),.countdown_value(countdown_value),.ticker_x(ticker_x),
 .ticker_text_length(5'd0),.title_text_length(5'd0),.font_addr(ui_font_addr),.font_bits(ui_font_bits),.font_ready(1'b1),
 .source_width_bcd(source_width_bcd),.source_height_bcd(source_height_bcd),.error_code(3'd0),
 .transition_active(transition_active),.transition_level(darkness),.audio_level(audio_level),
 .spectrum_active(spectrum_active),.spectrum_tone_bin(spectrum_bin),.waveform_mode(waveform_mode),.settings_mode(1'b0),.setting_item(3'd0),
 .volume_setting(volume),.brightness_setting(brightness),.contrast_setting(contrast),.sharpness_setting(sharpness),
 .saturation_setting(saturation),.invert_setting(invert),.vintage_setting(vintage),.enhancement_setting(enhancement),
 .audio_sample_valid(audio_sample_valid),.audio_sample(audio_left[23:16]),.rgb_out(music_ui_rgb));
// The OSD drives black when DE is low: use an explicit, equal-latency
// bypass for the unified settings page instead of hiding it via DE.
reg [23:0] menu_bypass_rgb[0:4];reg [4:0] menu_bypass_select;integer menu_bi;
always @(posedge pixel_clk or posedge rst_pixel)begin
 if(rst_pixel)begin menu_bypass_select<=0;for(menu_bi=0;menu_bi<5;menu_bi=menu_bi+1)menu_bypass_rgb[menu_bi]<=0;end
 else begin
  menu_bypass_select<={menu_bypass_select[3:0],settings_render_mode};
  menu_bypass_rgb[0]<=final_rgb;
  for(menu_bi=1;menu_bi<5;menu_bi=menu_bi+1)menu_bypass_rgb[menu_bi]<=menu_bypass_rgb[menu_bi-1];
 end
end
// Award input coordinates follow the same two-cycle FIFO latency as raw_rgb.
// Bypass photo fades, resolution text and music graphics for the full scene.
photo_award_render award_render(.clk(pixel_clk),.rst(rst_pixel),.enable(award_active),
 .pause(award_pause || settings_mode),.frame_tick(blank_start),.x(x1),.y(y1),
 .tagged_rgb(raw_rgb),.rgb(award_rgb),.menu_rgb(award_menu_rgb));
always @(posedge pixel_clk or posedge rst_pixel)
 if(rst_pixel)award_pause<=0;
 else if(!award_active)award_pause<=0;
 else if(hmi_resume)award_pause<=0;
 else if(hmi_pause_set)award_pause<=1;
 else if(hmi_pause || (!settings_mode && carousel_mode && presses[1]))award_pause<=!award_pause;
wire [23:0] playback_rgb=award_active && carousel_mode && !settings_render_mode ? award_rgb:
 (menu_bypass_select[4] ? menu_bypass_rgb[4]:music_ui_rgb);
wire boot_active;wire [23:0] boot_rgb;
(* async_reg="true" *)reg boot_init_meta,boot_init_sync;
always @(posedge pixel_clk or posedge rst_pixel)
 if(rst_pixel)begin boot_init_meta<=0;boot_init_sync<=0;end
 else begin boot_init_meta<=init_done;boot_init_sync<=boot_init_meta;end
photo_boot_screen #(.VIDEO_DELAY(26),.MIN_FRAMES(90)) boot_screen(
 .clk(pixel_clk),.rst(rst_pixel),.frame_tick(blank_start),.x(x),.y(y),
 .memory_ready(boot_init_sync),.catalog_ready(count!=0 || award_available),
 .frame_ready(display_valid && started),.active(boot_active),.rgb(boot_rgb));
assign feature_rgb=boot_active ? boot_rgb:playback_rgb;
hdmi_phy_wrapper #(.DEVICE("EG")) u_hdmi_phy(.I_pixel_clk(pixel_clk),.I_serial_clk(serial_clk),.I_rst(rst_serial),
 .I_tmds_channel_0(blue),.I_tmds_channel_1(green),.I_tmds_channel_2(red),.I_tmds_channel_clk(hdmi_clock_data),
 .O_tmds_ch0_p(HDMI_D0_P),.O_tmds_ch1_p(HDMI_D1_P),.O_tmds_ch2_p(HDMI_D2_P),.O_tmds_clk_p(HDMI_CLK_P));
wire scan_valid,scan_fault,clock_valid,clock_fault;
hdmi_scan_monitor #(.HT(1650),.VT(750),.HA(1280),.VA(720),.HS(40),.VS(5)) u_scan(
 .clk(pixel_clk),.rst(rst_pixel),.x(x),.y(y),.de(de),.hs(hs),.vs(vs),.frame_start(fs),.valid(scan_valid),.fault(scan_fault));
hdmi_pixel_clock_monitor #(.EXPECTED_PIXELS(7500000),.TOLERANCE_PIXELS(75000)) u_clock_check(
 .ref_clk(clk),.pixel_clk(pixel_clk),.arst(!video_lock),.valid(clock_valid),.fault(clock_fault));
reg hpd_meta,hpd_sync;reg [17:0] status_meta,status_sync;
reg [19:0] audio_diag_meta,audio_diag_sync;
reg [15:0] award_diag_meta,award_diag_sync;
reg menu_meta,menu_sync;reg [15:0] menu_digits_meta,menu_digits_sync;
// photo_status shifts nibble 0 out first, so encode the displayed order in reverse.
wire [15:0] menu_digits={4'd0,{3'b000,auto_enable},{1'b0,effect_select},setting_item};
always @(posedge clk or posedge rst_ref)
 if(rst_ref)begin hpd_meta<=0;hpd_sync<=0;status_meta<=0;status_sync<=0;
  award_diag_meta<=0;award_diag_sync<=0;audio_diag_meta<=0;audio_diag_sync<=0;menu_meta<=0;menu_sync<=0;menu_digits_meta<=0;menu_digits_sync<=0;end
 else begin hpd_meta<=hdmi_hpd;hpd_sync<=hpd_meta;
  audio_diag_meta<={audio_diag_stage,{1'b0,music_count},(music_count!=0 ? {1'b0,music_index}+4'd1:4'd0),audio_buffer_level,
   {1'b0,audio_nonzero_seen,hdmi_video_locked,hpd_audio_sync}};
  audio_diag_sync<=audio_diag_meta;
  award_diag_meta<={2'd0,(award_loading ? 2'd1:award_notice),3'd0,award_available,3'd0,award_scan_complete,error};award_diag_sync<=award_diag_meta;
  menu_meta<=settings_mode;menu_sync<=menu_meta;
  menu_digits_meta<=menu_digits;menu_digits_sync<=menu_digits_meta;
  status_meta<={count,(display_valid ? current+3'd1:3'd0),control_state,error,
   (error!=0 || underflow || scan_fault || clock_fault ? 4'd9:busy ? 4'd3:display_valid ? 4'd5:4'd2)};
  status_sync<=status_meta;end
photo_status #(.CLK_HZ(50000000)) status(.clk(clk),.rst(rst_ref),.status(menu_sync ? (hpd_sync ? status_sync[3:0]:4'd0):audio_diag_sync[3:0]),
 .error(status_sync[7:4]),.state(status_sync[11:8]),.image(status_sync[14:12]),.count(status_sync[17:15]),
 .diagnostic_page(menu_sync ? 3'd1:award_diag_sync[15:12]!=0 ? 3'd4:3'd5),.diagnostic_crc(menu_sync ? menu_digits_sync:award_diag_sync[15:12]!=0 ? award_diag_sync:audio_diag_sync[19:4]),.seg_sel(seg_sel),.seg_data(seg_data));

endmodule
