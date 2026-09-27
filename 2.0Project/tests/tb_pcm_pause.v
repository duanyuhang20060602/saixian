`timescale 1ns/1ps
module tb_pcm_pause;
reg clk=0;always #5 clk=~clk;
reg rst=1,play=0,tick=0,valid=0;
reg [31:0] data=0;
wire read,active;wire [23:0] left,right;wire [7:0] level;wire [4:0] bin;
saixian_pcm_player dut(clk,rst,play,tick,1'b0,data,valid,read,left,right,level,active,bin);
integer next_sample=1,reads=0;
always @(posedge clk) begin
 if(rst) begin valid<=0;data<=0;next_sample=1;reads=0;end
 else begin
  valid<=read;
  if(read) begin data<={16'h2222,next_sample[15:0]};next_sample=next_sample+1;reads=reads+1;end
 end
end
task wait_sample;begin repeat(8) @(negedge clk);end endtask
task sample;begin tick=1;@(negedge clk);tick=0;end endtask
initial begin
 wait_sample;rst=0;tick=1;wait_sample;tick=0;
 if(reads || left!==0 || right!==0) $fatal(1,"paused player consumed startup music");
 play=1;wait_sample;sample;
 if(left!==24'h000100 || right!==24'h222200) $fatal(1,"first stereo sample skipped");
 wait_sample;play=0;wait_sample;
 if(reads!=2 || left!==0) $fatal(1,"paused player drains stream");
 play=1;sample;if(left!==24'h000200) $fatal(1,"resume skipped prefetched sample");
 $display("PASS no startup FIFO reads, preserved first sample and event-pause resume");$finish;
end
endmodule
