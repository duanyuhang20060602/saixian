`timescale 1ns/1ps
module image_metadata_case #(parameter [31:0] MAX_SECTOR=1048575,
                            parameter integer EXPECTED_BITS=20)(
 input clk,rst,push,commit,input [2:0] which,
 input [15:0] w,h,input [31:0] epoch
);
wire [31:0] discovered=MAX_SECTOR-epoch-which;
sd_card_bmp #(.CLK_FREQ_HZ(1000),.SCAN_MAX_SECTOR(MAX_SECTOR)) dut(
 .clk(clk),.rst(rst),.prev_req_toggle(1'b0),.next_req_toggle(1'b0),
 .carousel_mode(1'b0),.display_commit_toggle(1'b0),.write_finish_toggle(1'b0),
 .audio_track_index(3'd0),.audio_track_toggle(1'b0),.audio_fifo_wrusedw(9'd511),
 .bmp_width(16'd1280),.bmp_height(16'd720),.write_req_ack(1'b0),.SD_MISO(1'b0));
reg [31:0] sectors[0:4];reg [15:0] widths[0:4],heights[0:4];
integer count=0;
initial begin
 force dut.sd_init_done=1;force dut.scan_done=0;force dut.scan_kicked=1;
 force dut.bmp_ready=0;force dut.bmp_data_wr_en=0;force dut.audio_scan_found_valid=0;
 force dut.scan_found_valid=push;force dut.scan_found_sprint=0;
 force dut.scan_found_sector=discovered;force dut.scan_found_width=w;force dut.scan_found_height=h;
 force dut.commit_pulse=commit;force dut.pending_image=which;force dut.awaiting_commit=commit;
 if($bits(dut.image_sector0)!=EXPECTED_BITS || $bits(dut.image_width0)!=11 || $bits(dut.image_height0)!=11)
  $fatal(1,"Metadata width does not follow configured range");
end
always @(posedge clk)begin
 if(rst)count=0;
 else if(push)begin sectors[count]=discovered;widths[count]=w;heights[count]=h;count=count+1;end
 #1;
 if(rst && (dut.source_width!==0 || dut.source_height!==0 || dut.cache_valid!==0))
  $fatal(1,"Reset did not invalidate visible metadata");
 if(!rst && count==0 && dut.load_start_pulse)
  $fatal(1,"Uninitialized metadata was consumed before discovery");
 if(push && !rst && dut.sector_for(which)!==sectors[which])
  $fatal(1,"Sector boundary bits were truncated");
 if(commit && !rst && (dut.source_width!==widths[which] || dut.source_height!==heights[which]))
  $fatal(1,"Committed dimensions changed");
end
endmodule
module tb_image_metadata;
reg clk=0;always #5 clk=~clk;
reg rst=1,push=0,commit=0;reg [2:0] which=0;
reg [15:0] w=640,h=360;reg [31:0] epoch=0;
image_metadata_case #(131071,17) narrow_case(clk,rst,push,commit,which,w,h,epoch);
image_metadata_case #(1048575,20) board(clk,rst,push,commit,which,w,h,epoch);
image_metadata_case #(32'hffffffff,32) full(clk,rst,push,commit,which,w,h,epoch);
integer i;
initial begin
 repeat(3)@(negedge clk);rst=0;repeat(4)@(negedge clk);
 for(i=0;i<5;i=i+1)begin
  @(negedge clk);which=i;w=640+i*320;h=360+i*180;push=1;
  @(negedge clk);push=0;
 end
 for(i=0;i<5;i=i+1)begin
  @(negedge clk);which=i;commit=1;
  @(negedge clk);commit=0;
 end
 @(negedge clk);rst=1;repeat(3)@(negedge clk);rst=0;epoch=8;which=0;
 repeat(5)@(negedge clk);
 @(negedge clk);w=1920;h=1080;push=1;
 @(negedge clk);push=0;
 @(negedge clk);commit=1;
 @(negedge clk);commit=0;
 $display("PASS image metadata: 17/20/32-bit sector boundaries, five records, exact dimensions, payload lifetime and reset/rescan");
 $finish;
end
endmodule
