`timescale 1ns/1ps
// One 1280x720 RGB565 frame, two pixels per SDRAM word.
module frame_store #(parameter FLIP=0)(
 input [1:0] write_slot,read_slot,new_slot, input slide_active,slide_right, input [10:0] slide_offset,input [2:0] transition_mode,
 input mem_clk,mem_clk_sft,rst,write_clk,write_req,write_en,
 input [31:0] write_data,output write_ack,write_finish,write_full,
 input read_clk,read_req,read_en,output read_ack,read_finish,read_empty,
 output [31:0] read_data,output init_done
);
wire init_ref,busy,rd,wr,rd_valid;
wire [20:0] rd_addr,wr_addr;
wire [31:0] rd_data,wr_data,aligned_rd_data;wire [3:0] dm;
photo_sdram_read_align align_read(.clk(mem_clk),.rst(rst),.raw_data(rd_data),.aligned_data(aligned_rd_data));
frame_read_write #(.WRITE_V_FLIP(FLIP),.FRAME_WIDTH(640),.FRAME_HEIGHT(720),.BURST_SIZE(256)) rw(
 .mem_clk(mem_clk),.rst(rst),.Sdr_init_done(init_done),.Sdr_init_ref_vld(init_ref),.Sdr_busy(busy),
 .App_rd_en(rd),.App_rd_addr(rd_addr),.Sdr_rd_en(rd_valid),.Sdr_rd_dout(aligned_rd_data),
 .read_clk(read_clk),.read_req(read_req),.read_req_ack(read_ack),.read_finish(read_finish),
 .read_addr_0(21'd0),.read_addr_1(21'd460800),.read_addr_2(21'd921600),.read_addr_3(21'd0),.read_addr_index(read_slot),
 .read_len(21'd460800),.read_en(read_en),.read_data(read_data),.read_fifo_empty(read_empty),
 .slide_active(slide_active),.slide_old_index(read_slot),.slide_new_index(new_slot),.slide_offset(slide_offset),
 .slide_right(slide_right),.transition_mode(transition_mode),.buffer0_vga(1'b0),.buffer1_vga(1'b0),
 .App_wr_en(wr),.App_wr_addr(wr_addr),.App_wr_din(wr_data),.App_wr_dm(dm),
 .write_clk(write_clk),.write_req(write_req),.write_req_ack(write_ack),.write_finish(write_finish),
 .write_addr_0(21'd0),.write_addr_1(21'd460800),.write_addr_2(21'd921600),.write_addr_3(21'd0),.write_addr_index(write_slot),
 .write_len(21'd460800),.write_vga(1'b0),.write_en(write_en),.write_data(write_data),.write_fifo_full(write_full));
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
