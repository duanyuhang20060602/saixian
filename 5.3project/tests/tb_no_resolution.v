`timescale 1ns/1ps
module tb_no_resolution;
reg clk=0;always #5 clk=~clk;
reg rst=1;reg [9:0] x=0;reg [8:0] y=0;integer px,py;
saixian_osd_overlay #(.SHOW_SOURCE_RESOLUTION(0)) dut(.clk(clk),.rst(rst),.frame_tick(1'b0),.de_i(1'b1),.x_i(x),.y_i(y),
 .display_valid(1'b1),.state(4'd0),.settings_mode(1'b0),.error_code(3'd0),.ticker_text_length(5'd0),.title_text_length(5'd0),.source_width_bcd(16'h1920),.source_height_bcd(16'h1080));
initial begin
 repeat(3)@(negedge clk);rst=0;repeat(3)@(negedge clk);
 for(py=23;py<=40;py=py+1)for(px=399;px<640;px=px+1)begin
  @(negedge clk);x=px;y=py;@(posedge clk);#1;
  if(dut.text_region)$fatal(1,"resolution still visible at %0d,%0d",px,py);
 end
 $display("PASS resolution text disabled across previous display area");$finish;
end
endmodule
