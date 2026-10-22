`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,stream_clear=0,write_en=0,output_read=0;
reg [31:0] write_data=0;
wire [31:0] raw_pcm,output_pcm;wire raw_read,empty,full,ready,overrun;
wire [13:0] raw_used,output_used;wire [2:0] active_mode;
integer written=0,accepted=0,checked=0,total_checked=0,tick=0,max_used=0,era=0;
reg pop_pending=0,drain=0;
always #5 clk=~clk;
function [31:0] sample;
 input integer n,tag;
 begin sample={16'(25000-(n*71+tag*919)%50000),16'((n*37+tag*733)%50000-25000)};end
endfunction
photo_audio_fifo fifo(.clk(clk),.rst(rst || stream_clear),.write_en(write_en),.write_data(write_data),
 .read_en(raw_read),.data(raw_pcm),.empty(empty),.full(full),.used(raw_used));
photo_audio_pitch_b dut(.clk(clk),.rst(rst),.stream_clear(stream_clear),.enable(1'b1),.repair_enable(1'b0),
 .requested_mode(3'd0),.raw_used(raw_used),.raw_pcm(raw_pcm),.raw_read(raw_read),
 .output_read(output_read),.output_pcm(output_pcm),.output_used(output_used),.ready(ready),.overrun(overrun),.active_mode(active_mode));
always @(posedge clk)begin
 if(rst || stream_clear)begin accepted=0;pop_pending=0;end
 else begin
  if(dut.state==2 && raw_pcm!==sample(accepted-1,era))$fatal(1,"raw FIFO missing/repeated frame %0d %h",accepted-1,raw_pcm);
  if(raw_read)accepted=accepted+1;
  pop_pending=output_read && output_used!=0;
  if(overrun)$fatal(1,"producer overrun");
 end
end
always @(negedge clk)begin
 if(rst || stream_clear)begin written=0;checked=0;write_en=0;output_read=0;tick=0;end
 else begin
  if(pop_pending)begin
   if(checked<2303 && output_pcm!==0)$fatal(1,"stale history in startup at %0d: %h",checked,output_pcm);
   if(checked>=2400 && output_pcm!==sample(checked-1215,era))
    $fatal(1,"loss/reorder at %0d got %h expected %h",checked,output_pcm,sample(checked-1215,era));
   checked=checked+1;total_checked=total_checked+1;
  end
  tick=tick+1;write_en=written<7500 && !full && tick%3==0;
  if(write_en)begin write_data=sample(written,era);written=written+1;end
  output_read=drain && output_used!=0 && tick%1100==0 && tick%9900!=0;
  if(output_used>max_used)max_used=output_used;
 end
end
initial begin
 repeat(5)@(negedge clk);rst=0;
 wait(output_used==256);repeat(5000)@(negedge clk);
 if(output_used!=256 || accepted!=256)$fatal(1,"queue did not backpressure exactly one outstanding frame %0d/%0d",output_used,accepted);
 drain=1;wait(checked>=6200);
 wait(dut.state==3 && dut.pitch.state!=0);@(negedge clk);stream_clear=1;era=1;
 repeat(5)@(negedge clk);stream_clear=0;
 wait(checked>=2800);
 if(max_used!=256 || total_checked<9000)$fatal(1,"coverage");
 $display("PASS %0d lossless queued stereo frames, 1215-sample dry delay, raw FIFO latency, ring wrap, full-queue backpressure, mid-flight clear and no stale history",total_checked);$finish;
end
initial begin #300000000;$fatal(1,"flow timeout");end
endmodule
