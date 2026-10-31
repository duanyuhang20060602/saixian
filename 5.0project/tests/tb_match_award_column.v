`timescale 1ns/1ps
module tb #(parameter SHARED=0);
reg clk=0;always #5 clk=~clk;reg rst=1,enable=1,pause=0,ft=0;reg[10:0] early_x=0,x=0;reg[9:0] y=0;reg[23:0] base=0;reg[5:0] tag=0;
always @(posedge clk)x<=early_x;
wire[23:0] rgb,reference_rgb;
award_fx #(.INITIAL_HOLD_FRAMES(0),.SHARED_MATH(SHARED),.EARLY_COLUMN(1)) d(.clk(clk),.rst(rst),.enable(enable),.pause(pause),.frame_tick(ft),.x(x),.early_x(early_x),.y(y),.base_rgb(base),.tag(tag),.rgb(rgb),.math_product_r(base[14:0]),.math_product_g({base[6:0],base[23:16]}));
award_fx_before_match #(.INITIAL_HOLD_FRAMES(0),.SHARED_MATH(SHARED)) reference(.clk(clk),.rst(rst),.enable(enable),.pause(pause),.frame_tick(ft),.x(x),.y(y),.base_rgb(base),.tag(tag),.rgb(reference_rgb),.math_product_r(base[14:0]),.math_product_g({base[6:0],base[23:16]}));
integer n,checks=0;reg[31:0] rng=32'h48234591;
always @(posedge clk)begin #1;
 if(!rst)begin
  if({d.components0,d.components1,d.components2,d.components3,d.wave0,d.breath0}!==
     {reference.components0,reference.components1,reference.components2,reference.components3,reference.wave0,reference.breath0})$fatal(1,"early column changed sprite or light phase");
  if(rgb!==reference_rgb)$fatal(1,"early column changed five-clock shader RGB");checks=checks+1;
 end
end
initial begin
 repeat(8)@(negedge clk);rst=0;
 for(n=0;n<200000;n=n+1)begin
  @(negedge clk);rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};early_x=rng[10:0];y=rng[20:11];base=rng[31:8];tag=rng[15:10];ft=n%37==1;pause=(n%503)>450;enable=n%50009!=1;
 end
 repeat(8)@(negedge clk);$display("PASS unchanged trophy/confetti/lighting: %d exact RGB and four sprite-center/phase cycles; all64 columns, motion, pause and enable",checks);$finish;
end
endmodule
