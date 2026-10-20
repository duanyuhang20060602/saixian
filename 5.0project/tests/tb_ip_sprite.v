`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg [13:0] a0=0,a1=0,a2=0,a3=0;wire [7:0] p0,p1,p2,p3,r0,r1,r2,r3;
award_sprite_rom dut(clk,a0,a1,a2,a3,p0,p1,p2,p3);
award_sprite_rom_ref_v5 ref_dut(clk,a0,a1,a2,a3,r0,r1,r2,r3);
integer n;
initial begin
 for(n=0;n<65536;n=n+1)begin
  @(negedge clk);a0=n;a1=n*73+129;a2=n*131+512;a3=n*317+1701;
  @(posedge clk);#1;
  if({p0,p1,p2,p3}!=={r0,r1,r2,r3})$fatal(1,"packed sprite mismatch %0d",n);
 end
 $display("PASS packed dual-port sprite ROM: 262144 exact reads, all poses/addresses/borders, unchanged one-clock latency");$finish;
end
endmodule
