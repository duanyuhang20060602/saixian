`timescale 1ns/1ps
module tb_match_cues;
reg clk=0;always #5 clk=~clk;
reg rst=1;reg [3:0] event_id=0;
wire valid;wire [23:0] l,r;wire busy,active;wire [7:0] level;
// Accelerate clock time, retaining the true 48 kHz sample cadence ratio.
saixian_audio_cue #(.CLK_FREQ_HZ(50000)) d(.clk(clk),.rst(rst),.cue_event(event_id),.audio_valid(valid),
 .audio_left(l),.audio_right(r),.audio_level(level),.cue_busy(busy),.spectrum_active(active),.spectrum_tone_bin());
integer i,j,count,nonzero;reg [23:0] last_l,last_r;
initial begin
 repeat(4)@(negedge clk);rst=0;count=0;
 for(j=0;j<50000;j=j+1)begin @(posedge clk);#1;if(valid)count=count+1;end
 if(count!=48000)$fatal(1,"audio cadence %d",count);
 for(i=1;i<=5;i=i+1)begin
  @(negedge clk);event_id=i;@(negedge clk);event_id=0;
  nonzero=0;
  for(j=0;j<60000;j=j+1)begin
   @(posedge clk);#1;if(valid && (l!=0 || r!=0))nonzero=nonzero+1;
   if(l!==r)$fatal(1,"cue stereo mismatch");
  end
  if(nonzero<100)$fatal(1,"silent cue %d",i);
 end
 $display("PASS audio cues: 48 kHz cadence, countdown/start/pause/resume/finish audible PCM");$finish;
end
endmodule
