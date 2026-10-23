`timescale 1ns/1ps
module top_photo_b(
 input clk,key2_n,sd_miso,control_rx,output control_tx,sd_ncs,sd_dclk,sd_mosi,
 output link_clk,output [15:0] link_data,output link_valid,link_sof,link_eof,
 input link_ready,audio_sclk,audio_cs,audio_mosi,output audio_miso,output transfer_done,transfer_error,
 output [5:0] seg_sel,output [7:0] seg_data);
wire audio_packet_active,audio_request_valid,audio_switching,audio_fifo_read;
wire audio_raw_read,audio_stream_reset;wire [7:0] requested_audio_epoch,active_audio_epoch;
(* async_reg="true" *)reg award_meta,award_sync;
wire award_available,award_scan_complete;wire [3:0] award_decode_error;



wire sd_clk,mem_clk,mem_clk_sft,sys_lock,link_lock,rst_sd,rst_mem,rst_link;
sys_pll u_sys_pll(.refclk(clk),.reset(1'b0),.clk0_out(sd_clk),.clk1_out(mem_clk),.clk2_out(mem_clk_sft),.locked(sys_lock));
builtin_link_pll u_link_pll(.refclk(clk),.reset(1'b0),.clk0_out(link_clk),.locked(link_lock));
dual_still_reset_sync rs(.clk(sd_clk),.arst(!sys_lock || !link_lock),.rst(rst_sd));
dual_still_reset_sync rm(.clk(mem_clk),.arst(!sys_lock),.rst(rst_mem));
dual_still_reset_sync rl(.clk(link_clk),.arst(!link_lock || !sys_lock),.rst(rst_link));
wire audio_request_repair;wire [3:0] audio_scan_state;wire audio_sample_prepare,audio_bg_enabled,audio_request_bg;
wire [2:0] audio_page_cue_count;wire audio_page_valid,audio_page_ready;wire [3:0] audio_page_style;
wire [3:0] audio_request_volume,audio_request_cue;wire [31:0] processed_audio;reg audio_request_seen;
always @(posedge sd_clk or posedge rst_sd)
 if(rst_sd)audio_request_seen<=0;else if(audio_request_valid)audio_request_seen<=1;

wire [2:0] requested_audio_track,active_audio_track,audio_count;wire [13:0] audio_fifo_used;wire [31:0] audio_fifo_data;
wire [13:0] pitch_fifo_used;wire [31:0] pitched_audio;
wire [2:0] pitch_mode,pitch_active_mode;wire pitch_ready,pitch_overrun;
photo_pitch_keys pitch_control(.clk(sd_clk),.rst(rst_sd),.key2_n(key2_n),.mode(pitch_mode));
photo_audio_pitch_b pitch_processing(.clk(sd_clk),.rst(rst_sd),
 .stream_clear(audio_stream_reset || !audio_bg_enabled),
 .enable(audio_count!=0 && !audio_switching),.repair_enable(audio_request_repair),
 .requested_mode(pitch_mode),.raw_used(audio_fifo_used),.raw_pcm(audio_fifo_data),.raw_read(audio_raw_read),
 .output_read(audio_fifo_read),.output_pcm(pitched_audio),.output_used(pitch_fifo_used),
 .ready(pitch_ready),.overrun(pitch_overrun),.active_mode(pitch_active_mode));
wire av_pcm_sent,av_snapshot;wire [8:0] av_address;wire [31:0] av_data;
// The serial-analysis datapath fits the existing 50 MHz domain. Transfer
// sparse events with toggles and hold each PCM bundle until the next sample.
wire av_reset_request=rst_sd || audio_switching || requested_audio_epoch!=active_audio_epoch;
wire av_analysis_rst,av_pcm_event,av_snapshot_event;
reg av_pcm_valid;
// Allow the two bundle samplers an extra clock before consuming the event.
// This also covers a one-clock difference in first-stage sampling at an edge.
always @(posedge mem_clk or posedge av_analysis_rst)
 if(av_analysis_rst)av_pcm_valid<=0;else av_pcm_valid<=av_pcm_event;
reg av_pcm_toggle,av_snapshot_toggle;reg [31:0] av_pcm_hold;
always @(posedge sd_clk or posedge rst_sd)
 if(rst_sd)begin av_pcm_toggle<=0;av_snapshot_toggle<=0;av_pcm_hold<=0;end
 else if(av_reset_request)begin av_pcm_toggle<=0;av_snapshot_toggle<=0;av_pcm_hold<=0;end
 else begin
  if(av_pcm_sent)begin av_pcm_toggle<=~av_pcm_toggle;av_pcm_hold<=processed_audio;end
  if(av_snapshot)av_snapshot_toggle<=~av_snapshot_toggle;
 end
dual_still_reset_sync av_reset_sync(.clk(mem_clk),.arst(av_reset_request),.rst(av_analysis_rst));
photo_event_sync av_sample_sync(.clk(mem_clk),.rst(av_analysis_rst),.toggle(av_pcm_toggle),.pulse(av_pcm_event));
photo_event_sync av_publish_sync(.clk(mem_clk),.rst(av_analysis_rst),.toggle(av_snapshot_toggle),.pulse(av_snapshot_event));
(* async_reg="true" *)reg [8:0] av_address_meta,av_address_sync;
(* async_reg="true" *)reg [31:0] av_pcm_meta,av_pcm_sync;
(* async_reg="true" *)reg [31:0] av_data_meta,av_data_sync;
always @(posedge mem_clk or posedge rst_mem)
 if(rst_mem)begin av_address_meta<=0;av_address_sync<=0;av_pcm_meta<=0;av_pcm_sync<=0;end
 else begin av_address_meta<=av_address;av_address_sync<=av_address_meta;av_pcm_meta<=av_pcm_hold;av_pcm_sync<=av_pcm_meta;end
always @(posedge sd_clk or posedge rst_sd)
 if(rst_sd)begin av_data_meta<=0;av_data_sync<=0;end
 else begin av_data_meta<=av_data;av_data_sync<=av_data_meta;end
photo_av_metadata_b #(.EDGE_METADATA(1)) audio_analysis(.clk(mem_clk),.rst(av_analysis_rst),
 .pcm_sent(av_pcm_valid),.snapshot(av_snapshot_event),.pcm(av_pcm_sync),.address(av_address_sync),.data(av_data));
photo_audio_spi_b #(.CATALOG_STATUS(1),.EXTENDED_AV(1),.PAGE_CUE(1),.TYPED_PAGE(1)) audio_link(.page_valid(audio_page_valid),.page_style(audio_page_style),.page_ready(audio_page_ready),.page_cue_count(audio_page_cue_count),.catalog_complete(award_scan_complete),.clk(sd_clk),.rst(rst_sd),.spi_sclk(audio_sclk),.spi_cs(audio_cs),.spi_mosi(audio_mosi),.spi_miso(audio_miso),.packet_active(audio_packet_active),
 .active_epoch(active_audio_epoch),.active_track(active_audio_track),.track_count(audio_count),.switching(audio_switching),
 .fifo_used(pitch_fifo_used),.processed_pcm(processed_audio),.bg_enabled(audio_bg_enabled && audio_count!=0),.sample_prepare(audio_sample_prepare),.fifo_read(audio_fifo_read),.request_valid(audio_request_valid),.request_epoch(requested_audio_epoch),.request_track(requested_audio_track),.request_repair(audio_request_repair),.request_bg(audio_request_bg),.request_volume(audio_request_volume),.request_cue(audio_request_cue),.pcm_sent(av_pcm_sent),.av_snapshot(av_snapshot),.av_address(av_address),.av_data(av_data_sync));
photo_audio_processing_b #(.PAGE_CUE(1),.TYPED_PAGE(1),.SHARED_SCALE(1),.EXTERNAL_REPAIRED(1),.BOOSTED_VOLUME(1)) audio_processing(.page_valid(audio_page_valid),.page_style(audio_page_style),.page_ready(audio_page_ready),.page_cue_count(audio_page_cue_count),.background_available(audio_count!=0),.clk(sd_clk),.rst(rst_sd),.prepare(audio_sample_prepare),
 .request_valid(audio_request_valid),.request_epoch(requested_audio_epoch),.request_repair(audio_request_repair),.request_bg(audio_request_bg),
 .request_volume(audio_request_volume),.request_cue(audio_request_cue),.raw_pcm(pitched_audio),
 .processed_pcm(processed_audio),.bg_enabled(audio_bg_enabled));
wire req,ack,we,full,finish,read_req,read_ack,read_en,empty,read_finish,mem_init;
wire write_top_down,write_award;
wire [31:0] packed_data,read_data,processed_data;wire processed_empty,source_read,processed_source_read;
wire [18:0] settings_state;wire [1:0] media_gain;
wire [1:0] write_slot,ready_slot,transmit_slot;wire [2:0] count;
wire display_pin_valid,prefetch_pause;wire [2:0] display_pin_image;

wire media_ready,request,release_slot,cancel,directory_ready;
wire [2:0] target;wire [3:0] media_error,control_error;
// Cache consumes media_request on the following edge. Mask stale ready/error
// while the new request clears the previous result.
reg [2:0] media_request_settle;
always @(posedge sd_clk or posedge rst_sd)
 if(rst_sd)media_request_settle<=0;
 else if(request)media_request_settle<=4;
 else if(media_request_settle!=0)media_request_settle<=media_request_settle-1'b1;
wire media_result_current=!request && media_request_settle==0;
wire [15:0] media_source_width,media_source_height;
reg finish_toggle;
always @(posedge mem_clk or posedge rst_mem)
 if(rst_mem)finish_toggle<=0;else if(finish)finish_toggle<=~finish_toggle;
photo_sd_cache #(.FORWARD_ONLY(1),.DISPLAY_PIN(1),.EARLY_PREFETCH(1)) media(.audio_stream_reset(audio_stream_reset),.audio_packet_active(audio_packet_active),.audio_request_valid(audio_request_valid),.requested_audio_epoch(requested_audio_epoch),.requested_audio_track(requested_audio_track),
 .active_audio_epoch(active_audio_epoch),.active_audio_track(active_audio_track),.audio_count(audio_count),.audio_switching(audio_switching),
 .audio_scan_state(audio_scan_state),.audio_fifo_used(audio_fifo_used),.audio_fifo_data(audio_fifo_data),.audio_fifo_read(audio_raw_read),.display_valid(display_pin_valid),.display_image(display_pin_image),.prefetch_pause(prefetch_pause),.clk(sd_clk),.rst(rst_sd),.request(request),.target(target),.release_slot(release_slot),.cancel(cancel),
 .award_available(award_available),.award_scan_complete(award_scan_complete),.award_decode_error(award_decode_error),
 .ready_gain(media_gain),.ready(media_ready),.ready_slot(ready_slot),.image_count(count),.error(media_error),.directory_ready(directory_ready),
 .ready_source_width(media_source_width),.ready_source_height(media_source_height),
 .write_award(write_award),.write_slot(write_slot),.write_req(req),.write_top_down(write_top_down),.write_ack(ack),.full(full),.write_en(we),.write_data(packed_data),.finish_toggle(finish_toggle),
 .sd_ncs(sd_ncs),.sd_dclk(sd_dclk),.sd_mosi(sd_mosi),.sd_miso(sd_miso));
frame_store #(.FLIP(1),.ENABLE_TOP_DOWN(1)) store(.write_award(write_award),.read_award(award_sync),.write_top_down(write_top_down),.write_slot(write_slot),.read_slot(transmit_slot),.new_slot(2'd0),
 .slide_active(1'b0),.slide_right(1'b0),.slide_offset(11'd0),.transition_mode(3'd0),
 .mem_clk(mem_clk),.mem_clk_sft(mem_clk_sft),.rst(rst_mem),
 .write_clk(sd_clk),.write_req(req),.write_en(we && !full),.write_data(packed_data),.write_ack(ack),.write_finish(finish),.write_full(full),
 .read_clk(link_clk),.read_req(read_req),.read_en(source_read),.read_ack(read_ack),.read_finish(read_finish),
 .read_empty(empty),.read_data(read_data),.init_done(mem_init));
reg [18:0] settings_meta,settings_sync;
reg [1:0] gain_meta,gain_sync;
always @(posedge link_clk or posedge rst_link)
 if(rst_link)begin settings_meta<=0;settings_sync<=0;gain_meta<=1;gain_sync<=1;end
 else begin settings_meta<=settings_state;settings_sync<=settings_meta;gain_meta<=media_gain;gain_sync<=gain_meta;end
wire plane_start,effect_plane;
wire start_toggle,abort_toggle,start,abort,sent,tx_busy;wire [31:0] tx_crc;
photo_event_sync ss(.clk(link_clk),.rst(rst_link),.toggle(start_toggle),.pulse(start));
photo_event_sync sa(.clk(link_clk),.rst(rst_link),.toggle(abort_toggle),.pulse(abort));

reg transmit_award;
always @(posedge link_clk or posedge rst_link)
 if(rst_link)begin award_meta<=0;award_sync<=0;transmit_award<=0;end
 else begin award_meta<=target==6 && media_source_width[15];award_sync<=award_meta;
  if(start)transmit_award<=award_sync;end
// Preserve every tag bit. Photo enhancement must never see an award plate.
assign source_read=transmit_award ? read_en:processed_source_read;
photo_b_processing processing(.clk(link_clk),.rst(rst_link),.start((start && !award_sync) || plane_start),.abort(abort),.effect_plane(effect_plane),.read_req(read_req && !transmit_award),
 .source_ack(read_ack),.source_empty(empty),.source_data(read_data),.source_read(processed_source_read),
 .settings_state(settings_sync),.image_gain(gain_sync),.read_en(read_en),.empty(processed_empty),.data(processed_data));
photo_link_sender #(.ENABLE_CRC(1),.LEGACY_TIMING(1),.AWARD_TAIL(1),.PREFETCH_WORD(1)) tx(.award_frame(award_sync),.extended_frame(!award_sync),.plane_start(plane_start),.effect_plane(effect_plane),.clk(link_clk),.rst(rst_link),.start(start),.abort(abort),.data(transmit_award ? read_data:processed_data),.empty(transmit_award ? empty:processed_empty),
 .read_ack(read_ack),.link_ready(link_ready),.read_req(read_req),.read_en(read_en),
 .link_data(link_data),.link_valid(link_valid),.link_sof(link_sof),.link_eof(link_eof),.done(sent),.busy(tx_busy),.frame_crc(tx_crc));
reg sent_toggle;
always @(posedge link_clk or posedge rst_link)
 if(rst_link)sent_toggle<=0;else if(sent)sent_toggle<=~sent_toggle;
wire sent_sd,control_busy;wire [3:0] control_state;
wire timing_begin,timing_ready,timing_send,timing_done,timing_cancel,timing_running,timing_valid;
wire [19:0] timing_prepare_ms,timing_handshake_ms,timing_send_ms,timing_total_ms;
wire [5:0] timing_seg_sel,base_seg_sel;wire [7:0] timing_seg_data,base_seg_data;
photo_switch_timing #(.CLK_HZ(100000000),.PHASES(3)) timing_probe(.clk(sd_clk),.rst(rst_sd),
 .start(timing_begin),.mark1(timing_ready),.mark2(timing_send),.finish(timing_done),.cancel(timing_cancel),
 .running(timing_running),.valid(timing_valid),.first_ms(timing_prepare_ms),.second_ms(timing_handshake_ms),.third_ms(timing_send_ms),.total_ms(timing_total_ms));
photo_switch_timing_display #(.CLK_HZ(100000000),.PAGES(4)) timing_display(.clk(sd_clk),.rst(rst_sd),.running(timing_running),
 .first_ms(timing_prepare_ms),.second_ms(timing_handshake_ms),.third_ms(timing_send_ms),.total_ms(timing_total_ms),.seg_sel(timing_seg_sel),.seg_data(timing_seg_data));
photo_event_sync sd(.clk(sd_clk),.rst(rst_sd),.toggle(sent_toggle),.pulse(sent_sd));
photo_control_b #(.CHECK_FRAME_CRC(1),.SEND_SOURCE_SIZE(1),.SETTINGS_LINK(1),.AWARD_CONTROL(1),.FLUID(1),.AWARD_LIGHTS(1)) ctrl(.clk(sd_clk),.rst(rst_sd),.uart_rx(control_rx),.uart_tx(control_tx),
 .timing_begin(timing_begin),.timing_ready(timing_ready),.timing_send(timing_send),.timing_done(timing_done),.timing_cancel(timing_cancel),
 .display_valid(display_pin_valid),.display_image(display_pin_image),.prefetch_pause(prefetch_pause),
 .award_available(award_available && directory_ready),.award_scan_complete(award_scan_complete),
 .settings_state(settings_state),.image_count(directory_ready ? count:3'd0),.media_ready(media_ready && media_result_current),.media_slot(ready_slot),.media_error(media_result_current ? media_error:4'd0),
 .media_source_width(media_source_width),.media_source_height(media_source_height),
 .media_request(request),.media_target(target),.media_release(release_slot),.media_cancel(cancel),
 .transmit_slot(transmit_slot),.start_toggle(start_toggle),.abort_toggle(abort_toggle),.tx_done(sent_sd),.tx_crc(tx_crc),
 .busy(control_busy),.error(control_error),.debug_state(control_state));
// Preserve a failed award report while photo background prefetch resumes.
// A new explicit award request starts a fresh diagnostic attempt.
reg [11:0] award_errors;
// Retain the first photo error across automatic retries and audio-page updates.
// Power cycling clears this history; a retained code does not mean it is active.
reg [11:0] first_photo_errors;
always @(posedge sd_clk or posedge rst_sd)
 if(rst_sd)first_photo_errors<=0;
 else if(first_photo_errors==0 && target!=6 && media_result_current && (media_error!=0 || control_error!=0))
  first_photo_errors<={4'd0,media_error,control_error};
always @(posedge sd_clk or posedge rst_sd)
 if(rst_sd)award_errors<=0;
 else if(request && target==6)award_errors<=0;
 else if(target==6 && media_result_current && (media_error!=0 || control_error!=0))
  award_errors<={award_decode_error,media_error,control_error};
wire [3:0] digit=(media_error!=0 || control_error!=0) ? 4'd9:control_busy ? 4'd3:directory_ready ? 4'd5:4'd1;
photo_status #(.CLK_HZ(100000000)) status(.clk(sd_clk),.rst(rst_sd),.status({1'b0,pitch_mode}),
 .error(media_error!=0 ? media_error:control_error),.state(control_state),.image(directory_ready ? target+3'd1:3'd0),
 .count(count),.diagnostic_page((award_errors!=0 || first_photo_errors!=0 || media_error!=0 || control_error!=0 || target==6) ? 3'd4:3'd6),.diagnostic_crc((award_errors!=0 || first_photo_errors!=0 || media_error!=0 || control_error!=0 || target==6) ? {3'd0,award_available,(award_errors!=0 ? award_errors:first_photo_errors!=0 ? first_photo_errors:{award_decode_error,media_error,control_error})}:{audio_scan_state,{1'b0,audio_count},(audio_count!=0 ? {1'b0,active_audio_track}+4'd1:4'd0),(audio_fifo_used[13] ? 4'd8:{1'b0,audio_fifo_used[12:10]})}),.seg_sel(base_seg_sel),.seg_data(base_seg_data));
wire show_timing=timing_valid && media_error==0 && control_error==0 && award_errors==0 && first_photo_errors==0 && target!=6;
assign seg_sel=show_timing ? timing_seg_sel:base_seg_sel;
assign seg_data=show_timing ? timing_seg_data:base_seg_data;
assign transfer_done=directory_ready && !control_busy;
assign transfer_error=media_error!=0 || control_error!=0;
endmodule
