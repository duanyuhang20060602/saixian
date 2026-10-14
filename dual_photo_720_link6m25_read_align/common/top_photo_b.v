`timescale 1ns/1ps
module top_photo_b(
 input clk,sd_miso,control_rx,output control_tx,sd_ncs,sd_dclk,sd_mosi,
 output link_clk,output [15:0] link_data,output link_valid,link_sof,link_eof,
 input link_ready,image_ack,output transfer_done,transfer_error,
 output [5:0] seg_sel,output [7:0] seg_data);
wire sd_clk,mem_clk,mem_clk_sft,sys_lock,link_lock,rst_sd,rst_mem,rst_link;
sys_pll u_sys_pll(.refclk(clk),.reset(1'b0),.clk0_out(sd_clk),.clk1_out(mem_clk),.clk2_out(mem_clk_sft),.locked(sys_lock));
builtin_link_pll u_link_pll(.refclk(clk),.reset(1'b0),.clk0_out(link_clk),.locked(link_lock));
dual_still_reset_sync rs(.clk(sd_clk),.arst(!sys_lock || !link_lock),.rst(rst_sd));
dual_still_reset_sync rm(.clk(mem_clk),.arst(!sys_lock),.rst(rst_mem));
dual_still_reset_sync rl(.clk(link_clk),.arst(!link_lock || !sys_lock),.rst(rst_link));
wire req,ack,we,full,finish,read_req,read_ack,read_en,empty,read_finish,mem_init;
wire [31:0] packed_data,read_data,processed_data;wire processed_empty,source_read;
wire [17:0] settings_state;wire [1:0] media_gain;
wire [1:0] write_slot,ready_slot,transmit_slot;wire [2:0] count;
wire display_pin_valid,prefetch_pause;wire [2:0] display_pin_image;
wire media_ready,request,release_slot,cancel,directory_ready;
wire [2:0] target;wire [3:0] media_error,control_error;
wire [15:0] media_source_width,media_source_height;
reg finish_toggle;
always @(posedge mem_clk or posedge rst_mem)
 if(rst_mem)finish_toggle<=0;else if(finish)finish_toggle<=~finish_toggle;
photo_sd_cache #(.FORWARD_ONLY(1),.DISPLAY_PIN(1)) media(.display_valid(display_pin_valid),.display_image(display_pin_image),.prefetch_pause(prefetch_pause),.clk(sd_clk),.rst(rst_sd),.request(request),.target(target),.release_slot(release_slot),.cancel(cancel),
 .ready_gain(media_gain),.ready(media_ready),.ready_slot(ready_slot),.image_count(count),.error(media_error),.directory_ready(directory_ready),
 .ready_source_width(media_source_width),.ready_source_height(media_source_height),
 .write_slot(write_slot),.write_req(req),.write_ack(ack),.full(full),.write_en(we),.write_data(packed_data),.finish_toggle(finish_toggle),
 .sd_ncs(sd_ncs),.sd_dclk(sd_dclk),.sd_mosi(sd_mosi),.sd_miso(sd_miso));
frame_store #(.FLIP(1)) store(.write_slot(write_slot),.read_slot(transmit_slot),.new_slot(2'd0),
 .slide_active(1'b0),.slide_right(1'b0),.slide_offset(11'd0),.transition_mode(3'd0),
 .mem_clk(mem_clk),.mem_clk_sft(mem_clk_sft),.rst(rst_mem),
 .write_clk(sd_clk),.write_req(req),.write_en(we && !full),.write_data(packed_data),.write_ack(ack),.write_finish(finish),.write_full(full),
 .read_clk(link_clk),.read_req(read_req),.read_en(source_read),.read_ack(read_ack),.read_finish(read_finish),
 .read_empty(empty),.read_data(read_data),.init_done(mem_init));
reg [17:0] settings_meta,settings_sync;reg [1:0] gain_meta,gain_sync;
always @(posedge link_clk or posedge rst_link)
 if(rst_link)begin settings_meta<=0;settings_sync<=0;gain_meta<=1;gain_sync<=1;end
 else begin settings_meta<=settings_state;settings_sync<=settings_meta;gain_meta<=media_gain;gain_sync<=gain_meta;end
wire start_toggle,abort_toggle,start,abort,sent,tx_busy;wire [31:0] tx_crc;
photo_event_sync ss(.clk(link_clk),.rst(rst_link),.toggle(start_toggle),.pulse(start));
photo_event_sync sa(.clk(link_clk),.rst(rst_link),.toggle(abort_toggle),.pulse(abort));
photo_b_processing processing(.clk(link_clk),.rst(rst_link),.start(start),.abort(abort),.read_req(read_req),
 .source_ack(read_ack),.source_empty(empty),.source_data(read_data),.source_read(source_read),
 .settings_state(settings_sync),.image_gain(gain_sync),.read_en(read_en),.empty(processed_empty),.data(processed_data));
photo_link_sender #(.ENABLE_CRC(0),.LEGACY_TIMING(1)) tx(.clk(link_clk),.rst(rst_link),.start(start),.abort(abort),.data(processed_data),.empty(processed_empty),
 .read_ack(read_ack),.link_ready(link_ready),.read_req(read_req),.read_en(read_en),
 .link_data(link_data),.link_valid(link_valid),.link_sof(link_sof),.link_eof(link_eof),.done(sent),.busy(tx_busy),.frame_crc(tx_crc));
reg sent_toggle;
always @(posedge link_clk or posedge rst_link)
 if(rst_link)sent_toggle<=0;else if(sent)sent_toggle<=~sent_toggle;
wire sent_sd,control_busy;wire [3:0] control_state;
photo_event_sync sd(.clk(sd_clk),.rst(rst_sd),.toggle(sent_toggle),.pulse(sent_sd));
photo_control_b #(.CHECK_FRAME_CRC(0),.SEND_SOURCE_SIZE(1),.SETTINGS_LINK(1)) ctrl(.clk(sd_clk),.rst(rst_sd),.uart_rx(control_rx),.uart_tx(control_tx),
 .display_valid(display_pin_valid),.display_image(display_pin_image),.prefetch_pause(prefetch_pause),
 .settings_state(settings_state),.image_count(directory_ready ? count:3'd0),.media_ready(media_ready),.media_slot(ready_slot),.media_error(media_error),
 .media_source_width(media_source_width),.media_source_height(media_source_height),
 .media_request(request),.media_target(target),.media_release(release_slot),.media_cancel(cancel),
 .transmit_slot(transmit_slot),.start_toggle(start_toggle),.abort_toggle(abort_toggle),.tx_done(sent_sd),.tx_crc(tx_crc),
 .busy(control_busy),.error(control_error),.debug_state(control_state));
wire [3:0] digit=(media_error!=0 || control_error!=0) ? 4'd9:control_busy ? 4'd3:directory_ready ? 4'd5:4'd1;
photo_status #(.CLK_HZ(100000000)) status(.clk(sd_clk),.rst(rst_sd),.status(digit),
 .error(media_error!=0 ? media_error:control_error),.state(control_state),.image(directory_ready ? target+3'd1:3'd0),
 .count(count),.diagnostic_page(3'd0),.diagnostic_crc(16'd0),.seg_sel(seg_sel),.seg_data(seg_data));
assign transfer_done=directory_ready && !control_busy;
assign transfer_error=media_error!=0 || control_error!=0;
endmodule
