`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=1,enable=0,pause=0,tick=0;reg[10:0] x=0;reg[9:0] y=0;
reg[23:0] color=0;reg[5:0] tag=0;wire[23:0] actual,reference;
award_fx #(.INITIAL_HOLD_FRAMES(0)) dut(.clk(clk),.rst(rst),.enable(enable),.pause(pause),.frame_tick(tick),.x(x),.y(y),.base_rgb(color),.tag(tag),.rgb(actual));
original_award_fx #(.INITIAL_HOLD_FRAMES(0)) original(.clk(clk),.rst(rst),.enable(enable),.pause(pause),.frame_tick(tick),.x(x),.y(y),.base_rgb(color),.tag(tag),.rgb(reference));
integer i,f,xx,yy,checks=0,visible=0,phases=0,j;reg[8:0] phase_value,absolute_value;
reg frame_active=0,latency_check=0;reg[23:0] expected[0:4];reg[4:0] expected_valid=0;
reg[31:0] rng=32'h54d671a9;
always @(posedge clk)begin
 expected[0]<=color;for(j=1;j<5;j=j+1)expected[j]<=expected[j-1];
 expected_valid<={expected_valid[3:0],latency_check};
 if(frame_active && x<1280 && y<720)visible=visible+1;
 #1;
 if(!rst)begin
  if(actual!==reference)$fatal(1,"five-clock pixel changed x=%0d y=%0d tag=%0d actual=%h reference=%h",x,y,tag,actual,reference);
  if(dut.wave0!==original.wave0)$fatal(1,"wave register changed");
  if({dut.motion,dut.fraction,dut.initial_frames,dut.pause_meta,dut.pause_sync}!=={original.motion,original.fraction,original.initial_frames,original.pause_meta,original.pause_sync})$fatal(1,"motion/enable/pause state changed");
  if(expected_valid[4] && actual!==expected[4])$fatal(1,"bypass output latency changed from five clocks");
  checks=checks+1;
 end
end
initial begin
 for(i=0;i<512;i=i+1)begin
  phase_value=i;absolute_value=phase_value[8] ? (~phase_value+9'd1):phase_value;
  if(dut.phase_curve(phase_value)!==original.wave_curve(absolute_value[8:3]))
   $fatal(1,"direct phase lookup mismatch phase=%0d abs=%0d",phase_value,absolute_value);
  phases=phases+1;
 end
 $display("PASS exhaustive 512 phase inputs against untouched original signed absolute-value wave function");
 repeat(6)@(negedge clk);rst=0;
 // Disabled shader must be an exact five-clock identity for arbitrary RGB/tag.
 latency_check=1;
 for(i=0;i<64;i=i+1)begin @(negedge clk);color=i*24'h254713;tag=i;end
 latency_check=0;repeat(8)@(negedge clk);enable=1;
 // Natural motion at frame boundaries, paused frames, disable and re-entry.
 for(f=0;f<100;f=f+1)begin
  @(negedge clk);pause=f>=30 && f<45;enable=!(f>=60 && f<66);tick=1;
  color=f*24'h17496b;tag=f;
  @(negedge clk);tick=0;repeat(8)@(negedge clk);
 end
 pause=0;enable=1;
 for(yy=0;yy<750;yy=yy+1)begin
  for(xx=0;xx<1650;xx=xx+1)begin
   @(negedge clk);frame_active=1;x=xx;y=yy;tick=xx==0 && yy==720;
   rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};color=rng[23:0];tag=rng[29:24];
   pause=yy>=300 && yy<450;enable=!(yy>=150 && yy<165);
  end
 end
 @(negedge clk);frame_active=0;tick=0;enable=0;pause=0;repeat(20)@(negedge clk);
 // Another reset with live inputs verifies synchronous stage clearing too.
 rst=1;repeat(4)@(negedge clk);rst=0;enable=1;repeat(15)@(negedge clk);
 if(phases!=512 || visible!=921600 || checks<1237500)$fatal(1,"incomplete coverage %0d/%0d/%0d",phases,visible,checks);
 $display("PASS complete 720p award differential: visible=%0d total_same-cycle_RGB_checks=%0d; arbitrary RGB/64 tags, pause, enable/re-entry, frame boundary and reset, unchanged five-clock pipeline",visible,checks);$finish;
end
initial begin #30000000;$fatal(1,"wave differential timeout");end
endmodule
