`timescale 1ns/1ps
// Unit-level isolation: unrelated vendor IP is omitted with iverilog -i.
module tb_frame_config;
reg clk=0;always #5 clk=~clk;
reg rst=1,ft=0;
reg [3:0] b=4,c=4,s=4;reg [1:0] sharp=1;reg inv=0,vin=0;
top dut();
initial begin
 force dut.video_clk=clk;force dut.rst_video=rst;force dut.frame_tick=ft;
 force dut.brightness_setting=b;force dut.contrast_setting=c;
 force dut.saturation_setting=s;force dut.sharpness_setting=sharp;
 force dut.invert_setting=inv;force dut.vintage_setting=vin;
 repeat(3) @(negedge clk);rst=0;
 b=8;c=7;s=6;sharp=3;inv=1;vin=1;
 repeat(3) @(negedge clk);
 if({dut.brightness_frame,dut.contrast_frame,dut.saturation_frame,dut.sharpness_frame,dut.invert_frame,dut.vintage_frame}
    !== {4'd4,4'd4,4'd4,2'd1,1'b0,1'b0}) $fatal(1,"configuration changed mid-frame");
 ft=1;@(negedge clk);ft=0;
 if({dut.brightness_frame,dut.contrast_frame,dut.saturation_frame,dut.sharpness_frame,dut.invert_frame,dut.vintage_frame}
    !== {b,c,s,sharp,inv,vin}) $fatal(1,"configuration not committed at frame boundary");
 b=0;c=0;s=0;sharp=0;inv=0;vin=0;repeat(5) @(negedge clk);
 if(dut.brightness_frame!==8 || dut.invert_frame!==1) $fatal(1,"frame configuration not held");
 $display("PASS frame-atomic picture configuration (vendor IP isolated)");$finish;
end
endmodule
