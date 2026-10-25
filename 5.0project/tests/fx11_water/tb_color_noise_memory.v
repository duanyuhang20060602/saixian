`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg[9:0] a=0,b=0;wire[8:0] qa,qb;reg[8:0] memory[0:1023];integer i;
water_color_noise_rom dut(clk,a,b,qa,qb);
initial begin
 $readmemh("common/fluid/water_color_noise.hex",memory);
 repeat(3)@(negedge clk);
 for(i=0;i<4096;i=i+1)begin
  a=i%1024;b=(i*313+17)%1024;
  @(negedge clk);
  if(qa!==memory[a]||qb!==memory[b])$fatal(1,"color DP ROM mismatch %0d %0d",a,b);
 end
 $display("PASS color_noise_memory 8192 independent dual-port samples, every 1024x9 coefficient, native one-clock latency");$finish;
end
endmodule
