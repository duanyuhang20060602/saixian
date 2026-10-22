`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,prepare=0,request_valid=0;
reg [7:0] request_epoch=0;
reg [3:0] request_volume=5;
reg [31:0] raw_pcm=0;
wire [31:0] shared_pcm,parallel_pcm;
integer level,i,checks=0;
always #5 clk=~clk;
photo_audio_processing_b #(.SHARED_SCALE(1),.EXTERNAL_REPAIRED(1),.BOOSTED_VOLUME(1)) shared(
 .clk(clk),.rst(rst),.prepare(prepare),.request_valid(request_valid),.request_epoch(request_epoch),
 .request_bg(1'b1),.request_repair(1'b0),.request_volume(request_volume),.request_cue(4'd0),
 .raw_pcm(raw_pcm),.processed_pcm(shared_pcm),.page_cue_count(3'd0),.background_available(1'b1),
 .page_valid(1'b0),.page_style(4'd0));
photo_audio_processing_b #(.SHARED_SCALE(0),.EXTERNAL_REPAIRED(1),.BOOSTED_VOLUME(1)) parallel(
 .clk(clk),.rst(rst),.prepare(prepare),.request_valid(request_valid),.request_epoch(request_epoch),
 .request_bg(1'b1),.request_repair(1'b0),.request_volume(request_volume),.request_cue(4'd0),
 .raw_pcm(raw_pcm),.processed_pcm(parallel_pcm),.page_cue_count(3'd0),.background_available(1'b1),
 .page_valid(1'b0),.page_style(4'd0));
function [15:0] expected;
 input signed [15:0] sample;input integer volume;
 reg signed [63:0] wide;integer gain;
 begin
  gain=volume==0 ? 0:volume>=8 ? 13:volume+5;
  wide=sample;wide=(wide*gain)>>>3;
  expected=wide>32767 ? 16'h7fff:wide < -32768 ? 16'h8000:wide[15:0];
 end
endfunction
task check;
 input [31:0] word;
 reg [31:0] answer;
 begin
  @(negedge clk);raw_pcm=word;prepare=1;
  @(negedge clk);prepare=0;repeat(18)@(negedge clk);
  answer={expected($signed(word[31:16]),level),expected($signed(word[15:0]),level)};
  if(shared_pcm!==answer || parallel_pcm!==answer)
   $fatal(1,"gain/saturation level %0d sample %h shared %h parallel %h want %h",level,word,shared_pcm,parallel_pcm,answer);
  checks=checks+1;
 end
endtask
initial begin
 repeat(5)@(negedge clk);rst=0;
 level=5;check(32'h80007fff);check(32'hffff0001);
 for(level=0;level<=9;level=level+1)begin
  @(negedge clk);request_valid=1;request_epoch=request_epoch+1;request_volume=level==9 ? 15:level;
  @(negedge clk);request_valid=0;repeat(3)@(negedge clk);
  check(0);check(32'h7fff8000);check(32'h80007fff);check(32'hffff0001);check(32'h4000c000);
  for(i=0;i<512;i=i+1)check($random);
 end
 $display("PASS %0d boosted stereo frames, 0..8 levels, default 5, clamp, mute, signed saturation, both scaling schedules",checks);$finish;
end
endmodule
