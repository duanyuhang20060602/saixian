`timescale 1ns/1ps
// Full-frame known pixel source. Same photo control and paced pixel sender.
// A continues to use its CRC_DIAG bit. This diagnostic has no SD/SDRAM source.
module top_photo_pattern_b #(parameter FRAME_PIXELS=921600,CTRL_HZ=100000000)(
 input clk,sd_miso,control_rx,output control_tx,sd_ncs,sd_dclk,sd_mosi,
 output link_clk,output [15:0] link_data,output link_valid,link_sof,link_eof,
 input link_ready,image_ack,output transfer_done,transfer_error,
 output [5:0] seg_sel,output [7:0] seg_data);
wire sd_clk,mem_clk,mem_clk_sft,sys_lock,link_lock,rst_sd,rst_link;
sys_pll u_sys_pll(.refclk(clk),.reset(1'b0),.clk0_out(sd_clk),.clk1_out(mem_clk),.clk2_out(mem_clk_sft),.locked(sys_lock));
builtin_link_pll u_link_pll(.refclk(clk),.reset(1'b0),.clk0_out(link_clk),.locked(link_lock));
dual_still_reset_sync rs(.clk(sd_clk),.arst(!sys_lock || !link_lock),.rst(rst_sd));
dual_still_reset_sync rl(.clk(link_clk),.arst(!link_lock || !sys_lock),.rst(rst_link));
wire request,release_slot,cancel,control_busy;reg media_ready;
always @(posedge sd_clk or posedge rst_sd)
 if(rst_sd)media_ready<=0;
 else if(cancel || release_slot)media_ready<=0;
 else if(request)media_ready<=1;
wire start_toggle,abort_toggle,start,abort,sent,tx_busy,sent_sd;
wire [31:0] tx_crc;wire [3:0] control_error,control_state;
photo_event_sync ss(.clk(link_clk),.rst(rst_link),.toggle(start_toggle),.pulse(start));
photo_event_sync sa(.clk(link_clk),.rst(rst_link),.toggle(abort_toggle),.pulse(abort));
wire read_req,read_en;reg [1:0] read_ack_pipe;reg [19:0] word_index;reg [31:0] read_data;
function [15:0] pattern;
 input [20:0] p;
 begin pattern=(p*16'h1237)^16'h8291;end
endfunction
always @(posedge link_clk or posedge rst_link)
 if(rst_link)begin read_ack_pipe<=0;word_index<=0;read_data<=0;end
 else begin
  read_ack_pipe<={read_ack_pipe[0],read_req};
  if(read_req)word_index<=0;
  if(read_en)begin
   read_data<={pattern({word_index,1'b0}),pattern({word_index,1'b1})};word_index<=word_index+1'b1;
  end
 end
photo_link_sender #(.FRAME_PIXELS(FRAME_PIXELS),.ENABLE_CRC(1),.LEGACY_TIMING(0)) tx(.clk(link_clk),.rst(rst_link),.start(start),.abort(abort),
 .data(read_data),.empty(1'b0),.read_ack(read_ack_pipe[1]),.link_ready(link_ready),.read_req(read_req),.read_en(read_en),
 .link_data(link_data),.link_valid(link_valid),.link_sof(link_sof),.link_eof(link_eof),.done(sent),.busy(tx_busy),.frame_crc(tx_crc));
reg sent_toggle;
always @(posedge link_clk or posedge rst_link)
 if(rst_link)sent_toggle<=0;else if(sent)sent_toggle<=~sent_toggle;
photo_event_sync sd(.clk(sd_clk),.rst(rst_sd),.toggle(sent_toggle),.pulse(sent_sd));
photo_control_b #(.CHECK_FRAME_CRC(1),.CLK_HZ(CTRL_HZ),.FRAME_BYTES(FRAME_PIXELS*2)) ctrl(.clk(sd_clk),.rst(rst_sd),.uart_rx(control_rx),.uart_tx(control_tx),
 .image_count(3'd1),.media_ready(media_ready),.media_slot(2'd0),.media_error(4'd0),
 .media_request(request),.media_target(),.media_release(release_slot),.media_cancel(cancel),
 .transmit_slot(),.start_toggle(start_toggle),.abort_toggle(abort_toggle),.tx_done(sent_sd),.tx_crc(tx_crc),
 .busy(control_busy),.error(control_error),.debug_state(control_state));
photo_status #(.CLK_HZ(CTRL_HZ)) status(.clk(sd_clk),.rst(rst_sd),.status(control_error!=0 ? 4'd9:control_busy ? 4'd3:4'd5),
 .error(control_error),.state(control_state),.image(3'd1),.count(3'd1),
 .diagnostic_page(3'd0),.diagnostic_crc(16'd0),.seg_sel(seg_sel),.seg_data(seg_data));
assign transfer_done=!control_busy;assign transfer_error=control_error!=0;
assign sd_ncs=1'b1;assign sd_dclk=1'b0;assign sd_mosi=1'b1;
endmodule
