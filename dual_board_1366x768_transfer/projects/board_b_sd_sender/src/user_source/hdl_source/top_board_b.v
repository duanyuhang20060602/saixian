`timescale 1ns/1ps
module top_dual_still_sender(
 input clk,sd_miso,output sd_ncs,sd_dclk,sd_mosi,
 output link_clk,output [15:0] link_data,output link_valid,link_sof,link_eof,
 input link_ready,image_ack,output transfer_done,transfer_error,
 output [5:0] seg_sel,output [7:0] seg_data);
wire sd_clk,mem_clk,mem_clk_sft,sys_lock,link_lock,rst_sd,rst_mem,rst_link;
sys_pll u_sys_pll(.refclk(clk),.reset(1'b0),.clk0_out(sd_clk),.clk1_out(mem_clk),.clk2_out(mem_clk_sft),.locked(sys_lock));
builtin_link_pll u_link_pll(.refclk(clk),.reset(1'b0),.clk0_out(link_clk),.locked(link_lock));
dual_still_reset_sync rs(.clk(sd_clk),.arst(!sys_lock),.rst(rst_sd));
dual_still_reset_sync rm(.clk(mem_clk),.arst(!sys_lock),.rst(rst_mem));
dual_still_reset_sync rl(.clk(link_clk),.arst(!link_lock || !sys_lock),.rst(rst_link));
wire req,req_ack,we,full,write_finish,read_req,read_ack,read_en,read_empty,mem_init;
wire [31:0] sd_data,read_data;wire read_finish;
reg finish_toggle;
always @(posedge mem_clk or posedge rst_mem)
 if(rst_mem)finish_toggle<=0;else if(write_finish)finish_toggle<=~finish_toggle;
reg half,packed_we,overflow;
reg [15:0] first_pixel;reg [31:0] packed_data;
function [15:0] to565;
 input [31:0] pixel;
 begin to565={pixel[31:27],pixel[23:18],pixel[15:11]};end
endfunction
always @(posedge sd_clk or posedge rst_sd)begin
 if(rst_sd)begin half<=0;packed_we<=0;first_pixel<=0;packed_data<=0;overflow<=0;end
 else begin
  packed_we<=0;
  if(packed_we && full)overflow<=1;
  if(req)half<=0;
  else if(we)begin
   if(!half)begin first_pixel<=to565(sd_data);half<=1;end
   else begin packed_data<={first_pixel,to565(sd_data)};packed_we<=1;half<=0;end
  end
 end
end
frame_store #(.FLIP(1)) store(.mem_clk(mem_clk),.mem_clk_sft(mem_clk_sft),.rst(rst_mem),
 .write_clk(sd_clk),.write_req(req),.write_en(packed_we && !full),.write_data(packed_data),
 .write_ack(req_ack),.write_finish(write_finish),.write_full(full),
 .read_clk(link_clk),.read_req(read_req),.read_en(read_en),.read_ack(read_ack),
 .read_finish(read_finish),.read_empty(read_empty),.read_data(read_data),.init_done(mem_init));
wire sd_init,scan_done,frame_ready,scaler_fault;
wire [2:0] media_error,image_count;
wire [3:0] sd_state;
sd_card_bmp #(.CLK_FREQ_HZ(100000000),.SCAN_START_SECTOR(0),.SCAN_MAX_SECTOR(1048575),
 .SCAN_TARGET_COUNT(1),.SINGLE_IMAGE_MODE(1'b1)) bmp(
 .clk(sd_clk),.rst(rst_sd),.prev_req_toggle(1'b0),.next_req_toggle(1'b0),.carousel_mode(1'b0),
 .display_commit_toggle(frame_ready),.state_code(sd_state),.sd_init_done_o(sd_init),.scan_done_o(scan_done),
 .image_count(image_count),.error_code(media_error),.source_width(),.source_height(),
 .frame_ready_toggle(frame_ready),.ready_buf_idx(),.ready_slide_right(),.write_buf_idx(),
 .write_vga(),.buffer0_vga(),.buffer1_vga(),.sprint_background_ready(),
 .bmp_width(16'd1366),.bmp_height(16'd768),.write_finish_toggle(finish_toggle),
 .write_req(req),.write_req_ack(req_ack),.write_en(we),.write_data(sd_data),
 .audio_fifo_wrusedw(9'd511),.audio_pcm_we(),.audio_pcm_word(),.audio_found_o(),
 .audio_track_index(3'd0),.audio_track_toggle(1'b0),.audio_track_count_o(),.scaler_fault_o(scaler_fault),
 .SD_nCS(sd_ncs),.SD_DCLK(sd_dclk),.SD_MOSI(sd_mosi),.SD_MISO(sd_miso));
reg ready_meta,ready_sync,ack_meta,ack_sync;
reg init_meta,init_sync,error_meta,error_sync,load_meta,load_sync;
always @(posedge link_clk or posedge rst_link)begin
 if(rst_link)begin ready_meta<=0;ready_sync<=0;ack_meta<=0;ack_sync<=0;
  init_meta<=0;init_sync<=0;error_meta<=0;error_sync<=0;load_meta<=0;load_sync<=0;end
 else begin
  ready_meta<=frame_ready;ready_sync<=ready_meta;ack_meta<=image_ack;ack_sync<=ack_meta;
  init_meta<=sd_init;init_sync<=init_meta;
  error_meta<=overflow || scaler_fault || media_error!=0;error_sync<=error_meta;
  load_meta<=req || sd_state>=4;load_sync<=load_meta;
 end
end
wire sent,busy;
link_sender tx(.clk(link_clk),.rst(rst_link),.start(ready_sync && !error_sync),
 .data(read_data),.empty(read_empty),.read_ack(read_ack),.link_ready(link_ready),
 .read_req(read_req),.read_en(read_en),.link_data(link_data),.link_valid(link_valid),
 .link_sof(link_sof),.link_eof(link_eof),.sent(sent),.busy(busy));
wire [3:0] digit=error_sync ? 4'd9 : ack_sync ? 4'd5 : sent ? 4'd4 :
                busy ? 4'd3 : (load_sync || ready_sync) ? 4'd2 : init_sync ? 4'd1 : 4'd0;
status_segments status(.digit(digit),.segments(seg_data));
assign seg_sel=6'b111110;
assign transfer_done=ack_sync;assign transfer_error=error_sync;
endmodule
