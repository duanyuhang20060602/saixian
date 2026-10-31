`timescale 1ns/1ps
module tb;
reg clk=0,rst=1;always #5 clk=~clk;
reg [2:0] notice=0;reg [11:0] x=0;reg [10:0] y=0;reg [23:0] background=0;
wire [23:0] rgb,gold_rgb;integer n,i,j,count=0;
photo_award_notice dut(clk,rst,notice,x,y,background,rgb);
photo_award_notice_before golden(clk,rst,notice,x,y,background,gold_rgb);
initial begin
 repeat(4)@(negedge clk);rst=0;
 for(n=0;n<8;n=n+1)begin
  notice=n;repeat(3)@(negedge clk);
  for(j=0;j<64;j=j+1)for(i=0;i<320;i=i+1)begin
   x=i;y=j;background={i[7:0],j[7:0],8'h5a};#1;
   if(rgb!==gold_rgb)$fatal(1,"notice %0d pixel %0d,%0d got %h expected %h",n,i,j,rgb,gold_rgb);
   count=count+1;
  end
 end
 // Outside the panel, including large coordinates whose low bits alias text.
 for(i=0;i<4096;i=i+1)begin
  x=i;y=700;background=24'habc123;#1;if(rgb!==gold_rgb)$fatal(1,"outside-panel alias changed");
 end
 x=32;y=24;rst=1;#1;if(rgb!==gold_rgb || rgb!==background)$fatal(1,"reset behavior changed");
 $display("PASS compact notice renderer: %0d exact RGB pixels, all 8 notice codes, four original messages, all glyph rows/columns, panel bounds, outside aliases and reset; zero added latency/state",count);$finish;
end
initial begin #1000000;$fatal(1,"notice equivalence timeout");end
endmodule
