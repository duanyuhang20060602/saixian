`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,valid=0;always #5 clk=~clk;
reg [31:0] old_word=0,new_word=0;reg [8:0] alpha=0;
wire av,bv;wire [31:0] ad,bd;
water_blend actual(clk,rst,valid,old_word,new_word,alpha,av,ad);
water_blend_baseline frozen(clk,rst,valid,old_word,new_word,alpha,bv,bd);
integer w,d,n;
always @(posedge clk)begin #1;if(av!==bv || (av && ad!==bd))$fatal(1,"blend word/latency differs");end
initial begin
 repeat(3)@(negedge clk);rst=0;
 for(w=0;w<=256;w=w+1)for(d=-63;d<=63;d=d+1)
  if(actual.alpha_product(d,w)!==frozen.alpha_product(d,w))$fatal(1,"signed multiplier differs %0d/%0d",d,w);
 for(n=0;n<80000;n=n+1)begin
  @(negedge clk);valid=!n[0] && n%17!=0;old_word=$random;new_word=$random;alpha=n%257;
  rst=n%17003==3;
 end
 $display("PASS native blend: 32639 signed products, 80000 randomized word/alpha cycles, endpoint weights, gaps, reset, exact pixels and latency");$finish;
end
endmodule
