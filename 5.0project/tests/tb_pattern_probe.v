`timescale 1ns/1ps
module sys_pll(input refclk,reset,output clk0_out,clk1_out,clk2_out,output reg locked=0);
assign clk0_out=refclk;assign clk1_out=refclk;assign clk2_out=refclk;initial #30 locked=1;
endmodule
module builtin_link_pll(input refclk,reset,output reg clk0_out=0,output reg locked=0);
always #40 clk0_out=~clk0_out;initial #30 locked=1;
endmodule
module tb_pattern_probe;
reg clk=0;always #5 clk=~clk;
wire link_clk,valid,sof,eof,ready;wire [15:0] data;
top_photo_pattern_b #(.FRAME_PIXELS(4096),.CTRL_HZ(1152000)) b(.clk(clk),.sd_miso(1'b1),.control_rx(1'b1),.control_tx(),
 .sd_ncs(),.sd_dclk(),.sd_mosi(),.link_clk(link_clk),.link_data(data),.link_valid(valid),.link_sof(sof),.link_eof(eof),
 .link_ready(ready),.image_ack(1'b0),.transfer_done(),.transfer_error(),.seg_sel(),.seg_data());
reg rst=1,arm=0,corrupt=0;wire req,we,done,fault;wire [31:0] packed_data,crc;
reg [1:0] ack=0;reg full=0,finish=0;reg [4:0] stall=0;integer pixels=0,words=0,frames=0;
reg [31:0] golden[0:0];initial $readmemh("tests/pattern_crc_reference.hex",golden);
photo_link_receiver #(.ENABLE_CRC(1),.LEGACY_TIMING(0),.FRAME_PIXELS(4096)) a(.clk(link_clk),.rst(rst),.arm(arm),.abort(1'b0),
 .data(data ^ (corrupt && sof ? 16'h0100:16'h0000)),.valid(valid),.sof(sof),.eof(eof),.ready(ready),.armed(),.busy(),
 .write_req(req),.write_ack(ack[1]),.full(full),.write_en(we),.write_data(packed_data),.finish_toggle(finish),.done(done),.fault(fault),.frame_crc(crc));
always @(posedge link_clk)begin
 if(rst)begin ack<=0;stall<=0;full<=0;words<=0;pixels<=0;finish<=0;end
 else begin
  ack<={ack[0],req};stall<=stall+1'b1;full<=stall[2:0]==3;
  if(req)begin words<=0;pixels<=0;end
  if(valid && ready)begin
   if(data!==(((pixels*16'h1237)^16'h8291)&16'hffff))$fatal(1,"known source pixel mismatch at %d",pixels);
   pixels<=pixels+1;
  end
  if(we && !full)begin words<=words+1;if(words==2047)finish<=~finish;end
  if(done)frames<=frames+1;
 end
end
task send_frame;
 begin
  @(negedge link_clk);arm=1;b.ctrl.state_flags=(11'd1<<6);b.ctrl.start_toggle=~b.ctrl.start_toggle;
  @(negedge link_clk);arm=0;
  wait(done);@(negedge link_clk);
  if(pixels!=4096 || words!=2048 || fault)$fatal(1,"frame length/marker mismatch");
  if(b.tx_crc!==golden[0])$fatal(1,"source CRC differs from Python/zlib");
  if(corrupt ? crc===golden[0]:crc!==golden[0])$fatal(1,"receiver CRC/corruption check failed");
  repeat(8)@(negedge link_clk);
 end
endtask
initial begin
 force b.ctrl.tx_busy=1'b1;
 repeat(15)@(negedge link_clk);rst=0;
 send_frame;corrupt=1;send_frame;corrupt=0;send_frame;
 $display("PASS known-pattern B top, 4096 pixels x3, every-pixel reference, backpressure, repeated frames and corrupted-bit CRC");$finish;
end
initial begin #10000000;$display("pattern timeout tx=%d rx=%d pixels=%d words=%d frames=%d start=%b rst=%b",b.tx.state,a.state,pixels,words,frames,b.start,b.rst_link);$fatal(1,"pattern probe timeout");end
endmodule
