`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=1;reg[2:0] notice=0;reg[11:0] x=0;reg[10:0] y=0;reg[23:0] rgb=0;
wire[23:0] actual,expected;
photo_award_notice newer(clk,rst,notice,x,y,rgb,actual);
photo_award_notice_reference older(clk,rst,notice,x,y,rgb,expected);
integer n,c,checked=0;
always @(posedge clk)begin #1;
 if(actual!==expected)$fatal(1,"notice mismatch code%0d xy%0d,%0d got%h expected%h",notice,x,y,actual,expected);
 checked=checked+1;
end
initial begin
 repeat(4)@(negedge clk);rst=0;
 for(c=0;c<8;c=c+1)for(n=0;n<18000;n=n+1)begin
  @(negedge clk);x=n%300;y=n/300;notice=n%73==0 ? (c+3)%8:c;
  rgb=(n*24'h12345)^(c<<21);rst=n%1000==999;
 end
 rst=0;repeat(3)@(negedge clk);
 $display("PASS notice direct character lookup: %0d exact RGB comparisons, every message/character/pixel, empty and invalid notices, mid-line changes and reset",checked);$finish;
end
endmodule
