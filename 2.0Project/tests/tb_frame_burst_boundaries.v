`timescale 1ns/1ps
// HISTORICAL experiment, NOT in run_stability.ps1. Requires the withdrawn
// 128-word/busy-admission candidate saved in the pre-retention-fix backup.
// Address/FSM test only. Encrypted SDRAM PHY and data FIFO are not modeled.
module tb_frame_burst_boundaries;
reg clk=0; always #5 clk=~clk;
reg rst=1, req=0, busy=1, refreshing=0;
reg [1:0] index=0;
wire wa,ra,old_ack,wfinish,rfinish;
wire wen,ren,old_en;
wire writer_busy,reader_busy;
wire [20:0] waddr,raddr,old_addr;
localparam WORDS=460800;
frame_fifo_write #(.BURST_SIZE(128),.FRAME_HEIGHT(720)) wr(
 .rst(rst),.mem_clk(clk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(refreshing),
 .Sdr_busy(busy),.App_rd_busy(reader_busy),.O_wr_busy(writer_busy),.write_req(req),.write_req_ack(wa),
 .write_finish(wfinish),.App_wr_en(wen),.App_wr_addr(waddr),
 .write_addr_0(21'd0),.write_addr_1(21'd460800),.write_addr_2(21'd921600),
 .write_addr_3(21'd0),.write_addr_index(index),.write_len(21'd460800),
 .write_vga(1'b0),.rdusedw(9'd511));
frame_fifo_write #(.BURST_SIZE(256),.FRAME_HEIGHT(720)) old_wr(
 .rst(rst),.mem_clk(clk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(refreshing),
 .Sdr_busy(busy),.App_rd_busy(1'b0),.write_req(req),.write_req_ack(old_ack),
 .App_wr_en(old_en),.App_wr_addr(old_addr),
 .write_addr_0(21'd0),.write_addr_1(21'd460800),.write_addr_2(21'd921600),
 .write_addr_3(21'd0),.write_addr_index(index),.write_len(21'd460800),
 .write_vga(1'b0),.rdusedw(9'd511));
frame_fifo_read #(.BURST_SIZE(128)) rd(
 .rst(rst),.mem_clk(clk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(refreshing),
 .Sdr_busy(busy),.Sdr_rd_en(1'b0),.App_wr_busy(writer_busy),.O_rd_busy(reader_busy),
 .read_req(req),.read_req_ack(ra),.read_finish(rfinish),
 .App_rd_en(ren),.App_rd_addr(raddr),.read_addr_0(21'd0),
 .read_addr_1(21'd460800),.read_addr_2(21'd921600),.read_addr_3(21'd0),
 .read_addr_index(index),.read_len(21'd460800),.slide_active(1'b0),
 .slide_old_index(2'd0),.slide_new_index(2'd1),.slide_offset(11'd0),
 .slide_right(1'b0),.transition_mode(3'd0),.buffer0_vga(1'b0),
 .buffer1_vga(1'b0),.wrusedw(9'd0));
integer wc=0,rc=0,oc=0,old_jumps=0,base=0,expected=0;
reg previous_wen=0,previous_ren=0,previous_old_en=0;
reg write_done=0,read_done=0;
reg [20:0] previous_waddr=0,previous_raddr=0,previous_old_addr=0;
always @(posedge clk) if(!rst) begin
 if(wen && ren) $fatal(1,"read/write issue overlap");
 if(wfinish) write_done=1;
 if(rfinish) read_done=1;
 if(wen) begin
  expected=base+(719-wc/640)*640+wc%640;
  if(waddr!==expected || wc>=WORDS) $fatal(1,"write address/count %d %d %d",index,wc,waddr);
  if(previous_wen && (waddr!=previous_waddr+1 || waddr[20:8]!=previous_waddr[20:8]))
   $fatal(1,"128-word write burst crossed line/page");
  wc=wc+1;
 end
 if(ren) begin
  if(raddr!==base+rc || rc>=WORDS) $fatal(1,"read address/count");
  if(previous_ren && (raddr!=previous_raddr+1 || raddr[20:8]!=previous_raddr[20:8]))
   $fatal(1,"128-word read burst crossed page");
  rc=rc+1;
 end
 if(old_en) begin
  if(previous_old_en && old_addr!=previous_old_addr+1) old_jumps=old_jumps+1;
  oc=oc+1;
 end
 previous_wen=wen;previous_ren=ren;previous_old_en=old_en;
 previous_waddr=waddr;previous_raddr=raddr;previous_old_addr=old_addr;
end
integer k;
initial begin
 for(k=0;k<3;k=k+1) begin
  rst=1;req=0;busy=1;refreshing=0;index=k;base=k*WORDS;
  repeat(4) @(negedge clk);
  wc=0;rc=0;oc=0;old_jumps=0;previous_wen=0;previous_ren=0;previous_old_en=0;write_done=0;read_done=0;
  rst=0;req=1;
  wait(wa && ra && old_ack);@(negedge clk);req=0;
  repeat(20) @(negedge clk);
  if(wc || rc || oc) $fatal(1,"transaction started while SDRAM busy");
  refreshing=1;busy=0;
  repeat(20) @(negedge clk);
  if(wc || rc || oc) $fatal(1,"transaction started during refresh");
  refreshing=0;
  wait(write_done && read_done);
  @(negedge clk);
  if(wc!=WORDS || rc!=WORDS || oc!=WORDS || old_jumps!=360)
   $fatal(1,"frame coverage/reference %d %d %d %d",wc,rc,oc,old_jumps);
 end
 $display("PASS three native buffers: complete V-flip write/read, aligned 128-word bursts, busy/refresh admission; old 256-word path has 360 within-burst jumps/frame");
 $finish;
end
initial begin #40000000; $fatal(1,"timeout");end
endmodule
