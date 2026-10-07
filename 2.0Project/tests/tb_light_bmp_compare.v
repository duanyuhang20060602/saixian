`timescale 1ns/1ps
module tb_light_bmp_compare;
reg clk=0;always #5 clk=~clk;
bmp_read dut(.clk(clk),.rst(1'b1),.op_abort(1'b0));
reg [31:0] a,b,random_state=32'h1479acd1;
integer i,lane,checks=0;
task check;
 begin
  if(dut.less_bytes(a,b)!==(a<b)) $fatal(1,"32-bit comparison mismatch %h < %h",a,b);
  checks=checks+1;
 end
endtask
initial begin
 for(lane=0;lane<4;lane=lane+1) begin
  for(i=0;i<256;i=i+1) begin
   b=i<<(lane*8);a=b;check;a=b-1;check;a=b+1;check;
  end
 end
 for(i=0;i<200000;i=i+1) begin
  random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};a=random_state;
  random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};b=random_state;check;
 end
 $display("PASS %0d independent unsigned32 comparisons: byte boundaries, equality, wrap and random full-width inputs",checks);$finish;
end
endmodule
