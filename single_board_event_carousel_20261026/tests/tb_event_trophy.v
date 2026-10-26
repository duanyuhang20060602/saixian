`timescale 1ns/1ps
module tb_event_trophy;
reg clk=0;always #5 clk=~clk;reg [2:0] angle=0;reg [6:0] x=0,y=0;wire [3:0] index;
event_trophy_rom d(clk,angle,x,y,index);
reg [3:0] expected[0:73727];integer a,xx,yy,n;
initial begin
 $readmemh("trophy_expected.hex",expected);n=0;
 for(a=0;a<8;a=a+1)for(yy=0;yy<96;yy=yy+1)for(xx=0;xx<96;xx=xx+1)begin
  @(negedge clk);angle=a;x=xx;y=yy;@(posedge clk);#1;
  if(index!==expected[n])$fatal(1,"trophy bank/row/nibble error %d actual %d expected %d",n,index,expected[n]);n=n+1;
 end
 $display("PASS original trophy ROM: all 73728 pixels, eight angles and nine physical memory banks");$finish;
end
endmodule
