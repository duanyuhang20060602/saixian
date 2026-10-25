`timescale 1ns/1ps
module tb;
reg clk=0,rst=1;always #5 clk=~clk;
reg signed [5:0] a=0,b=0;wire signed [11:0] result;reg signed [11:0] expected;integer i,j;
photo_relief_wall_dsp_product dut(.clk(clk),.rst(rst),.a(a),.b(b),.p(result));
initial begin
 repeat(5)@(negedge clk);rst=0;
 for(i=-32;i<32;i=i+1)for(j=-32;j<32;j=j+1)begin
  a=i;b=j;expected=i*j;@(posedge clk);#1;if(result!==expected)$fatal(1,"native wall product %0d*%0d = %0d/%0d",a,b,result,expected);@(negedge clk);
 end
 rst=1;@(posedge clk);#1;if(result!==0)$fatal(1,"synchronous reset failed");
 $display("PASS all 4096 signed normal/light products in native DSP model, exact low 12 bits and registered reset");$finish;
end
endmodule
