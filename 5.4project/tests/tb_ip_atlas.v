`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg [12:0] address=0;wire [31:0] sprint,victory;
saixian_dictionary_atlas #(.ADDR(13),.NAME("saixian_sprint_atlas")) s(clk,address,sprint);
saixian_dictionary_atlas #(.ADDR(12),.NAME("saixian_victory_atlas")) v(clk,address[11:0],victory);
reg [31:0] sg[0:8191],vg[0:4095],s1,s2,v1,v2;integer n;
always @(posedge clk)begin s1<=sg[address];s2<=s1;v1<=vg[address[11:0]];v2<=v1;end
initial begin
 $readmemh("sprint_golden.hex",sg);$readmemh("victory_golden.hex",vg);
 for(n=0;n<16390;n=n+1)begin
  @(negedge clk);address=n;
  @(posedge clk);#1;
  if(n>2 && {sprint,victory}!=={s2,v2})$fatal(1,"atlas IP mapping differs at %0d",n);
 end
 $display("PASS dictionary eRAM allocation: every sprint/victory atlas word and unchanged two-clock latency");$finish;
end
endmodule
