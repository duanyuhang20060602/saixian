`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,enable=1,pause=0,tick=0;always #5 clk=~clk;
reg[10:0]x=0;reg[9:0]y=0;reg[23:0]base=0;reg[5:0]tag=0;
wire[23:0]rgb,old_rgb;wire signed[8:0]dr,dg;wire[3:0]alpha;wire request;wire signed[14:0]px,py;
reg[7:0]forced_selected=0;reg[23:0]forced_flow=0;
award_fx #(.SHARED_MATH(1),.INITIAL_HOLD_FRAMES(0)) dut(.clk(clk),.rst(rst),.enable(enable),.pause(pause),.frame_tick(tick),.x(x),.y(y),.base_rgb(base),.tag(tag),.rgb(rgb),.math_delta_r(dr),.math_delta_g(dg),.math_alpha(alpha),.math_request(request),.math_product_r(px),.math_product_g(py));
award_fx_before #(.INITIAL_HOLD_FRAMES(0)) reference(.clk(clk),.rst(rst),.enable(enable),.pause(pause),.frame_tick(tick),.x(x),.y(y),.base_rgb(base),.tag(tag),.rgb(old_rgb));
photo_award_math_bank bank(clk,rst,request,dr,dg,alpha,6'sd23,-6'sd31,-6'sd17,6'sd29,px,py);
integer a,b,checks=0;
always @(posedge clk)begin #1;if(rgb!==old_rgb)$fatal(1,"RGB/latency mismatch actual=%h old=%h selected=%h flow=%h",rgb,old_rgb,dut.selected3,dut.flow3);checks=checks+1;end
initial begin
 repeat(3)@(negedge clk);rst=0;
 force dut.selected3=forced_selected;force reference.selected3=forced_selected;
 force dut.flow3=forced_flow;force reference.flow3=forced_flow;
 for(a=0;a<256;a=a+1)for(b=0;b<256;b=b+1)begin
  forced_selected=b;forced_flow={a[7:0],a[7:0],a[7:0]};@(negedge clk);
 end
 for(a=0;a<20000;a=a+1)begin forced_selected=$random;forced_flow=$random;rst=(a%791)==0;@(negedge clk);end
 rst=0;release dut.selected3;release reference.selected3;release dut.flow3;release reference.flow3;
 for(a=0;a<200000;a=a+1)begin
  base=$random;tag=a[5:0];x=(a*7)%1280;y=(a*11)%720;tick=a%1650==0;
  enable=(a%17011)>8;pause=(a%1231)<300;rst=a%33331==0;@(negedge clk);
 end
 $display("PASS shared foil: %0d same-cycle RGB comparisons including all 65536 opacity/color/background combinations, random RGB, tags, enable, pause and reset",checks);$finish;
end
endmodule
