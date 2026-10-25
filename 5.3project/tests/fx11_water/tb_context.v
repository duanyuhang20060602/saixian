`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,focus=0,have=0;reg[2:0] image=0;reg[4:0] applied=0;
always #5 clk=~clk;
photo_cached_control_a #(.SETTINGS_LINK(1)) dut(.clk(clk),.rst(rst));
photo_cached_control_a_reference #(.SETTINGS_LINK(1)) reference(.clk(clk),.rst(rst));
integer n,checks=0;
initial begin
 force dut.settings_focus=focus;force reference.settings_focus=focus;
 force dut.have_current=have;force reference.have_current=have;
 force dut.current_image=image;force reference.current_image=image;
 force dut.applied_context=applied;force reference.applied_context=applied;
 repeat(2)@(negedge clk);
 for(n=0;n<1024;n=n+1)begin
  {focus,have,image,applied}=n;
  #1;
  if(dut.context_dirty!==reference.context_dirty || dut.live_context!==reference.live_context)
   $fatal(1,"context decode changed focus=%b have=%b image=%d applied=%h",focus,have,image,applied);
  checks=checks+1;@(negedge clk);
 end
 $display("PASS parallel context decode: %0d exhaustive comparisons across every focus/current/image/applied-context combination",checks);$finish;
end
endmodule
