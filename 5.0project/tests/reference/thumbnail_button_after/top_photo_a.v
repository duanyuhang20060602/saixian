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
// The image pipeline has one fixed RGB565 format and the normal PLL resets.
wire rst_image_pixel=rst_pixel,rst_image_mem=rst_mem,rst_image_link=rst_link;
wire req,we,ack,full,finish,rx_done,rx_armed,rx_fault;
wire [3:0] rx_fault_detail;
wire [31:0] packed_data,read_data,rx_crc;reg finish_toggle,done_toggle;
always @(posedge mem_clk or posedge rst_mem)
 if(rst_mem)finish_toggle<=0;else if(finish)finish_toggle<=~finish_toggle;
always @(posedge link_clk or posedge rst_link)
 if(rst_link)done_toggle<=0;else if(rx_done)done_toggle<=~done_toggle;
wire receive_fluid,receive_award,receive_relief;
(* async_reg="true" *)reg fluid_link_meta,fluid_link_sync;
always @(posedge link_clk or posedge rst_link)
 if(rst_link)begin fluid_link_meta<=0;fluid_link_sync<=0;end
 else begin fluid_link_meta<=receive_fluid;fluid_link_sync<=fluid_link_meta;end
(* async_reg="true" *)reg award_link_meta,award_link_sync;
always @(posedge link_clk or posedge rst_link)
 if(rst_link)begin award_link_meta<=0;award_link_sync<=0;end
 else begin award_link_meta<=receive_award;award_link_sync<=award_link_meta;end
(* async_reg="true" *)reg relief_link_meta,relief_link_sync;
always @(posedge link_clk or posedge rst_link)if(rst_link)begin relief_link_meta<=0;relief_link_sync<=0;end else begin relief_link_meta<=receive_relief;relief_link_sync<=relief_link_meta;end
wire arm_toggle,abort_toggle,arm,abort;
wire [1:0] receive_slot,active_slot,new_slot,ready_slot;
photo_event_sync sa(.clk(link_clk),.rst(rst_link),.toggle(arm_toggle),.pulse(arm));
photo_event_sync sb(.clk(link_clk),.rst(rst_link),.toggle(abort_toggle),.pulse(abort));
photo_link_receiver #(.ENABLE_CRC(1),.LEGACY_TIMING(1),.AWARD_TAIL(1)) rx(.relief_frame(relief_link_sync),.award_frame(award_link_sync),.extended_frame(fluid_link_sync),.clk(link_clk),.rst(rst_image_link),.arm(arm),.abort(abort),.data(link_data),.valid(link_valid),.sof(link_sof),.eof(link_eof),
 .ready(link_ready),.armed(rx_armed),.busy(),.write_req(req),.write_ack(ack),.full(full),.write_en(we),.write_data(packed_data),
 .finish_toggle(finish_toggle),.done(rx_done),.fault(rx_fault),.frame_crc(rx_crc),.fault_detail(rx_fault_detail));

wire read_req,read_en,read_ack,read_finish,read_empty,init_done;
wire transition_active,slide_right,display_valid,frame_commit,ready_toggle,ready_right,ready_immediate;
wire [8:0] fluid_progress;
wire [76:0] fluid_configuration;
wire [4:0] transition_mode;wire [10:0] slide_offset;wire [5:0] darkness;
wire [4:0] effect_select;wire auto_enable;wire [4:0] auto_interval_seconds;
wire light_wide,light_request,light_ack,light_valid;wire [20:0] light_address,light_base;wire [31:0] light_data;
wire done_pixel,busy;wire [2:0] count,current;wire [3:0] error,control_state;
wire thumbnail_request,thumbnail_done,thumbnail_cache_valid,thumbnail_visible,thumbnail_cancel;
wire [1:0] thumbnail_slot,thumbnail_cache_slot;wire [2:0] thumbnail_id;
wire [12:0] thumbnail_address;wire [15:0] thumbnail_data;
wire thumbnail_blank;
wire thumbnail_read_busy;
wire relief_available;
wire auto_next,award_available,award_scan_complete,award_loading;wire [2:0] award_notice;wire [3:0] last_transfer_error;
wire settings_mode;
wire boot_active;
wire [15:0] current_source_width,current_source_height;
wire award_active=display_valid && current>=3'd6 && current_source_width[15];
// DISPLAY_CONTROL_REGISTERS
reg award_menu_select_q,award_display_select_q,preview_enable_q,pointer_nav_display_q;
frame_store #(.FLIP(0)) store(.write_relief(receive_relief),.write_award(receive_award),.read_award(award_active),
 .display_active(display_valid),.thumbnail_request(thumbnail_request),.thumbnail_cancel(thumbnail_cancel),
 .thumbnail_blank(thumbnail_blank),.thumbnail_slot(thumbnail_slot),
 .thumbnail_address(thumbnail_address),.thumbnail_done(thumbnail_done),.thumbnail_data(thumbnail_data),
 .light_wide(light_wide),.light_enable(award_active),.light_request(light_request),.light_address(light_address),.light_ack(light_ack),
 .light_data(light_data),.light_valid(light_valid),.light_base(light_base),
 .water_cfg(fluid_configuration),.fluid_progress(fluid_progress),.write_fluid(receive_fluid),.write_slot(receive_slot),.read_slot(active_slot),.new_slot(new_slot),
 .slide_active(transition_active),.slide_right(slide_right),.slide_offset({1'b0,slide_offset[10:1]}),.transition_mode(transition_mode),
 .mem_clk(mem_clk),.mem_clk_sft(mem_clk_sft),.rst(rst_image_mem),
 .write_clk(link_clk),.write_req(req),.write_en(we && !full),.write_data(packed_data),.write_ack(ack),.write_finish(finish),.write_full(full),
 .read_clk(pixel_clk),.read_req(read_req),.read_en(read_en),.read_ack(read_ack),.read_finish(read_finish),
 .read_empty(read_empty),.read_data(read_data),.init_done(init_done));
wire hs,vs,de,fs;wire [11:0] x;wire [10:0] y;wire [9:0] blue,green,red;
wire blank_start=x==0 && y==720;
wire [23:0] menu_notice_rgb;
wire [23:0] raw_rgb,final_rgb,feature_rgb,music_ui_rgb;
wire result_busy,result_sprint_active;


wire [23:0] award_rgb,award_menu_rgb;
wire [3:0] award_light_error;wire [6:0] award_light_frame;
reg [1:0] award_raw_de;
always @(posedge pixel_clk or posedge rst_pixel)
 if(rst_pixel)award_raw_de<=0;else award_raw_de<={award_raw_de[0],de};
reg award_pause;
// The FIFO reader takes two cycles, photo enhancement seven, adjustment
// eight and style/fade/multiply/range four: 21 clocks in all.
hdmi_minimal_tx #(.EXTERNAL_VIDEO(1),.VIDEO_DELAY(21)) u_tx(.clk(pixel_clk),.rst(rst_pixel),.rgb_in(final_rgb),
 .blue(),.green(),.red(),.hs(hs),.vs(vs),.de(de),.frame_start(fs),.x(x),.y(y));
wire armed,started,underflow;
frame_pixels pixels(.clk(pixel_clk),.rst(rst_image_pixel),.de(de),.x(x),.y(y),.image_valid(display_valid),
 .read_ack(read_ack),.empty(read_empty),.data(read_data),.read_req(read_req),.read_en(read_en),.rgb(raw_rgb),
 .armed(armed),.output_started(started),.underflow(underflow));
saixian_transition #(.ALLOW_IMMEDIATE(1)) transition(.fluid_enable(!award_active && !award_loading && !settings_mode),.clk(pixel_clk),.rst(rst_image_pixel),.frame_tick(blank_start),.frame_ready_toggle(ready_toggle),
 .ready_buf_idx(ready_slot),.ready_slide_right(ready_right),.ready_immediate(ready_immediate),.effect_select(effect_select),.active_buf_idx(active_slot),.slide_new_buf_idx(new_slot),
 .frame_commit_toggle(frame_commit),.display_valid(display_valid),.transition_active(transition_active),
 .fluid_progress(fluid_progress),.transition_mode(transition_mode),.slide_offset(slide_offset),.slide_right(slide_right),.transition_level(darkness));
wire [3:0] presses;
genvar k;
generate for(k=0;k<4;k=k+1)begin:keys
 saixian_key_debounce #(.CLK_FREQ_HZ(75000000)) button(.clk(pixel_clk),.rst(rst_pixel),.key_n(key[k]),.press_pulse(presses[k]));
end endgenerate
wire touch_valid,touch_down,touch_mode_valid,touch_mode_value;
wire [9:0] touch_x;wire [8:0] touch_y;
reg touch_mode;
always @(posedge pixel_clk or posedge rst_pixel)
 if(rst_pixel)touch_mode<=1;else if(touch_mode_valid)touch_mode<=touch_mode_value;
wire [10:0] cursor_x;wire [9:0] cursor_y;wire pointer_click,pointer_contact;
wire carousel_mode;
wire pointer_enabled=touch_mode && carousel_mode && !boot_active && !result_busy;
photo_touchpad pointer(.clk(pixel_clk),.rst(rst_pixel),.enable(pointer_enabled),.frame_tick(blank_start),
 .sample_valid(touch_valid),.sample_down(touch_down),.sample_x(touch_x),.sample_y(touch_y),
 .cursor_x(cursor_x),.cursor_y(cursor_y),.click(pointer_click),.contact(pointer_contact));
wire pointer_menu_click=pointer_click && pointer_enabled && cursor_x>=1152 && cursor_x<1256 && cursor_y>=24 && cursor_y<64;
localparam THUMBNAIL_X=1096,THUMBNAIL_Y=315;
wire pointer_navigation_enable=pointer_enabled && !settings_mode && !award_active && !award_loading && count>1;
wire pointer_next_click=pointer_click && pointer_navigation_enable && thumbnail_visible &&
 cursor_x>=THUMBNAIL_X-2 && cursor_x<THUMBNAIL_X+162 &&
 cursor_y>=THUMBNAIL_Y-14 && cursor_y<THUMBNAIL_Y+92;
wire pointer_row_click=pointer_click && pointer_enabled && settings_mode && cursor_x>=64 && cursor_x<864 && cursor_y>=144 && cursor_y<592;
wire [9:0] pointer_row_y=cursor_y-10'd144;
// Isolate context/hit decoding from the settings controller's update priority.
reg pointer_menu_event,pointer_row_event,pointer_increase_q;reg [3:0] pointer_item_q;
always @(posedge pixel_clk or posedge rst_pixel)
 if(rst_pixel)begin pointer_menu_event<=0;pointer_row_event<=0;pointer_increase_q<=0;pointer_item_q<=0;end
 else begin
  pointer_menu_event<=pointer_menu_click;pointer_row_event<=pointer_row_click;
  pointer_item_q<=pointer_row_y[8:5];pointer_increase_q<=cursor_x>=448;
 end
wire hmi_award_valid,hmi_award_value;
wire hmi_music_next,hmi_start,hmi_pause,hmi_pause_set,hmi_resume,hmi_finish;
wire hmi_result_blue,hmi_result_red,hmi_result_sprint,hmi_result_stop;
wire hmi_project_valid;wire [1:0] hmi_project_value;
wire key4_short,key4_long;
photo_key_hold key4_hold(.clk(pixel_clk),.rst(rst_pixel),.key_n(key[3]),.short_release(key4_short),.long_press(key4_long));
wire [3:0] event_state,countdown_value,cue_event;wire [6:0] event_minutes;wire [5:0] event_seconds;
wire [1:0] event_project;reg [1:0] project_select;
always @(posedge pixel_clk or posedge rst_pixel)
 if(rst_pixel)project_select<=0;else if(hmi_project_valid && carousel_mode)project_select<=hmi_project_value;
wire hmi_prev,hmi_next,setting_valid,reset_defaults,page_notify;wire [2:0] setting_id,page_id;wire [7:0] setting_value;
wire edge_valid,edge_value,edge_enable;
wire effect_valid,auto_valid,auto_value;wire audio_view_valid,audio_view_value,waveform_mode;wire [4:0] effect_value;
saixian_hmi_uart #(.CLK_FREQ_HZ(75000000)) screen_rx(.clk(pixel_clk),.rst(rst_pixel),.uart_rx(hmi_uart_rx),
 .award_mode_valid(hmi_award_valid),.award_mode_value(hmi_award_value),
 .touch_valid(touch_valid),.touch_x(touch_x),.touch_y(touch_y),.touch_down(touch_down),
 .touch_mode_valid(touch_mode_valid),.touch_mode_value(touch_mode_value),
 .project_valid(hmi_project_valid),.project_value(hmi_project_value),
 .start_pulse(hmi_start),.pause_pulse(hmi_pause),.pause_set_pulse(hmi_pause_set),.resume_pulse(hmi_resume),.finish_pulse(hmi_finish),
 .result_blue_pulse(hmi_result_blue),.result_red_pulse(hmi_result_red),
 .result_sprint_pulse(hmi_result_sprint),.result_stop_pulse(hmi_result_stop),
 .music_next_pulse(hmi_music_next),.prev_pulse(hmi_prev),.next_pulse(hmi_next),.setting_valid(setting_valid),.setting_id(setting_id),.setting_value(setting_value),
 .edge_valid(edge_valid),.edge_value(edge_value),.effect_valid(effect_valid),.effect_value(effect_value),.auto_valid(auto_valid),.auto_value(auto_value),.audio_view_valid(audio_view_valid),.audio_view_value(audio_view_value),
 .reset_defaults_pulse(reset_defaults),.page_id(page_id),.page_notify_pulse(page_notify));
wire audio_repair_enable;wire [3:0] setting_item;wire [3:0] brightness,contrast,saturation,volume;wire [1:0] sharpness,enhancement;wire invert,vintage;
// Match the single-board photo pipeline: enhancement owns the spatial
// smoothing/sharpening control; the later colour stage must not sharpen twice.
photo_unified_settings_controller #(.CLK_FREQ_HZ(75000000),.IMAGE_MENU(0),.POINTER_CONTROL(1),.INTERVAL_CONTROL(1)) settings(.clk(pixel_clk),.rst(rst_pixel),.carousel_mode(carousel_mode),
 .pointer_valid(pointer_row_event),.pointer_item(pointer_item_q),.pointer_increase(pointer_increase_q),
 .key_next_item(presses[0]),.key_decrease(presses[1]),.key_enter_exit((presses[2] || pointer_menu_event) && !result_busy),.key_increase(presses[3]),
 .hmi_setting_valid(setting_valid),.hmi_setting_id(setting_id),.hmi_setting_value(setting_value),.hmi_reset_defaults(reset_defaults),
 .edge_valid(edge_valid),.edge_value(edge_value),.effect_valid(effect_valid),.effect_value(effect_value),.auto_valid(auto_valid),.auto_value(auto_value),.audio_view_valid(audio_view_valid),.audio_view_value(audio_view_value),
 .edge_enable(edge_enable),.effect_select(effect_select),.auto_enable(auto_enable),.auto_interval_seconds(auto_interval_seconds),
 .audio_repair_enable(audio_repair_enable),.waveform_mode(waveform_mode),.settings_mode(settings_mode),.setting_item(setting_item),.volume_setting(volume),.brightness_setting(brightness),.contrast_setting(contrast),
 .saturation_setting(saturation),.sharpness_setting(sharpness),.invert_setting(invert),.vintage_setting(vintage),.enhancement_setting(enhancement));
saixian_event_controller #(.CLK_FREQ_HZ(75000000)) event_controller(.clk(pixel_clk),.rst(rst_pixel),.frame_start(blank_start),
 .key_start(!settings_mode && !result_busy && (hmi_start || (!carousel_mode && (key4_long || presses[0])))),
 .key_pause((!carousel_mode && presses[1]) || (!(award_active && carousel_mode) && (hmi_pause || (hmi_pause_set && event_state==6) || (hmi_resume && event_state==7)))),
 .key_end((!carousel_mode && presses[2]) || hmi_finish),.project_switch(project_select),
 .state(event_state),.project_id(event_project),.minutes(event_minutes),.seconds(event_seconds),
 .countdown_value(countdown_value),.cue_event(cue_event),.carousel_mode(carousel_mode));
reg [27:0] finish_delay;
always @(posedge pixel_clk or posedge rst_pixel)
 if(rst_pixel)finish_delay<=0;else if(event_state!=8)finish_delay<=0;
 else if(finish_delay<150000000)finish_delay<=finish_delay+1'b1;
wire bg_music_enable=(carousel_mode && !result_busy) || (event_state==8 && finish_delay>=150000000);
// Register playback focus: the event-state decoder must not feed the UART
// request/cache-victim control cone in the same pixel-clock cycle.
reg photo_focus;
always @(posedge pixel_clk or posedge rst_pixel)
 if(rst_pixel)photo_focus<=0;
 else photo_focus<=settings_mode || !carousel_mode || award_active || award_loading || result_busy;
reg armed_meta,armed_sync,fault_meta,fault_sync;
always @(posedge pixel_clk or posedge rst_pixel)
 if(rst_pixel)begin armed_meta<=0;armed_sync<=0;fault_meta<=0;fault_sync<=0;end
 else begin armed_meta<=rx_armed;armed_sync<=armed_meta;fault_meta<=rx_fault;fault_sync<=fault_meta;end


wire [3:0] first_transfer_origin,first_transfer_error;
reg [3:0] first_link_fault;
always @(posedge pixel_clk or posedge rst_pixel)
 if(rst_pixel)first_link_fault<=0;
 else if(presses[0] || hmi_next || pointer_next_click || key4_short)first_link_fault<=0;
 else if(fault_sync && first_link_fault==0)first_link_fault<=rx_fault_detail;
photo_auto_advance #(.ADJUSTABLE(1)) auto_advance(.clk(pixel_clk),.rst(rst_pixel),.enable(auto_enable && carousel_mode && !award_active && !award_loading && !result_busy),
 .display_valid(display_valid),.transition_active(transition_active),.busy(busy),.enough_images(count>1),
 .settings_mode(settings_mode),.manual_event(presses[0] || key4_short || hmi_next || pointer_next_click || reset_defaults),
 .interval_seconds(auto_interval_seconds),.next_pulse(auto_next));
photo_event_sync sd(.clk(pixel_clk),.rst(rst_pixel),.toggle(done_toggle),.pulse(done_pixel));
reg done_pixel_registered;
always @(posedge pixel_clk or posedge rst_pixel)
 if(rst_pixel)done_pixel_registered<=0;else done_pixel_registered<=done_pixel;
wire [18:0] image_settings={1'b0,brightness,contrast,saturation,sharpness,enhancement,invert,vintage};
// Register gated navigation events before the cache's adjacency/priority logic.
// One-clock event staging removes result-state decoding from that long path.
reg photo_next_event,photo_award_event,photo_relief_event;
always @(posedge pixel_clk or posedge rst_pixel)
 if(rst_pixel)begin photo_next_event<=0;photo_award_event<=0;photo_relief_event<=0;end
 else begin
  photo_next_event<=carousel_mode && !settings_mode && !result_busy && (presses[0] || hmi_next || pointer_next_click || auto_next);
  photo_award_event<=carousel_mode && !settings_mode && !result_busy && !award_loading &&
   ((hmi_award_valid && !hmi_award_value) || (key4_short && (current>=6 || (!relief_available && award_scan_complete))));
  photo_relief_event<=carousel_mode && !settings_mode && !result_busy && !award_loading &&
   ((hmi_award_valid && hmi_award_value) || (key4_short && current<6 && (relief_available || !award_scan_complete)));
 end
wire settings_updating;
wire timing_begin,timing_present,timing_commit,timing_cancel,timing_running,timing_valid;
wire [19:0] timing_wait_ms,timing_effect_ms,timing_total_ms;
wire [5:0] timing_seg_sel,base_seg_sel;wire [7:0] timing_seg_data,base_seg_data;
photo_switch_timing #(.CLK_HZ(75000000),.PHASES(2)) timing_probe(.clk(pixel_clk),.rst(rst_pixel),
 .start(timing_begin),.mark1(timing_present),.mark2(1'b0),.finish(timing_commit),.cancel(timing_cancel),
 .running(timing_running),.valid(timing_valid),.first_ms(timing_wait_ms),.second_ms(timing_effect_ms),.third_ms(),.total_ms(timing_total_ms));
photo_switch_timing_display #(.CLK_HZ(75000000),.PAGES(3)) timing_display(.clk(pixel_clk),.rst(rst_pixel),.running(timing_running),
 .first_ms(timing_wait_ms),.second_ms(timing_effect_ms),.third_ms(20'd0),.total_ms(timing_total_ms),.seg_sel(timing_seg_sel),.seg_data(timing_seg_data));
photo_cached_control_a #(.CHECK_FRAME_CRC(1),.SETTINGS_LINK(1),.AWARD_CONTROL(1),.FLUID(1),.AWARD_LIGHTS(1),.EARLY_THUMBNAIL(1),.RELIEF_CONTROL(1)) ctrl(.receive_relief(receive_relief),.receive_award(receive_award),.receive_fluid(receive_fluid),.settings_mode(photo_focus),.settings_state(image_settings),.settings_updating(settings_updating),.clk(pixel_clk),.rst(rst_pixel),.uart_rx(control_rx),.uart_tx(control_tx),
 .thumbnail_read_busy(thumbnail_read_busy),.thumbnail_read_slot(thumbnail_slot),
 .timing_begin(timing_begin),.timing_present(timing_present),.timing_commit(timing_commit),.timing_cancel(timing_cancel),
 .award_toggle(photo_award_event),.relief_toggle(photo_relief_event),.relief_available(relief_available),.award_available(award_available),.award_scan_complete(award_scan_complete),.award_loading(award_loading),.award_notice(award_notice),.last_transfer_error(last_transfer_error),
 .first_transfer_origin(first_transfer_origin),.first_transfer_error(first_transfer_error),
 .previous(1'b0),.next(photo_next_event),
 .active_slot(active_slot),.new_slot(new_slot),.transition_active(transition_active),.commit_toggle(frame_commit),
 .receive_slot(receive_slot),.arm_toggle(arm_toggle),.abort_toggle(abort_toggle),.rx_armed(armed_sync),.rx_done(done_pixel_registered),
 .ready_immediate(ready_immediate),.rx_fault(fault_sync),.rx_crc(rx_crc),.ready_toggle(ready_toggle),.ready_slot(ready_slot),.ready_right(ready_right),
 .image_count(count),.current_image(current),.busy(busy),.error(error),.debug_state(control_state),
 .thumbnail_valid(thumbnail_cache_valid),.thumbnail_slot(thumbnail_cache_slot),.thumbnail_id(thumbnail_id),
 .current_source_width(current_source_width),.current_source_height(current_source_height));
wire page_turn_cue;wire [3:0] page_turn_style;
photo_transition_page_event page_feedback(.clk(pixel_clk),.rst(rst_pixel),
 .enable(carousel_mode && !settings_mode && !award_active && !award_loading && !result_busy && !boot_active),
 .transition_active(transition_active),.transition_mode(transition_mode),.page_style(page_turn_style),
 .display_valid(display_valid),.image(current),.count(count),.page_event(page_turn_cue));
wire [2:0] music_count,music_index;wire [7:0] music_epoch;
wire [3:0] audio_diag_stage,audio_buffer_level;wire audio_header_seen,audio_pcm_seen,audio_nonzero_seen;
water_scene dwell_water(.clk(pixel_clk),.rst(rst_image_pixel),.frame_tick(blank_start),
 .display_valid(display_valid),.transition_active(transition_active),
 .wave_enable(carousel_mode && !settings_mode && !award_active && !award_loading && !result_busy && !boot_active && !settings_updating),
 .manual_drop(1'b0),.progress(fluid_progress),.cfg(fluid_configuration));
wire music_buffer_ready,music_catalog_complete;reg startup_released;
wire audio_sample_valid;wire [23:0] audio_left,audio_right;wire [15:0] audio_packet_errors,audio_underflows;
wire av_available,av_begin,av_word_valid,av_commit,av_finish,av_stream_reset;
wire [8:0] av_word_index;wire [31:0] av_word,av_play_position;
photo_audio_spi_a #(.STARTUP_SYNC(1),.FIFO_AW(11),.FIFO_RAM32_HEAD(2048),.EXTENDED_AV(1),.PAGE_CUE(1),.TYPED_PAGE(1)) audio_link(.page_style(page_turn_style),.page_event(page_turn_cue),.playback_hold(!startup_released),.buffer_ready(music_buffer_ready),.catalog_complete(music_catalog_complete),.clk(pixel_clk),.rst(rst_pixel),.bg_enable(bg_music_enable),.repair_enable(audio_repair_enable),.volume(volume),.cue_event(cue_event),
 .next_track(carousel_mode && !result_busy && ((!settings_mode && !award_active && presses[1]) || hmi_music_next)),
 .spi_miso(audio_miso),.spi_sclk(audio_sclk),.spi_cs(audio_cs),.spi_mosi(audio_mosi),
 .track_count(music_count),.track_index(music_index),.desired_epoch(music_epoch),
 .diagnostic_stage(audio_diag_stage),.buffer_level(audio_buffer_level),.header_seen(audio_header_seen),.pcm_seen(audio_pcm_seen),.nonzero_seen(audio_nonzero_seen),
 .sample_valid(audio_sample_valid),.audio_left(audio_left),.audio_right(audio_right),.packet_errors(audio_packet_errors),.underflows(audio_underflows),
 .av_available(av_available),.av_begin(av_begin),.av_word_valid(av_word_valid),.av_commit(av_commit),.av_finish(av_finish),
 .av_word_index(av_word_index),.av_word(av_word),.play_position(av_play_position),.stream_reset(av_stream_reset));
// Keep the known 21-cycle RGB path; send aligned AXI pixels to the single-board
// HDMI core, including an exact last-pixel marker and first-frame marker.
wire [11:0] raster_x21,raster_x26,raster_x34;
wire [10:0] raster_y21,raster_y26,raster_y34;
wire raster_valid21,raster_valid26,raster_valid34;
// Stop admitting long preview turns 256 pixels before blanking ends.
// Already-owned turns drain normally; the display FIFO reserve still wins.
assign thumbnail_blank=raster_valid26 && raster_y26>=11'd720 &&
 !(raster_y26==11'd749 && raster_x26>=12'd1394);
wire [8:0] raster_ui_y;
photo_raster_delay #(.DELAY(21),.SCALE_Y(1)) raster21(.clk(pixel_clk),.rst(rst_pixel),.x(raster_x21),.y(raster_y21),.valid(raster_valid21),.y_two_thirds(raster_ui_y));
photo_raster_delay #(.DELAY(26)) raster26(.clk(pixel_clk),.rst(rst_pixel),.x(raster_x26),.y(raster_y26),.valid(raster_valid26));
photo_raster_delay #(.DELAY(34)) raster34(.clk(pixel_clk),.rst(rst_pixel),.x(raster_x34),.y(raster_y34),.valid(raster_valid34));
wire raster_de21=raster_valid21 && raster_x21<1280 && raster_y21<720;
wire raster_de26=raster_valid26 && raster_x26<1280 && raster_y26<720;
wire raster_sof26=raster_valid26 && raster_x26==0 && raster_y26==0;
wire raster_last26=raster_de26 && raster_x26==1279;
wire raster_vs26=raster_valid26 && raster_y26>=725 && raster_y26<730;
wire raster_tick26=raster_valid26 && raster_x26==0 && raster_y26==720;
wire raster_sof34=raster_valid34 && raster_x34==0 && raster_y34==0;
wire raster_last34=raster_valid34 && raster_x34==1279 && raster_y34<720;
wire acr_valid;wire [19:0] acr_cts,acr_n;
audio_arc_calculate #(.ACR_N(6144)) acr(.I_clk(pixel_clk),.I_rst(rst_pixel),.I_audio_valid(audio_sample_valid),.O_acr_valid(acr_valid),.O_acr_cts(acr_cts),.O_acr_n(acr_n));
reg hpd_audio_meta,hpd_audio_sync,hpd_audio_previous;
always @(posedge pixel_clk or posedge rst_pixel)begin
 if(rst_pixel)begin hpd_audio_meta<=0;hpd_audio_sync<=0;hpd_audio_previous<=0;end
 else begin hpd_audio_meta<=hdmi_hpd;hpd_audio_sync<=hpd_audio_meta;hpd_audio_previous<=hpd_audio_sync;end
end
wire [23:0] result_rgb;wire result_de,result_vs;
// Capture the complete command gates before the result renderer's pixel
// registers. Events settle one clock later; the video pipeline is unchanged.
reg result_select_blue_q,result_select_red_q,result_select_sprint_q;
reg result_trigger_q,result_stop_q,result_frame_tick_q;
always @(posedge pixel_clk or posedge rst_pixel)
 if(rst_pixel)begin
  result_select_blue_q<=0;result_select_red_q<=0;result_select_sprint_q<=0;
  result_trigger_q<=0;result_stop_q<=0;result_frame_tick_q<=0;
 end
 else begin
  result_trigger_q<=(result_busy && carousel_mode && !settings_mode) && (presses[0] || hmi_next);
  result_stop_q<=hmi_result_stop || (key4_long && result_busy);
  result_frame_tick_q<=raster_tick26;
  result_select_blue_q<=(hmi_result_blue || (result_busy && presses[1])) && carousel_mode && !settings_mode && !award_active && !award_loading;
  result_select_red_q<=(hmi_result_red || (result_busy && presses[2])) && carousel_mode && !settings_mode && !award_active && !award_loading;
  result_select_sprint_q<=(hmi_result_sprint || key4_long) && carousel_mode && !settings_mode && !award_active && !award_loading;
 end
saixian_battle_result_fx u_result_animation(
 .clk(pixel_clk),.rst(rst_pixel),.frame_tick(result_frame_tick_q),
 .trigger(result_trigger_q),
 .select_blue(result_select_blue_q),
 .select_red(result_select_red_q),
  .select_sprint(result_select_sprint_q),
  .stop(result_stop_q),.busy(result_busy),.sprint_active(result_sprint_active),
 .sprint_background_valid(display_valid),.x_in(raster_x26[10:0]),.y_in(raster_y26[9:0]),
 .de_in(raster_de26),.vs_in(raster_vs26),.rgb_in(feature_rgb),
 .de_out(result_de),.vs_out(result_vs),.rgb_out(result_rgb));
wire edge_de,edge_sof,edge_last;wire [23:0] edge_rgb;wire [7:0] edge_level,edge_target;
// Stage the scene-state decode before the edge renderer's pixel datapath.
// This changes only control settling by one clock; RGB/DE/SOF/EOL stay aligned.
reg music_drive_q;
always @(posedge pixel_clk or posedge rst_pixel)
 if(rst_pixel)music_drive_q<=0;
 else music_drive_q<=edge_enable && carousel_mode && !settings_mode && !award_active && !award_loading && !result_busy && !boot_active && display_valid;
// Edge light has a fixed five-clock RGB/DE/SOF/EOL pipeline, even when disabled.
water_edge #(.EXTERNAL_ENVELOPE(1)) music_edge(.clk(pixel_clk),.rst(rst_pixel),.frame_tick(blank_start),.external_target(edge_target),
 .music_drive(music_drive_q),
 .pcm_valid(audio_sample_valid),.pcm_left(audio_left[23:8]),.pcm_right(audio_right[23:8]),
 .x(raster_x34[10:0]),.y(raster_y34[9:0]),.de(result_de),.sof(raster_sof34),.eol(raster_last34),
 .rgb(result_rgb),.darkness(6'd0),.de_out(edge_de),.sof_out(edge_sof),.eol_out(edge_last),.rgb_out(edge_rgb),.level(edge_level));
wire [9:0] hdmi_clock_data;wire axis_ready,hdmi_video_locked;
hdmi_1_4b_transmitter_core_wrapper #(.DEVICE("EG"),.HTOTAL(1650),.HSA(40),.HFP(110),.HBP(220),.HACTIVE(1280),
 .VTOTAL(750),.VSA(5),.VFP(5),.VBP(20),.VACTIVE(720),.VIDEO_VIC(4),.VIDEO_TPG("Disable"),.VIDEO_FORMAT("RGB"),.AUDIO_SAMPLE_RATE("48K"),.IIC_SCL_DIV(375)) audio_hdmi(
 .I_pixel_clk(pixel_clk),.I_rst(rst_pixel),.I_edid_read_trig(hpd_audio_sync && !hpd_audio_previous),.O_edid_read_valid(),.O_edid_read_data(),
 .I_axis_s_user(edge_sof),.I_axis_s_valid(edge_de),.I_axis_s_last(edge_last),.I_axis_s_data(edge_rgb),.O_axis_s_ready(axis_ready),
 .I_audio_valid(audio_sample_valid),.I_audio_left_data(audio_left),.I_audio_right_data(audio_right),.I_acr_valid(acr_valid),.I_acr_cts(acr_cts),.I_acr_n(acr_n),.O_video_locked(hdmi_video_locked),
 .O_ddc_scl(HDMI_DDC_SCL),.IO_ddc_sda(HDMI_DDC_SDA),.O_ch0_tmds_data(blue),.O_ch1_tmds_data(green),.O_ch2_tmds_data(red),.O_clk_tmds_data(hdmi_clock_data));
saixian_hmi_status_tx #(.CLK_FREQ_HZ(75000000),.ENHANCEMENT_FEEDBACK(1)) screen_tx(.clk(pixel_clk),.rst(rst_pixel),.image_count(count),
 .audio_count(music_count),.error_code(error>7 ? 3'd7:error[2:0]),.initializing(count==0),.page_id(page_id),
 .refresh_request(page_notify || setting_valid || reset_defaults),.sharpness(sharpness),.brightness(brightness),.contrast(contrast),
 .saturation(saturation),.volume(volume),.invert(invert),.vintage(vintage),.enhancement(enhancement),.event_state(event_state),.minutes(event_minutes),.seconds(event_seconds),
 .uart_tx(hmi_uart_tx),.command_sent_pulse());
// Image enhancement/adjustment is already performed on B. Keep the
// established 2+15+4=21 clocks without a second neutral processing engine.
reg [1:0] de_pipe;reg [10:0] x0,x1;reg [9:0] y0,y1;
always @(posedge pixel_clk or posedge rst_pixel)
 if(rst_pixel)begin de_pipe<=0;x0<=0;x1<=0;y0<=0;y1<=0;end
 else begin de_pipe<={de_pipe[0],de};x0<=x[10:0];x1<=x0;y0<=y[9:0];y1<=y0;end
wire [23:0] neutral_rgb,range_rgb;
photo_neutral_delay neutral(.clk(pixel_clk),.rst(rst_pixel),.de(de_pipe[1]),.rgb_in(raw_rgb),.rgb_out(neutral_rgb));
photo_display_fade display_fade(.clk(pixel_clk),.rst(rst_pixel),.darkness(darkness),.rgb_in(neutral_rgb),.rgb_out(range_rgb));
photo_settings_overlay #(.VIDEO_DELAY(21),.INTERVAL_CONTROL(1)) menu_overlay(.clk(pixel_clk),.rst(rst_pixel),.frame_tick(blank_start),
 .x(x),.y(y),.de(de),.settings_mode(settings_mode),.setting_item(setting_item),.updating(settings_updating),
 .edge_enable(edge_enable),.audio_repair_enable(audio_repair_enable),.volume(volume),.waveform_mode(waveform_mode),.brightness(brightness),.contrast(contrast),.saturation(saturation),.sharpness(sharpness),.enhancement(enhancement),
 .invert(invert),.vintage(vintage),.effect(effect_select),.auto_enable(auto_enable),.auto_interval_seconds(auto_interval_seconds),
 .rgb_in(award_menu_select_q ? award_menu_rgb:range_rgb),.rgb_out(menu_notice_rgb));
// Lock the slow status decode in blanking, before the combinational banner.
reg [2:0] frame_award_notice;
always @(posedge pixel_clk or posedge rst_pixel)
 if(rst_pixel)frame_award_notice<=0;
 else if(blank_start)frame_award_notice<=carousel_mode && !settings_mode ? (award_loading ? 3'd1:award_notice):3'd0;
photo_award_notice award_notice_osd(.clk(pixel_clk),.rst(rst_pixel),.notice(frame_award_notice),
 .x(raster_x21),.y(raster_y21),.rgb_in(menu_notice_rgb),.rgb_out(final_rgb));
reg settings_render_mode;
always @(posedge pixel_clk or posedge rst_pixel)
 if(rst_pixel)settings_render_mode<=0;else if(blank_start)settings_render_mode<=settings_mode;
// begin DISPLAY_CONTROL_STAGE
// Register scene selection before the wide RGB multiplexers. Only control
// settling changes by one clock; all RGB/DE/coordinate pipelines stay intact.
always @(posedge pixel_clk or posedge rst_pixel)
 if(rst_pixel)begin
  award_menu_select_q<=0;award_display_select_q<=0;preview_enable_q<=0;pointer_nav_display_q<=0;
 end else begin
  award_menu_select_q<=award_active;
  award_display_select_q<=award_active && carousel_mode && !settings_render_mode;
  preview_enable_q<=display_valid && carousel_mode && !boot_active && !settings_mode && !result_busy && !award_active && !award_loading;
  pointer_nav_display_q<=pointer_navigation_enable;
 end
// end DISPLAY_CONTROL_STAGE

reg [9:0] ui_x;reg [8:0] ui_y;reg ui_de;reg [23:0] ui_rgb;
always @(posedge pixel_clk or posedge rst_pixel)begin
 if(rst_pixel)begin ui_x<=0;ui_y<=0;ui_de<=0;ui_rgb<=0;end
 else begin ui_x<=raster_x21[10:1];ui_y<=raster_ui_y;ui_rgb<=final_rgb;
  ui_de<=raster_de21 && !settings_render_mode;end
end
wire [10:0] ui_font_addr;wire [15:0] ui_font_bits;
saixian_font_rom ui_font(.clk(pixel_clk),.glyph_id(ui_font_addr[10:4]),.row(ui_font_addr[3:0]),.bits(ui_font_bits));
reg [10:0] ticker_x;
always @(posedge pixel_clk or posedge rst_pixel)
 if(rst_pixel)ticker_x<=0;else if(blank_start)ticker_x<=ticker_x>=864 ? 0:ticker_x+1'b1;
// Analyze the same post-mix, post-volume PCM delivered to HDMI.
wire [9:0] visual_x=ui_x-10'd64;
wire [6:0] visual_height,visual_peak;wire [31:0] visual_wave;
wire visual_fft_valid,visual_wave_valid;
photo_av_metadata_a #(.EDGE_METADATA(1)) visual_cache(.clk(pixel_clk),.rst(rst_pixel || av_stream_reset),.frame_tick(blank_start),.edge_target(edge_target),
 .play_position(av_play_position),.begin_packet(av_begin),.word_valid(av_word_valid),.commit_packet(av_commit),.finish_packet(av_finish),
 .word_index(av_word_index),.word_data(av_word),.available(av_available),
 .read_band(visual_x[8:4]),.read_index(visual_x[8:1]),.height(visual_height),.peak(visual_peak),.extrema(visual_wave),
 .fft_valid(visual_fft_valid),.wave_valid(visual_wave_valid));
saixian_osd_overlay #(.SHOW_SOURCE_RESOLUTION(0)) music_event_ui(.clk(pixel_clk),.rst(rst_pixel),.frame_tick(blank_start),.de_i(ui_de),
 .x_i(ui_x),.y_i(ui_y),.rgb_in_i(ui_rgb),.display_valid(display_valid || music_count!=0 || !carousel_mode),
 .loading_phase(3'd0),.state(event_state),.project_id(carousel_mode ? project_select:event_project),
 .minutes(event_minutes),.seconds(event_seconds),.countdown_value(countdown_value),.ticker_x(ticker_x),
 .ticker_text_length(5'd0),.title_text_length(5'd0),.font_addr(ui_font_addr),.font_bits(ui_font_bits),.font_ready(1'b1),
 .source_width_bcd(16'd0),.source_height_bcd(16'd0),.error_code(3'd0),
 .visual_height(visual_height),.visual_peak(visual_peak),.visual_wave(visual_wave),
 .visual_fft_valid(visual_fft_valid),.visual_wave_valid(visual_wave_valid),
 .waveform_mode(waveform_mode),.settings_mode(1'b0),.setting_item(3'd0),
 .volume_setting(volume),.brightness_setting(brightness),.contrast_setting(contrast),.sharpness_setting(sharpness),
 .saturation_setting(saturation),.invert_setting(invert),.vintage_setting(vintage),.enhancement_setting(enhancement),
 .rgb_out(music_ui_rgb));
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
// Bypass photo fades and music graphics for the full scene.
photo_award_render #(.RELIEF_ENABLE(1)) award_render(
 .relief_mode(current==7),.touch_contact(pointer_contact),.cursor_x(cursor_x),.cursor_y(cursor_y),.mem_clk(mem_clk),.mem_rst(rst_image_mem),.light_base(light_base),
 .light_wide(light_wide),.light_request(light_request),.light_address(light_address),.light_ack(light_ack),.light_data(light_data),.light_valid(light_valid),
 .de_in(award_raw_de[1]),.clk(pixel_clk),.rst(rst_pixel),.enable(award_active),
 .pause(award_pause || settings_mode),.frame_tick(blank_start),.x(x1),.y(y1),
 .tagged_rgb(raw_rgb),.rgb(award_rgb),.menu_rgb(award_menu_rgb),
 .light_error(award_light_error),.light_frame(award_light_frame));
always @(posedge pixel_clk or posedge rst_pixel)
 if(rst_pixel)award_pause<=0;
 else if(!award_active)award_pause<=0;
 else if(hmi_resume)award_pause<=0;
 else if(hmi_pause_set)award_pause<=1;
 else if(hmi_pause || (!settings_mode && carousel_mode && presses[1]))award_pause<=!award_pause;
wire [23:0] playback_rgb=award_display_select_q ? award_rgb:
 (menu_bypass_select[4] ? menu_bypass_rgb[4]:music_ui_rgb);
wire [23:0] boot_rgb;
// Release audio at the first visible frame after the loading UI exits.
always @(posedge pixel_clk or posedge rst_pixel)
 if(rst_pixel)startup_released<=0;
 else if(!boot_active && de && x==0 && y==0)startup_released<=1;
wire boot_audio_ready=music_buffer_ready || (music_catalog_complete && music_count==0);
(* async_reg="true" *)reg boot_init_meta,boot_init_sync;
always @(posedge pixel_clk or posedge rst_pixel)
 if(rst_pixel)begin boot_init_meta<=0;boot_init_sync<=0;end
 else begin boot_init_meta<=init_done;boot_init_sync<=boot_init_meta;end
// Animation ROMs are configured with the FPGA, rather than loaded from TF.
// Wait for the local renderer pipeline to leave reset before declaring ready.
reg [3:0] boot_animation_warmup;
always @(posedge pixel_clk or posedge rst_pixel)
 if(rst_pixel)boot_animation_warmup<=0;
 else if(!(&boot_animation_warmup))boot_animation_warmup<=boot_animation_warmup+1'b1;
photo_boot_screen #(.VIDEO_DELAY(26),.MIN_FRAMES(90),.STAGED_LOADING(1)) boot_screen(
 .clk(pixel_clk),.rst(rst_pixel),.frame_tick(blank_start),.x(x),.y(y),
 .memory_ready(boot_init_sync),.catalog_ready(count!=0 || award_available || relief_available),
 .animation_ready(&boot_animation_warmup),.audio_ready(boot_audio_ready),
 .frame_ready(display_valid && started),.active(boot_active),.rgb(boot_rgb));
wire [23:0] pointer_rgb;
wire [23:0] thumbnail_rgb;
photo_thumbnail_overlay #(.X(THUMBNAIL_X),.Y(THUMBNAIL_Y),.DELAY(1),.SEPARATE_DISPLAY(1)) preview(.clk(pixel_clk),.rst(rst_image_pixel),.frame_tick(blank_start),
 .enable(preview_enable_q),
 .display_enable(!settings_updating && !transition_active),.read_busy(thumbnail_read_busy),
 .cache_valid(thumbnail_cache_valid),.cache_slot(thumbnail_cache_slot),.identity({1'b0,thumbnail_id,thumbnail_cache_slot}),
 .de(raster_de26),.x(raster_x26),.y(raster_y26),.request(thumbnail_request),.slot(thumbnail_slot),.cancel(thumbnail_cancel),
 .done(thumbnail_done),.data(thumbnail_data),.address(thumbnail_address),.visible(thumbnail_visible),
 .rgb_in(playback_rgb),.rgb_out(thumbnail_rgb));
photo_pointer_overlay #(.DELAY(5),.NAVIGATION_BUTTON(0)) pointer_osd(.clk(pixel_clk),.rst(rst_pixel),.frame_tick(blank_start),
 .enable(pointer_enabled),.navigation_enable(pointer_nav_display_q),.de(raster_de21),.x(raster_x21),.y(raster_y21),.cursor_x(cursor_x),.cursor_y(cursor_y),
 .rgb_in(thumbnail_rgb),.rgb_out(pointer_rgb));
assign feature_rgb=boot_active ? boot_rgb:pointer_rgb;
hdmi_phy_wrapper #(.DEVICE("EG")) u_hdmi_phy(.I_pixel_clk(pixel_clk),.I_serial_clk(serial_clk),.I_rst(rst_serial),
 .I_tmds_channel_0(blue),.I_tmds_channel_1(green),.I_tmds_channel_2(red),.I_tmds_channel_clk(hdmi_clock_data),
 .O_tmds_ch0_p(HDMI_D0_P),.O_tmds_ch1_p(HDMI_D1_P),.O_tmds_ch2_p(HDMI_D2_P),.O_tmds_clk_p(HDMI_CLK_P));
wire scan_valid,scan_fault,clock_valid,clock_fault;
hdmi_scan_monitor #(.HT(1650),.VT(750),.HA(1280),.VA(720),.HS(40),.VS(5)) u_scan(
 .clk(pixel_clk),.rst(rst_pixel),.x(x),.y(y),.de(de),.hs(hs),.vs(vs),.frame_start(fs),.valid(scan_valid),.fault(scan_fault));
hdmi_pixel_clock_monitor #(.EXPECTED_PIXELS(7500000),.TOLERANCE_PIXELS(75000)) u_clock_check(
 .ref_clk(clk),.pixel_clk(pixel_clk),.arst(!video_lock),.valid(clock_valid),.fault(clock_fault));
// Preserve the first image fault until startup succeeds. Audio readiness
// must not hide why the loading screen is still waiting for its first frame.
reg [3:0] startup_first_error;
always @(posedge pixel_clk or posedge rst_pixel)
 if(rst_pixel)startup_first_error<=0;
 else if(!startup_released && startup_first_error==0 && error!=0)startup_first_error<=error;
wire [15:0] startup_failure_digits={4'd8,4'd0,control_state,startup_first_error};
reg hpd_meta,hpd_sync;reg [17:0] status_meta,status_sync;
reg [19:0] audio_diag_meta,audio_diag_sync;
reg [15:0] award_diag_meta,award_diag_sync;
reg menu_meta,menu_sync;reg [15:0] menu_digits_meta,menu_digits_sync;
// photo_status shifts nibble 0 out first, so encode the displayed order in reverse.
wire [15:0] menu_digits={4'd0,{3'b000,auto_enable},effect_select[3:0],setting_item};
always @(posedge clk or posedge rst_ref)
 if(rst_ref)begin hpd_meta<=0;hpd_sync<=0;status_meta<=0;status_sync<=0;
  award_diag_meta<=0;award_diag_sync<=0;audio_diag_meta<=0;audio_diag_sync<=0;menu_meta<=0;menu_sync<=0;menu_digits_meta<=0;menu_digits_sync<=0;end
 else begin hpd_meta<=hdmi_hpd;hpd_sync<=hpd_meta;
  audio_diag_meta<={audio_diag_stage,{1'b0,music_count},(music_count!=0 ? {1'b0,music_index}+4'd1:4'd0),audio_buffer_level,
   {1'b0,audio_nonzero_seen,hdmi_video_locked,hpd_audio_sync}};
  audio_diag_sync<=audio_diag_meta;
  // Award playback: 4 6 E FF C (E=light error, FF=field 00..77).
  // Preserve earlier transfer/startup faults ahead of this live diagnostic.
  award_diag_meta<=first_transfer_origin!=0 ? {4'd4,first_transfer_origin,first_transfer_error,(first_transfer_origin==2 ? first_link_fault:4'd0)}:(!startup_released && startup_first_error!=0) ? startup_failure_digits:award_active ? {4'd6,award_light_error,1'b0,award_light_frame}:{1'b0,(award_loading ? 3'd1:award_notice),3'd0,award_available,3'd0,award_scan_complete,((award_notice==3 || award_notice==4) ? last_transfer_error:error)};award_diag_sync<=award_diag_meta;
  menu_meta<=settings_mode;menu_sync<=menu_meta;
  menu_digits_meta<=menu_digits;menu_digits_sync<=menu_digits_meta;
  status_meta<={count,(display_valid ? current+3'd1:3'd0),control_state,error,
   (error!=0 || underflow || scan_fault || clock_fault ? 4'd9:busy ? 4'd3:display_valid ? 4'd5:4'd2)};
  status_sync<=status_meta;end
photo_status #(.CLK_HZ(50000000)) status(.clk(clk),.rst(rst_ref),.status(menu_sync ? (hpd_sync ? status_sync[3:0]:4'd0):audio_diag_sync[3:0]),
 .error(status_sync[7:4]),.state(status_sync[11:8]),.image(status_sync[14:12]),.count(status_sync[17:15]),
 .diagnostic_page(menu_sync ? 3'd1:award_diag_sync[15:12]!=0 ? 3'd4:3'd5),.diagnostic_crc(menu_sync ? menu_digits_sync:award_diag_sync[15:12]!=0 ? award_diag_sync:audio_diag_sync[19:4]),.seg_sel(base_seg_sel),.seg_data(base_seg_data));
wire show_timing=timing_valid && !settings_mode && !award_active && !award_loading &&
 first_transfer_origin==0 && startup_first_error==0 && error==0;
assign seg_sel=show_timing ? timing_seg_sel:base_seg_sel;
assign seg_data=show_timing ? timing_seg_data:base_seg_data;

endmodule
