`timescale 1ns/1ps
module top_photo_b(
 input clk,sd_miso,control_rx,output control_tx,sd_ncs,sd_dclk,sd_mosi,
 output link_clk,output [15:0] link_data,output link_valid,link_sof,link_eof,
 input link_ready,audio_sclk,audio_cs,audio_mosi,output audio_miso,output transfer_done,transfer_error,
 output [5:0] seg_sel,output [7:0] seg_data);
wire sd_clk,mem_clk,mem_clk_sft,sys_lock,link_lock,rst_sd,rst_mem,rst_link;
sys_pll u_sys_pll(.refclk(clk),.reset(1'b0),.clk0_out(sd_clk),.clk1_out(mem_clk),.clk2_out(mem_clk_sft),.locked(sys_lock));
builtin_link_pll u_link_pll(.refclk(clk),.reset(1'b0),.clk0_out(link_clk),.locked(link_lock));
dual_still_reset_sync rs(.clk(sd_clk),.arst(!sys_lock || !link_lock),.rst(rst_sd));
dual_still_reset_sync rm(.clk(mem_clk),.arst(!sys_lock),.rst(rst_mem));
dual_still_reset_sync rl(.clk(link_clk),.arst(!link_lock || !sys_lock),.rst(rst_link));
wire [3:0] audio_scan_state;wire audio_sample_prepare,audio_bg_enabled,audio_request_bg;
wire [3:0] audio_request_volume,audio_request_cue;wire [31:0] processed_audio;reg audio_request_seen;
always @(posedge sd_clk or posedge rst_sd)
 if(rst_sd)audio_request_seen<=0;else if(audio_request_valid)audio_request_seen<=1;
wire audio_packet_active,audio_request_valid,audio_switching,audio_fifo_read;wire [7:0] requested_audio_epoch,active_audio_epoch;
wire [2:0] requested_audio_track,active_audio_track,audio_count;wire [13:0] audio_fifo_used;wire [31:0] audio_fifo_data;
photo_audio_spi_b audio_link(.clk(sd_clk),.rst(rst_sd),.spi_sclk(audio_sclk),.spi_cs(audio_cs),.spi_mosi(audio_mosi),.spi_miso(audio_miso),.packet_active(audio_packet_active),
 .active_epoch(active_audio_epoch),.active_track(active_audio_track),.track_count(audio_count),.switching(audio_switching),
 .fifo_used(audio_fifo_used),.processed_pcm(processed_audio),.bg_enabled(audio_bg_enabled),.sample_prepare(audio_sample_prepare),.fifo_read(audio_fifo_read),.request_valid(audio_request_valid),.request_epoch(requested_audio_epoch),.request_track(requested_audio_track),.request_bg(audio_request_bg),.request_volume(audio_request_volume),.request_cue(audio_request_cue));
photo_audio_processing_b audio_processing(.clk(sd_clk),.rst(rst_sd),.prepare(audio_sample_prepare),
 .request_valid(audio_request_valid),.request_epoch(requested_audio_epoch),.request_bg(audio_request_bg),
 .request_volume(audio_request_volume),.request_cue(audio_request_cue),.raw_pcm(audio_fifo_data),
 .processed_pcm(processed_audio),.bg_enabled(audio_bg_enabled));
wire req,ack,we,full,finish,read_req,read_ack,read_en,empty,read_finish,mem_init;
wire write_top_down;
wire [31:0] packed_data,read_data,processed_data;wire processed_empty,source_read,processed_source_read;
wire high_color;wire [18:0] settings_state;wire [1:0] media_gain;
wire [1:0] write_slot,ready_slot,transmit_slot;wire [2:0] count;
wire display_pin_valid,prefetch_pause;wire [2:0] display_pin_image;
wire award_available,award_scan_complete;wire [3:0] award_decode_error;
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
photo_sd_cache #(.FORWARD_ONLY(1),.DISPLAY_PIN(1)) media(.requested_high_color(settings_state[18]),.high_color(high_color),.audio_packet_active(audio_packet_active),.audio_request_valid(audio_request_valid),.requested_audio_epoch(requested_audio_epoch),.requested_audio_track(requested_audio_track),
 .active_audio_epoch(active_audio_epoch),.active_audio_track(active_audio_track),.audio_count(audio_count),.audio_switching(audio_switching),
 .audio_scan_state(audio_scan_state),.audio_fifo_used(audio_fifo_used),.audio_fifo_data(audio_fifo_data),.audio_fifo_read(audio_fifo_read),.display_valid(display_pin_valid),.display_image(display_pin_image),.prefetch_pause(prefetch_pause),.clk(sd_clk),.rst(rst_sd),.request(request),.target(target),.release_slot(release_slot),.cancel(cancel),
 .award_available(award_available),.award_scan_complete(award_scan_complete),.award_decode_error(award_decode_error),
 .ready_gain(media_gain),.ready(media_ready),.ready_slot(ready_slot),.image_count(count),.error(media_error),.directory_ready(directory_ready),
 .ready_source_width(media_source_width),.ready_source_height(media_source_height),
 .write_slot(write_slot),.write_req(req),.write_top_down(write_top_down),.write_ack(ack),.full(full),.write_en(we),.write_data(packed_data),.finish_toggle(finish_toggle),
 .sd_ncs(sd_ncs),.sd_dclk(sd_dclk),.sd_mosi(sd_mosi),.sd_miso(sd_miso));
frame_store #(.FLIP(1),.ENABLE_TOP_DOWN(1)) store(.write_top_down(write_top_down),.high_color(high_color),.write_slot(write_slot),.read_slot(transmit_slot),.new_slot(2'd0),
 .slide_active(1'b0),.slide_right(1'b0),.slide_offset(11'd0),.transition_mode(3'd0),
 .mem_clk(mem_clk),.mem_clk_sft(mem_clk_sft),.rst(rst_mem),
 .write_clk(sd_clk),.write_req(req),.write_en(we && !full),.write_data(packed_data),.write_ack(ack),.write_finish(finish),.write_full(full),
 .read_clk(link_clk),.read_req(read_req),.read_en(source_read),.read_ack(read_ack),.read_finish(read_finish),
 .read_empty(empty),.read_data(read_data),.init_done(mem_init));
reg [18:0] settings_meta,settings_sync;
(* async_reg="true" *)reg color_link_meta,color_link_sync;reg [1:0] gain_meta,gain_sync;
always @(posedge link_clk or posedge rst_link)
 if(rst_link)begin color_link_meta<=0;color_link_sync<=0;settings_meta<=0;settings_sync<=0;gain_meta<=1;gain_sync<=1;end
 else begin color_link_meta<=high_color;color_link_sync<=color_link_meta;settings_meta<=settings_state;settings_sync<=settings_meta;gain_meta<=media_gain;gain_sync<=gain_meta;end
wire start_toggle,abort_toggle,start,abort,sent,tx_busy;wire [31:0] tx_crc;
photo_event_sync ss(.clk(link_clk),.rst(rst_link),.toggle(start_toggle),.pulse(start));
photo_event_sync sa(.clk(link_clk),.rst(rst_link),.toggle(abort_toggle),.pulse(abort));
(* async_reg="true" *)reg award_meta,award_sync;
reg transmit_award;
always @(posedge link_clk or posedge rst_link)
 if(rst_link)begin award_meta<=0;award_sync<=0;transmit_award<=0;end
 else begin award_meta<=target==6 && media_source_width[15];award_sync<=award_meta;
  if(start)transmit_award<=award_sync;end
// Preserve every tag bit. Photo enhancement must never see an award plate.
assign source_read=transmit_award ? read_en:processed_source_read;
photo_b_processing processing(.clk(link_clk),.rst(rst_link),.start(start && !award_sync),.abort(abort),.read_req(read_req && !transmit_award),
 .source_ack(read_ack),.source_empty(empty),.source_data(read_data),.source_read(processed_source_read),
 .settings_state(settings_sync),.image_gain(gain_sync),.read_en(read_en),.empty(processed_empty),.data(processed_data));
photo_link_sender #(.ENABLE_CRC(0),.LEGACY_TIMING(1)) tx(.high_color(color_link_sync),.clk(link_clk),.rst(rst_link),.start(start),.abort(abort),.data(transmit_award ? read_data:processed_data),.empty(transmit_award ? empty:processed_empty),
 .read_ack(read_ack),.link_ready(link_ready),.read_req(read_req),.read_en(read_en),
 .link_data(link_data),.link_valid(link_valid),.link_sof(link_sof),.link_eof(link_eof),.done(sent),.busy(tx_busy),.frame_crc(tx_crc));
reg sent_toggle;
always @(posedge link_clk or posedge rst_link)
 if(rst_link)sent_toggle<=0;else if(sent)sent_toggle<=~sent_toggle;
wire sent_sd,control_busy;wire [3:0] control_state;
photo_event_sync sd(.clk(sd_clk),.rst(rst_sd),.toggle(sent_toggle),.pulse(sent_sd));
photo_control_b #(.CHECK_FRAME_CRC(0),.SEND_SOURCE_SIZE(1),.SETTINGS_LINK(1),.AWARD_CONTROL(1)) ctrl(.high_color(high_color),.clk(sd_clk),.rst(rst_sd),.uart_rx(control_rx),.uart_tx(control_tx),
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
always @(posedge sd_clk or posedge rst_sd)
 if(rst_sd)award_errors<=0;
 else if(request && target==6)award_errors<=0;
 else if(target==6 && media_result_current && (media_error!=0 || control_error!=0))
  award_errors<={award_decode_error,media_error,control_error};
wire [3:0] digit=(media_error!=0 || control_error!=0) ? 4'd9:control_busy ? 4'd3:directory_ready ? 4'd5:4'd1;
photo_status #(.CLK_HZ(100000000)) status(.clk(sd_clk),.rst(rst_sd),.status({3'd0,audio_request_seen}),
 .error(media_error!=0 ? media_error:control_error),.state(control_state),.image(directory_ready ? target+3'd1:3'd0),
 .count(count),.diagnostic_page((award_errors!=0 || media_error!=0 || control_error!=0 || target==6) ? 3'd4:3'd6),.diagnostic_crc((award_errors!=0 || media_error!=0 || control_error!=0 || target==6) ? {3'd0,award_available,(award_errors!=0 ? award_errors:{award_decode_error,media_error,control_error})}:{audio_scan_state,{1'b0,audio_count},(audio_count!=0 ? {1'b0,active_audio_track}+4'd1:4'd0),(audio_fifo_used[13] ? 4'd8:{1'b0,audio_fifo_used[12:10]})}),.seg_sel(seg_sel),.seg_data(seg_data));
assign transfer_done=directory_ready && !control_busy;
assign transfer_error=media_error!=0 || control_error!=0;
endmodule
