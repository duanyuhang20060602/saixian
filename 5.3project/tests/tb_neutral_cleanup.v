`timescale 1ns/1ps
module tb_neutral_cleanup;
reg clk=0;always #5 clk=~clk;
reg rst=1,de=0;reg [23:0] rgb=0;reg [10:0] x=0;reg [9:0] y=0;
wire [23:0] enhanced,reference,actual;wire ed;wire [10:0] ex;
saixian_adaptive_enhance #(.WIDTH(1280),.PHOTO_SMOOTH(1)) old_enhance(.clk(clk),.rst(rst),.de(de),.vs(1'b0),.frame_tick(1'b0),.statistics_enable(1'b0),
 .x(x),.y(y),.rgb_in(rgb),.mode(2'd0),.strength(2'd0),.external_gain(2'd0),.rgb_out(enhanced),.de_out(ed),.x_out(ex));
saixian_picture_adjust_pipe old_adjust(.clk(clk),.rst(rst),.de(ed),.x(ex),.rgb_in(enhanced),
 .brightness_setting(4'd4),.contrast_setting(4'd4),.saturation_setting(4'd4),.sharpness_setting(2'd0),.rgb_out(reference));
photo_neutral_delay lean(.clk(clk),.rst(rst),.de(de),.rgb_in(rgb),.rgb_out(actual));
integer n;
initial begin
 repeat(5)@(negedge clk);rst=0;
 for(n=0;n<5000;n=n+1)begin
  rgb=$random;de=n%83<67;x=n%1280;y=n/1280;
  @(negedge clk);if(n>32 && actual!==reference)$fatal(1,"neutral cleanup differs at %0d actual=%h reference=%h",n,actual,reference);
 end
 $display("PASS neutral cleanup: 5000 random RGB pixels, DE gaps and exact original latency");$finish;
end
endmodule
