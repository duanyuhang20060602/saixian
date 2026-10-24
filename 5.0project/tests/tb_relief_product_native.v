`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=1;reg signed[5:0] a=0,b=0;wire signed[11:0] p;
photo_relief_product dut(.clk(clk),.rst(rst),.a(a),.b(b),.p(p));
integer i,j,checks=0;reg signed[11:0] expected,held;
initial begin
 repeat(4)@(negedge clk);
 rst=0;
 for(i=-32;i<32;i=i+1)begin
  for(j=-32;j<32;j=j+1)begin
   @(negedge clk);a=i;b=j;expected=i*j;
   @(posedge clk);#1;
   if(p!==expected)$fatal(1,"signed product mismatch a=%0d b=%0d actual=%0d expected=%0d",a,b,p,expected);
   checks=checks+1;
  end
 end
 // A reset between clocks must not asynchronously alter the DSP register.
 @(negedge clk);a=-32;b=-32;
 @(posedge clk);#1;held=p;
 #1;rst=1;#1;
 if(p!==held)$fatal(1,"reset was asynchronous");
 @(posedge clk);#1;if(p!==0)$fatal(1,"synchronous reset failed");
 @(negedge clk);rst=0;a=31;b=-32;
 @(posedge clk);#1;if(p!==-12'sd992)$fatal(1,"first post-reset product latency");
 $display("PASS native vendor EG_PHY_MULT18 all 4096 signed 6x6 pairs, one-clock latency and synchronous reset checks=%0d",checks);$finish;
end
initial begin #1000000;$fatal(1,"product timeout");end
endmodule
