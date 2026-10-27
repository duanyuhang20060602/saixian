`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=1;reg signed[5:0] a=0,b=0;wire signed[11:0] p;
photo_relief_product dut(.clk(clk),.rst(rst),.a(a),.b(b),.p(p));
reg[4:0] red=0,blue=0;reg[5:0] green=0;reg[7:0] gain=0;wire[25:0] packed_p,green_p;
photo_relief_lighting_product packed_dut(.clk(clk),.rst(rst),.a({red,8'd0,blue}),.b(gain),.p(packed_p));
photo_relief_lighting_product green_dut(.clk(clk),.rst(rst),.a({12'd0,green}),.b(gain),.p(green_p));
integer r,t,d,packed_checks=0,expected_red,expected_blue,expected_green,fine_red,fine_blue,fine_green;
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
 for(r=0;r<32;r=r+1)for(t=0;t<32;t=t+1)for(d=0;d<256;d=d+1)begin
  @(negedge clk);red=r;blue=t;green=r*2+(t%2);gain=d;
  expected_red=r*d;expected_blue=t*d;expected_green=(r*2+(t%2))*d;
  @(posedge clk);#1;
  if(packed_p[12:0]!==expected_blue || packed_p[25:13]!==expected_red || green_p!==expected_green)$fatal(1,"packed RGB cross-carry or latency mismatch r=%0d b=%0d gain=%0d",r,t,d);
  fine_red=(expected_red*33)>>11;fine_blue=(expected_blue*33)>>11;fine_green=(expected_green*65)>>13;
  if(fine_red<((((r<<3)|(r>>2))*d)>>9) || fine_red>((((r<<3)|(r>>2))*d)>>9)+1)$fatal(1,"red scaling error");
  if(fine_blue<((((t<<3)|(t>>2))*d)>>9) || fine_blue>((((t<<3)|(t>>2))*d)>>9)+1)$fatal(1,"blue scaling error");
  if(fine_green<(((((green<<2)|(green>>4))*d)>>9)) || fine_green>(((((green<<2)|(green>>4))*d)>>9))+1)$fatal(1,"green scaling error");
  packed_checks=packed_checks+1;
 end
 @(negedge clk);rst=1;@(posedge clk);#1;if(packed_p!==0 || green_p!==0)$fatal(1,"packed DSP sync reset");
 $display("PASS exact logic 6x6 all 4096 pairs plus native packed RGB diffuse: 262144 red/blue/gain cases, all 16384 green/gain pairs covered, no channel carry, <=1-code scaling error, registered latency and synchronous reset");$finish;
end
initial begin #5000000;$fatal(1,"product timeout");end
endmodule
