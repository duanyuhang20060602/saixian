`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=1,cup=0;reg[15:0] surface=0,base_color=0,bg2=0;
reg signed[5:0] light_x=0,light_y=0;
wire[23:0] before_rgb,after_rgb;
shader_before a(clk,rst,surface,base_color,cup,bg2,light_x,light_y,before_rgb);
shader_after b(clk,rst,surface,base_color,cup,bg2,light_x,light_y,after_rgb);
integer i,checks=0;reg[31:0] rng=32'hcafebab1;
function[31:0] next_random;input[31:0] x;begin next_random=(x>>1)^((0-(x&1))&32'hd0000001);end endfunction
always @(negedge clk)begin
 if(before_rgb!==after_rgb)$fatal(1,"Pixel mismatch cycle=%0d before=%h after=%h",checks,before_rgb,after_rgb);
 checks=checks+1;
end
initial begin
 repeat(4)@(posedge clk);
 for(i=0;i<262144;i=i+1)begin
  @(negedge clk);rng=next_random(rng);surface=i[15:0];base_color=rng[15:0];bg2=rng[31:16];
  cup=i[17];light_x=rng[21:16];light_y=rng[27:22];rst=(i%4093==0);
 end
 @(negedge clk);rst=0;repeat(16)@(posedge clk);#2;
 $display("PASS relief_pipeline_equivalence all 65536 surface words in four contexts, random RGB565 and signed lights, reset and cycle-aligned exact RGB888 output; checks=%0d",checks);$finish;
end
endmodule
