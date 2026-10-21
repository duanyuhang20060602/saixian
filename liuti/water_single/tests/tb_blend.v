`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=1,valid=0;reg[31:0] a,b;reg[8:0] alpha;
wire out_valid;wire[31:0] result;
water_blend dut(clk,rst,valid,a,b,alpha,out_valid,result);
reg[31:0] queue[0:31];integer head=0,tail=0,checked=0;
integer x,y,p,seed=9172;reg[31:0] ra,rb;
function[15:0] mix_pixel;
 input[15:0] a,b;input integer alpha;
 integer r,g,bl;
 begin
  r=(a[15:11]*(256-alpha)+b[15:11]*alpha+128)>>8;
  g=(a[10:5]*(256-alpha)+b[10:5]*alpha+128)>>8;
  bl=(a[4:0]*(256-alpha)+b[4:0]*alpha+128)>>8;
  mix_pixel={r[4:0],g[5:0],bl[4:0]};
 end
endfunction
always @(posedge clk)begin #1;
 if(out_valid)begin
  if(head==tail||result!==queue[head%32])$fatal(1,"shared blend mismatch %0d actual%h expected%h",checked,result,queue[head%32]);
  head=head+1;checked=checked+1;
 end
end
task send;
 input[31:0] aa,bb;input integer pp;
 begin
  @(negedge clk);a=aa;b=bb;alpha=pp;valid=1;
  queue[tail%32]={mix_pixel(aa[31:16],bb[31:16],pp),mix_pixel(aa[15:0],bb[15:0],pp)};tail=tail+1;
  @(negedge clk);valid=0;
 end
endtask
initial begin
 repeat(5)@(negedge clk);rst=0;
 // All green-channel endpoint pairs at every 9-bit interpolation weight.
 // Red/blue use different permutations and their opposite signs in each pixel.
 for(p=0;p<=256;p=p+1)for(x=0;x<64;x=x+1)for(y=0;y<64;y=y+1)begin
  ra={x[4:0],x[5:0],y[4:0],y[4:0],y[5:0],x[4:0]};
  rb={y[4:0],y[5:0],x[4:0],x[4:0],x[5:0],y[4:0]};send(ra,rb,p);
 end
 for(x=0;x<4096;x=x+1)begin
  ra=$random(seed);rb=$random(seed);send(ra,rb,x%257);
  repeat(x%4)@(negedge clk);
 end
 repeat(12)@(negedge clk);
 if(head!=tail)$fatal(1,"lost shared blend output");
 $display("PASS %0d exact RGB565 blends, all 257 weights and all 64x64 green pairs, back-to-back pairs and gaps",checked);$finish;
end
initial begin #50000000;$fatal(1,"blend timeout");end
endmodule
