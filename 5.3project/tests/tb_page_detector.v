`timescale 1ns/1ps
module tb_page_detector;
reg clk=0;always #5 clk=~clk;
reg rst=1,valid=0;reg [2:0] image=0,count=0;wire event_out;
photo_page_change_event dut(clk,rst,valid,image,count,event_out);
task step;input v;input [2:0] im,n;input expected;
begin @(negedge clk);valid=v;image=im;count=n;@(posedge clk);#1;
if(event_out!==expected)$fatal(1,"page event im=%0d n=%0d v=%0d",im,n,v);end endtask
initial begin
 repeat(3)@(negedge clk);rst=0;
 step(1,0,6,0);step(1,0,6,0);step(0,1,6,0);step(1,1,6,1);
 step(1,1,6,0);step(1,6,6,0);step(1,1,6,0);step(1,5,6,1);step(1,0,6,1);
 step(1,0,0,0);step(1,3,6,0);step(1,4,6,1);
 $display("PASS committed photo detector: initial/repeat/preload/award silent, manual/auto/wrap one event");$finish;
end
endmodule
