`timescale 1ns/1ps
module tb_scaler_pacing;
reg clk=0;always #5 clk=~clk;
reg rst=1,start=0,pv=0;
wire ov,busy,fault;wire [23:0] rgb;
saixian_load_scaler #(.OUT_WIDTH(8),.OUT_HEIGHT(6)) dut(
 clk,rst,start,16'd4,16'd4,pv,24'hFFFFFF,ov,rgb,busy,fault);
integer cycle=0,last_cycle=-1000,n=0,i;
always @(negedge clk) begin
 cycle=cycle+1;
 if(ov) begin
  if(cycle-last_cycle<16) $fatal(1,"vertical output burst too fast");
  if(rgb!==24'hFFFFFF) $fatal(1,"paced RAM/interpolation alignment error");
  last_cycle=cycle;n=n+1;
 end
end
initial begin
 repeat(4) @(negedge clk);rst=0;
 @(negedge clk);start=1;@(negedge clk);start=0;
 repeat(40) @(negedge clk);
 for(i=0;i<16;i=i+1) begin
  @(negedge clk);pv=1;@(negedge clk);pv=0;
  repeat(128) @(negedge clk);
 end
 repeat(300) @(negedge clk);
 if(n!=48 || busy || fault) $fatal(1,"paced image incomplete: n=%0d busy=%b fault=%b",n,busy,fault);
 $display("PASS paced vertical writes: exact pixel count, RGB alignment, at least 16 clocks between pixels");
 $finish;
end
endmodule
