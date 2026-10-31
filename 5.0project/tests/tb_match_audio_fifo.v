`timescale 1ns/1ps
module tb #(parameter AW=11);
localparam DEPTH=1<<AW;
reg clk=0;always #5 clk=~clk;reg rst=1,we=0,re=0;reg[31:0] wd=1;
wire[31:0] rd,refd;wire empty,full,refe,reff,ge511,ge512,lehalf;wire[AW:0] used,refu;
photo_match_audio_fifo #(.DEPTH(DEPTH),.AW(AW),.RAM32_HEAD(DEPTH)) d(clk,rst,we,wd,re,rd,empty,full,used,ge511,ge512,lehalf);
photo_audio_fifo #(.DEPTH(DEPTH),.AW(AW),.RAM32_HEAD(DEPTH)) reference(clk,rst,we,wd,re,refd,refe,reff,refu);
integer n=0,checks=0;reg[31:0] rng=32'h389367ab;reg pop;
always @(posedge clk)begin
 pop=re && !refe;#1;
 if(!rst)begin
  if({used,empty,full}!=={refu,refe,reff} || (pop && rd!==refd))$fatal(1,"FIFO cycle changed AW=%d used=%d/%d",AW,used,refu);
  if(ge511!==(used>=511) || ge512!==(used>=512) || lehalf!==(used<=(1<<(AW-1))))$fatal(1,"predictive threshold changed");
  checks=checks+1;
 end
end
initial begin
 repeat(4)@(negedge clk);rst=0;we=1;
 repeat(DEPTH+8)@(negedge clk);if(!full)$fatal(1,"full coverage");
 we=0;re=1;repeat(DEPTH+8)@(negedge clk);if(!empty)$fatal(1,"empty coverage");
 for(n=0;n<50000;n=n+1)begin
  @(negedge clk);rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};we=rng[3];re=rng[17];wd=rng;rst=n%997==1;
 end
 @(negedge clk);$display("PASS exact FIFO and511/512/half thresholds: AW=%0d, %0d cycles, full/empty, concurrent push/pop, resets and RAM data",AW,checks);$finish;
end
endmodule
