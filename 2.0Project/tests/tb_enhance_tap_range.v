`timescale 1ns/1ps
// Exhaustively compare the range gate to the absolute-difference definition.
module tb_enhance_tap_range;
saixian_adaptive_enhance #(.WIDTH(4),.SPLIT_X(2)) dut(
 .clk(1'b0),.rst(1'b1),.de(1'b0),.vs(1'b0),.frame_tick(1'b0),
 .statistics_enable(1'b0),.x(11'd0),.y(10'd0),.rgb_in(24'd0),.mode(2'd0),.strength(2'd0));
integer a,b,v,difference;
reg [7:0] expected,actual;
initial begin
 for(v=0;v<2;v=v+1) for(a=0;a<256;a=a+1) for(b=0;b<256;b=b+1) begin
  difference=(a>b) ? a-b : b-a;
  expected=(v && difference<=24) ? b : a;
  actual=dut.tap(a[7:0],b[7:0],v[0]);
  if(actual!==expected) $fatal(1,"range gate mismatch a=%d b=%d valid=%d",a,b,v);
 end
 $display("PASS exhaustive enhancement range gate: 131072 input/valid combinations");
 $finish;
end
endmodule
