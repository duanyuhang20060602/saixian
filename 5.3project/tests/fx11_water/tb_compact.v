`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg[13:0] ra=0,wa=0;reg we=0;reg[31:0] wd=0;wire[31:0] rd;
water_cache #(.BANKS(3),.TAIL_HALF(1)) cache(clk,ra,wa,we,wd,rd);
reg[11:0] address=0;wire[16:0] value;
water_inverse_rom rom(clk,address,value);
reg[16:0] inverse[0:2047];integer i,pass,checks=0;
function[31:0] pattern;input integer a,p;begin pattern=(a*32'h9e3779b9)^(p*32'h7126a9c3);end endfunction
initial begin
 $readmemh("water_inverse.hex",inverse);
 for(pass=0;pass<2;pass=pass+1)begin
  for(i=0;i<5120;i=i+1)begin @(negedge clk);we=1;wa=i;wd=pattern(i,pass);end
  @(negedge clk);we=0;repeat(3)@(negedge clk);
  for(i=0;i<5120;i=i+1)begin
   @(negedge clk);ra=i;repeat(2)@(posedge clk);#1;
   if(rd!==pattern(i,pass))$fatal(1,"compact cache address%0d pass%0d",i,pass);checks=checks+1;
  end
 end
 for(i=0;i<4096;i=i+1)begin
  @(negedge clk);address=i;@(posedge clk);#1;
  if(value!==(i<2048 ? inverse[i]:17'd0))$fatal(1,"reciprocal coefficient %0d",i);
 end
 $display("PASS compact cache: %0d reads across every bank/tail boundary and 4096 exact reciprocal coefficients",checks);$finish;
end
endmodule
