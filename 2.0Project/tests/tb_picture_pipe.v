`timescale 1ns/1ps
module tb_picture_pipe;
reg clk=0;always #5 clk=~clk;
reg rst=1,de=1;reg [10:0] x=0;
reg [23:0] rgb=0;
reg [3:0] b=4,c=4,s=4;reg [1:0] sharp=0;
wire [23:0] out;
saixian_picture_adjust_pipe dut(clk,rst,de,x,rgb,b,c,s,sharp,out);
integer i,j;
task settle;begin repeat(11) @(negedge clk);end endtask
initial begin
 settle;rst=0;
 for(i=0;i<256;i=i+1) begin
  rgb={i[7:0],i[7:0],i[7:0]};settle;
  if(out!==rgb) $fatal(1,"neutral grayscale changed at %d: %h",i,out);
 end
 for(i=0;i<8;i=i+1) begin
  rgb={(i[2]?8'hFF:8'h00),(i[1]?8'hFF:8'h00),(i[0]?8'hFF:8'h00)};settle;
  if(out!==rgb) $fatal(1,"neutral primary overflow %h",out);
 end
 rgb=24'hFFFFFF;b=8;c=8;s=8;settle;if(out!==24'hFFFFFF) $fatal(1,"white overflow");
 rgb=0;b=0;settle;if(out!==0) $fatal(1,"black underflow");
 b=4;c=4;s=0;rgb=24'hFF0000;settle;
 if(out!==24'h3F3F3F) $fatal(1,"gray saturation arithmetic %h",out);
 $display("PASS 256 gray levels, primaries, brightness/contrast clamps, saturation");$finish;
end
endmodule
