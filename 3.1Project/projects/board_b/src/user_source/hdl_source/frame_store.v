`timescale 1ns/1ps
// One 1280x720 RGB565 frame, two pixels per SDRAM word.
module frame_store #(parameter FLIP=0,parameter RGB888_READ_ALIGN=1,parameter ENABLE_TOP_DOWN=0)(
 input write_top_down,high_color,input [1:0] write_slot,read_slot,new_slot, input slide_active,slide_right, input [10:0] slide_offset,input [2:0] transition_mode,
 input mem_clk,mem_clk_sft,rst,write_clk,write_req,write_en,
 input [31:0] write_data,output write_ack,write_finish,write_full,
 input read_clk,read_req,read_en,output read_ack,read_finish,read_empty,
 output [31:0] read_data,output init_done
);
wire init_ref,busy,rd,wr,rd_valid;
(* async_reg="true" *)reg top_down_meta,top_down_sync;
always @(posedge mem_clk or posedge rst)
 if(rst)begin top_down_meta<=0;top_down_sync<=0;end
 else begin top_down_meta<=ENABLE_TOP_DOWN ? write_top_down:1'b0;top_down_sync<=top_down_meta;end
(* async_reg="true" *)reg color_meta,color_sync;
always @(posedge mem_clk or posedge rst)
 if(rst)begin color_meta<=0;color_sync<=0;end else begin color_meta<=high_color;color_sync<=color_meta;end
wire [20:0] frame_words=color_sync ? 21'd691200:21'd460800;
wire [20:0] slot1=color_sync ? 21'd691200:21'd460800;
wire [20:0] slot2=color_sync ? 21'd0:21'd921600;
wire [20:0] slot3=color_sync ? 21'd0:21'd1382400;

wire [20:0] rd_addr,wr_addr;
wire [31:0] rd_data,wr_data;wire [3:0] dm;
// Calibration candidate: if raw SDRAM data leads rd_valid by one clock,
// keep the preceding word before the FIFO samples it. Capture EVERY clock,
// including the first word before rd_valid; gating capture by valid loses it.
reg [31:0] captured_rd_data;
always @(posedge mem_clk or posedge rst)
 if(rst)captured_rd_data<=0;else captured_rd_data<=rd_data;
wire [31:0] fifo_rd_data=(RGB888_READ_ALIGN && color_sync) ? captured_rd_data:rd_data;
frame_read_write #(.WRITE_V_FLIP(FLIP),.FRAME_WIDTH(640),.FRAME_HEIGHT(720),.BURST_SIZE(256)) rw(
 .write_top_down(top_down_sync),.high_color(color_sync),.mem_clk(mem_clk),.rst(rst),.Sdr_init_done(init_done),.Sdr_init_ref_vld(init_ref),.Sdr_busy(busy),
 .App_rd_en(rd),.App_rd_addr(rd_addr),.Sdr_rd_en(rd_valid),.Sdr_rd_dout(fifo_rd_data),
 .read_clk(read_clk),.read_req(read_req),.read_req_ack(read_ack),.read_finish(read_finish),
 .read_addr_0(21'd0),.read_addr_1(slot1),.read_addr_2(slot2),.read_addr_3(21'd0),.read_addr_index(read_slot),
 .read_len(frame_words),.read_en(read_en),.read_data(read_data),.read_fifo_empty(read_empty),
 .slide_active(slide_active),.slide_old_index(read_slot),.slide_new_index(new_slot),.slide_offset(slide_offset),
 .slide_right(slide_right),.transition_mode(transition_mode),.buffer0_vga(1'b0),.buffer1_vga(1'b0),
 .App_wr_en(wr),.App_wr_addr(wr_addr),.App_wr_din(wr_data),.App_wr_dm(dm),
 .write_clk(write_clk),.write_req(write_req),.write_req_ack(write_ack),.write_finish(write_finish),
 .write_addr_0(21'd0),.write_addr_1(slot1),.write_addr_2(slot2),.write_addr_3(21'd0),.write_addr_index(write_slot),
 .write_len(frame_words),.write_vga(1'b0),.write_en(write_en),.write_data(write_data),.write_fifo_full(write_full));
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
