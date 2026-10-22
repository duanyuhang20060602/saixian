`timescale 1ns/1ps
module tb_v4_award_equivalence;
reg clk=0;always #5 clk=~clk;
reg rst=1,enable=0,pause=0,frame_tick=0;
reg [10:0] x=0;reg [9:0] y=0;
reg [23:0] base_rgb=0;reg [5:0] tag=0;
wire [23:0] actual,reference;
wire [23:0] instant_actual,instant_reference;
integer checked=0;
award_fx dut(clk,rst,enable,pause,frame_tick,x,y,base_rgb,tag,actual);
v4_port_ref_award_fx frozen(clk,rst,enable,pause,frame_tick,x,y,base_rgb,tag,reference);
// photo_award_render uses zero initial hold in the production A bitstream.
award_fx #(.INITIAL_HOLD_FRAMES(0)) instant(clk,rst,enable,pause,frame_tick,x,y,base_rgb,tag,instant_actual);
v4_port_ref_award_fx #(.INITIAL_HOLD_FRAMES(0)) instant_frozen(clk,rst,enable,pause,frame_tick,x,y,base_rgb,tag,instant_reference);
always @(posedge clk)begin
 #1;if(!rst)begin
  if(actual!==reference)$fatal(1,"shader mismatch x=%d y=%d tag=%d actual=%h reference=%h",x,y,tag,actual,reference);
  if(instant_actual!==instant_reference)$fatal(1,"immediate-entry shader mismatch");
  checked=checked+1;
 end
end
initial begin
 repeat(4)@(negedge clk);rst=0;enable=1;
 // Exercise the natural initial hold, pause and phase state first.
 for(integer f=0;f<100;f=f+1)begin
  frame_tick=1;pause=f>=75 && f<85;@(negedge clk);
  frame_tick=0;repeat(8)@(negedge clk);
 end
 pause=0;
 // Sweep every flow/breath phase with both dark/bright and all tag gains.
 for(integer phase=0;phase<1024;phase=phase+1)begin
  force dut.motion=phase;force frozen.motion=phase;
  force instant.motion=phase;force instant_frozen.motion=phase;
  for(integer gain=0;gain<64;gain=gain+1)begin
   x=(phase*37+gain*31)%1280;y=(phase+gain*17)%720;
   tag=gain;base_rgb={8'(gain*4),8'(phase),8'(255-gain*4)};
   @(negedge clk);
  end
 end
 release dut.motion;release frozen.motion;
 release instant.motion;release instant_frozen.motion;
 enable=0;repeat(12)@(negedge clk);enable=1;repeat(12)@(negedge clk);
 // Exhaust all legal blend operands against the untouched branch renderer.
 for(integer background=0;background<256;background=background+1)
  for(integer foreground=0;foreground<256;foreground=foreground+1)
   for(integer alpha=0;alpha<16;alpha=alpha+1)
    if(dut.blend(background,foreground,alpha)!==frozen.blend(background,foreground,alpha))
     $fatal(1,"blend changed background=%0d foreground=%0d alpha=%0d",background,foreground,alpha);
 $display("PASS exhaustive 1048576 trophy blends");
 if(checked<65000)$fatal(1,"insufficient coverage");
 $display("PASS exact award shader retiming: %0d pixels, all 1024 phases and 64 tags, hold/pause/reset, unchanged latency",checked);$finish;
end
endmodule
