`timescale 1ns/1ps
module tb_fx_legacy_cues;
reg clk=0;always #5 clk=~clk;
reg rst=1,tick=0;reg [3:0] event_in=0;wire [23:0] a,b;wire busy_a,busy_b;integer i;
photo_audio_cue_samples #(.PAGE_STYLES(1)) enhanced(.clk(clk),.rst(rst),.cue_event(event_in),.page_style(4'd10),.sample_tick(tick),.audio_left(a),.cue_busy(busy_a));
photo_audio_cue_samples original(.clk(clk),.rst(rst),.cue_event(event_in),.sample_tick(tick),.audio_left(b),.cue_busy(busy_b));
initial begin
 repeat(3)@(negedge clk);rst=0;
 for(i=0;i<220000;i=i+1)begin
  @(negedge clk);tick=i%4==0;event_in=0;
  if(i%40000==0)event_in=i/40000%5+1;
  if(i%81001==0)rst=1;else rst=0;
  @(posedge clk);#1;
  if({a,busy_a}!=={b,busy_b})$fatal(1,"legacy event cue changed at %0d",i);
 end
 $display("PASS legacy competition cues: 220000 cycles bit-exact with style feature enabled, resets, sample gating and preemption");$finish;
end
endmodule
