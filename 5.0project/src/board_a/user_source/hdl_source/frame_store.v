`timescale 1ns/1ps
// One 1280x720 RGB565 frame, two pixels per SDRAM word.
module frame_store #(parameter FLIP=0)(
 input display_active,thumbnail_request,thumbnail_cancel,thumbnail_blank,input [1:0] thumbnail_slot,
 input [12:0] thumbnail_address,output thumbnail_done,output [15:0] thumbnail_data,
 input write_award,read_award,light_enable,light_request,input [20:0] light_address,
 output light_ack,light_valid,output [31:0] light_data,output [20:0] light_base,
 input [76:0] water_cfg,input [8:0] fluid_progress,input write_fluid,input [1:0] write_slot,read_slot,new_slot, input slide_active,slide_right, input [10:0] slide_offset,input [4:0] transition_mode,
 input mem_clk,mem_clk_sft,rst,write_clk,write_req,write_en,
 input [31:0] write_data,output write_ack,write_finish,write_full,
 input read_clk,read_req,read_en,output read_ack,read_finish,read_empty,
 output [31:0] read_data,output init_done
);
wire [20:0] rd_addr,wr_addr;
wire [31:0] rd_data,wr_data,aligned_rd_data;wire [3:0] dm;
wire init_ref,busy,rd,wr,rd_valid;
wire frame_rd,frame_access,light_claim,light_rd;wire [20:0] frame_address,light_rd_address;
wire thumb_request,thumb_claim,thumb_read,external_allowed;wire [20:0] thumb_address;
(* async_reg="true" *)reg display_meta,display_sync;
always @(posedge mem_clk or posedge rst)
 if(rst)begin display_meta<=0;display_sync<=0;end
 else begin display_meta<=display_active;display_sync<=display_meta;end
(* async_reg="true" *)reg award_w0,award_w1,award_r0,award_r1,light_en0,light_en1;
(* async_reg="true" *)reg [1:0] slot_m0,slot_m1;
always @(posedge mem_clk or posedge rst)
 if(rst)begin award_w0<=0;award_w1<=0;award_r0<=0;award_r1<=0;light_en0<=0;light_en1<=0;slot_m0<=0;slot_m1<=0;end
 else begin award_w0<=write_award;award_w1<=award_w0;award_r0<=read_award;award_r1<=award_r0;
  light_en0<=light_enable;light_en1<=light_en0;slot_m0<=read_slot;slot_m1<=slot_m0;end
assign light_base=(slot_m1==0 ? 21'd0:slot_m1==1 ? 21'd691200:21'd1382400)+21'd460800;
assign rd=thumb_claim ? thumb_read:light_claim ? light_rd:frame_rd;
assign rd_addr=thumb_claim ? thumb_address:light_claim ? light_rd_address:frame_address;
photo_award_memory light_memory(.clk(mem_clk),.rst(rst),.enable(light_en1),.init_done(init_done),
 .refresh(init_ref),.busy(busy),.frame_busy(frame_access || thumb_claim),.request(light_request),.address(light_address),
 .acknowledge(light_ack),.data(light_data),.valid(light_valid),.claim(light_claim),
 .read_command(light_rd),.read_address(light_rd_address),.response_valid(rd_valid && light_claim),.response(aligned_rd_data));
(* async_reg="true" *)reg fluid_meta,fluid_sync;
always @(posedge mem_clk or posedge rst)
 if(rst)begin fluid_meta<=0;fluid_sync<=0;end else begin fluid_meta<=write_fluid;fluid_sync<=fluid_meta;end
wire [20:0] frame_words=21'd460800;
wire [20:0] slot1=21'd691200;
wire [20:0] slot2=21'd1382400;
wire [20:0] slot3=21'd0;
photo_thumbnail_memory thumbnails(.clk(mem_clk),.rst(rst),
 .init_done(init_done),.refresh(init_ref),.busy(busy),.frame_busy(frame_access),.allow_access(external_allowed),
 .other_request(light_request || light_claim),.request(thumb_request),.claim(thumb_claim),.read_command(thumb_read),.address(thumb_address),
 .response_valid(rd_valid && thumb_claim),.response(aligned_rd_data),
 .video_clk(read_clk),.video_request(thumbnail_request),.video_cancel(thumbnail_cancel),.video_blank(thumbnail_blank),.video_slot(thumbnail_slot),
 .video_done(thumbnail_done),.video_address(thumbnail_address),.video_data(thumbnail_data));
photo_sdram_read_align align_read(.clk(mem_clk),.rst(rst),.raw_data(rd_data),.aligned_data(aligned_rd_data));
frame_read_write #(.WRITE_V_FLIP(FLIP),.FRAME_WIDTH(640),.FRAME_HEIGHT(720),.BURST_SIZE(256)) rw(
 .external_request(light_request || thumb_request),.external_busy(light_claim || thumb_claim),.access_busy(frame_access),
 .display_active(display_sync),.external_allowed(external_allowed),.water_cfg(water_cfg),.fluid_progress(fluid_progress),.mem_clk(mem_clk),.rst(rst),.Sdr_init_done(init_done),.Sdr_init_ref_vld(init_ref),.Sdr_busy(busy),
 .App_rd_en(frame_rd),.App_rd_addr(frame_address),.Sdr_rd_en(rd_valid && !light_claim && !thumb_claim),.Sdr_rd_dout(aligned_rd_data),
 .read_clk(read_clk),.read_req(read_req),.read_req_ack(read_ack),.read_finish(read_finish),
 .read_addr_0(21'd0),.read_addr_1(slot1),.read_addr_2(slot2),.read_addr_3(slot3),.read_addr_index(read_slot),
 .read_len(award_r1 ? 21'd460800:frame_words),.read_en(read_en),.read_data(read_data),.read_fifo_empty(read_empty),
 .slide_active(slide_active),.slide_old_index(read_slot),.slide_new_index(new_slot),.slide_offset(slide_offset),
 .slide_right(slide_right),.transition_mode(transition_mode),.buffer0_vga(1'b0),.buffer1_vga(1'b0),
 .App_wr_en(wr),.App_wr_addr(wr_addr),.App_wr_din(wr_data),.App_wr_dm(dm),
 .write_clk(write_clk),.write_req(write_req),.write_req_ack(write_ack),.write_finish(write_finish),
 .write_addr_0(21'd0),.write_addr_1(slot1),.write_addr_2(slot2),.write_addr_3(slot3),.write_addr_index(write_slot),
 .write_len(award_w1 || fluid_sync ? 21'd691200:21'd460800),.write_vga(1'b0),.write_en(write_en),.write_data(write_data),.write_fifo_full(write_full));
sdram ram(.Clk(mem_clk),.Clk_sft(mem_clk_sft),.Rst(rst),.Sdr_init_done(init_done),
 .Sdr_init_ref_vld(init_ref),.Sdr_busy(busy),.App_wr_en(wr),.App_wr_addr(wr_addr),
 .App_wr_dm(dm),.App_wr_din(wr_data),.App_rd_en(rd),.App_rd_addr(rd_addr),.Sdr_rd_en(rd_valid),.Sdr_rd_dout(rd_data));
endmodule

module status_segments(input [3:0] digit,output reg [7:0] segments);
always @* case(digit)
 0:segments=8'hc0;1:segments=8'hf9;2:segments=8'ha4;3:segments=8'hb0;4:segments=8'h99;
 5:segments=8'h92;6:segments=8'h82;7:segments=8'hf8;8:segments=8'h80;default:segments=8'h90;
endcase
endmodule

// Experimental alignment: only data is delayed, valid keeps original timing.
// Sample every cycle including before valid, to preserve the first/last word.
module photo_sdram_read_align(input clk,rst,input [31:0] raw_data,output reg [31:0] aligned_data);
always @(posedge clk or posedge rst)begin
 if(rst)aligned_data<=0;else aligned_data<=raw_data;
end
endmodule
