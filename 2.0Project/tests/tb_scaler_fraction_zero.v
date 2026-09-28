`timescale 1ns/1ps
// Bilinear (not VGA): a nonzero Q16 fraction may quantize to zero Q8 weight.
module tb_scaler_fraction_zero;
reg clk=0;always #5 clk=~clk;
reg rst=1,start=0,pv=0;reg [23:0] rgb=0;
wire ov,busy,fault;wire [23:0] out;
saixian_load_scaler #(.OUT_WIDTH(4),.OUT_HEIGHT(512)) dut(
 clk,rst,start,16'd2,16'd2,pv,rgb,ov,out,busy,fault);
integer i,n=0,y,w,r,g,b,cycle=0,last_cycle=-1000;
reg [23:0] a,z,expected;
function [23:0] quantized;
 input [23:0] p;
 begin quantized={p[23:19],p[23:21],p[15:10],p[15:14],p[7:3],p[7:5]};end
endfunction
always @(negedge clk) begin
 cycle=cycle+1;
 if(!rst && fault) $fatal(1,"bilinear scheduling fault");
 if(ov) begin
  if(n>=2048) $fatal(1,"extra bilinear output");
  y=n/4;w=(y*((65536)/511))>>8;
  r=a[23:16];g=a[15:8];b=a[7:0];
  r=r+((($signed({1'b0,z[23:16]})-r)*w)>>>8);
  g=g+((($signed({1'b0,z[15:8]})-g)*w)>>>8);
  b=b+((($signed({1'b0,z[7:0]})-b)*w)>>>8);
  expected=(y==511)?z:{r[7:0],g[7:0],b[7:0]};
  if(out!==expected) $fatal(1,"bilinear zero-Q8 fraction y=%d got=%h expected=%h",y,out,expected);
  if(cycle-last_cycle<16) $fatal(1,"bilinear pacing");
  last_cycle=cycle;n=n+1;
 end
end
initial begin
 a=quantized(24'h105028);z=quantized(24'hE020C0);
 repeat(4) @(negedge clk);rst=0;
 @(negedge clk);start=1;@(negedge clk);start=0;
 repeat(40) @(negedge clk);
 for(i=0;i<4;i=i+1) begin
  @(negedge clk);rgb=i<2?24'h105028:24'hE020C0;pv=1;
  @(negedge clk);pv=0;repeat(128) @(negedge clk);
 end
 repeat(34000) @(negedge clk);
 if(n!=2048 || busy || fault) $fatal(1,"bilinear incomplete n=%d",n);
 $display("PASS 2048 bilinear pixels: nonzero-Q16/zero-Q8 fraction and exact endpoint");$finish;
end
initial begin #500000;$fatal(1,"bilinear timeout");end
endmodule
