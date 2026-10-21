`timescale 1ns/1ps
module tb_fx_start;
reg clk=0;always #5 clk=~clk;
reg rst=1,en=1,valid=0,active=0;reg [2:0] image=0,count=6;reg [4:0] mode=0;
wire event_out;wire [3:0] style;integer i;
photo_transition_page_event dut(clk,rst,en,valid,active,image,count,mode,event_out,style);
task step;input a,e,v;input [2:0] im;input [4:0] m;input expected;
begin @(negedge clk);active=a;en=e;valid=v;image=im;mode=m;@(posedge clk);#1;
if(event_out!==expected)$fatal(1,"transition start gate mode=%0d",m);
if(expected && style!==(m<=10 ? m[3:0]:4'd0))$fatal(1,"actual mode not latched");end endtask
initial begin
 repeat(3)@(negedge clk);rst=0;
 step(0,1,1,0,0,0);
 for(i=0;i<11;i=i+1)begin
  step(1,1,1,0,i,1);step(1,1,1,1,i,0);step(0,1,1,1,i,0);
 end
 step(1,1,1,6,6,0);step(0,1,1,0,0,0);
 step(1,0,1,0,0,0);step(0,1,1,0,0,0);
 step(1,1,0,0,0,0);step(0,1,1,0,0,0);step(1,1,1,0,31,1);
 $display("PASS actual transition start styles: all 11 internal modes, one event before commit, initial/award/disabled/reset gates");$finish;
end
endmodule
