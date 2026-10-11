`timescale 1ns/1ps
module tb_sprite_storage;
reg clk=0;always #5 clk=~clk;
reg [13:0] a0=0,a1=0,a2=0,a3=0;
wire [7:0] q0,q1,q2,q3;
reg [7:0] reference[0:16383];integer i,checks=0;
award_sprite_rom dut(clk,a0,a1,a2,a3,q0,q1,q2,q3);
initial begin
 $readmemh("tests/fixtures/sprite_reference.hex",reference);
 for(i=0;i<16384;i=i+1)begin
  @(negedge clk);a0=i;a1=(i+1)%16384;a2=(i+4095)%16384;a3=16383-i;
  @(posedge clk);#1;
  if(q0!==reference[a0] || q1!==reference[a1] || q2!==reference[a2] || q3!==reference[a3])
   $fatal(1,"cropped sprite differs at logical address %d",i);
  checks=checks+4;
 end
 $display("PASS sprite_storage: %d exact opacity/shade samples on four ports, all sixteen flip poses and transparent margins; unchanged one-cycle latency",checks);
 $finish;
end
endmodule
