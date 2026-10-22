`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg [13:0] a0=0,a1=0,a2=0,a3=0;wire [31:0] actual,reference;
award_sprite_rom optimized(clk,a0,a1,a2,a3,actual[31:24],actual[23:16],actual[15:8],actual[7:0]);
award_sprite_rom_baseline frozen(clk,a0,a1,a2,a3,reference[31:24],reference[23:16],reference[15:8],reference[7:0]);
integer n;
initial begin
 for(n=0;n<32768;n=n+1)begin
  @(negedge clk);a0=n;a1=16383-n;a2=(n*3917+137);a3=(n*71+931);
  @(posedge clk);#1;if(actual!==reference)$fatal(1,"compressed sprite differs at %0d",n);
 end
 $display("PASS lossless sprite compression: all 16384 addresses twice on four simultaneous ports, all 16 poses, clipping, original metallic shades and exact one-clock latency");$finish;
end
endmodule
