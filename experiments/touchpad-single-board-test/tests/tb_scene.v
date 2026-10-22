`timescale 1ns/1ps
module tb_scene;
reg clk=0;always #5 clk=~clk;
reg rst=1,frame=0,de=1;reg [11:0] x=0;reg [10:0] y=0;
wire [23:0] rgb;
touch_test_scene dut(.clk(clk),.rst(rst),.frame_tick(frame),.de(de),.x(x),.y(y),
 .cursor_x(11'd640),.cursor_y(10'd360),.raw_x(10'd472),.raw_y(9'd273),
 .mode_enabled(1'b1),.contact(1'b0),.rx_count(16'd86),.error_count(16'd0),.tap_count(16'd6),.selection(2'd2),.rgb(rgb));
task pixel;input [11:0] px;input [10:0] py;input [23:0] expected;
begin @(negedge clk);x=px;y=py;repeat(2)@(negedge clk);
 if(rgb!==expected)$fatal(1,"pixel %d,%d: %h expected %h",px,py,rgb,expected);end endtask
integer xx,yy,fd;
initial begin
 repeat(3)@(negedge clk);rst=0;frame=1;@(negedge clk);frame=0;
 pixel(160,420,24'h782c38);pixel(520,420,24'h50db80);pixel(900,420,24'h294b78);
 pixel(510,600,24'h52627a);pixel(640,360,24'h101010);pixel(643,368,24'hebebeb);
 // Top-left pixel of S is blank; the next source font column is lit.
 pixel(64,32,24'h142132);pixel(68,32,24'hebebeb);
 de=0;pixel(520,420,24'h101010);de=1;
 // Two-stage video alignment: old pixel remains at first stage, then new pixel.
 pixel(160,420,24'h782c38);
 @(negedge clk);x=520;@(negedge clk);
 if(rgb!==24'h782c38)$fatal(1,"early video pixel");
 @(negedge clk);if(rgb!==24'h50db80)$fatal(1,"late video pixel");
 fd=$fopen("tests/preview.ppm","w");$fwrite(fd,"P3\n640 360\n255\n");
 for(yy=0;yy<720;yy=yy+2)for(xx=0;xx<1280;xx=xx+2)begin
  @(negedge clk);x=xx;y=yy;repeat(2)@(negedge clk);
  $fwrite(fd,"%0d %0d %0d\n",rgb[23:16],rgb[15:8],rgb[7:0]);
 end
 $fclose(fd);$display("PASS test scene button colors, font, cursor, DE and two-cycle alignment");$finish;
end
endmodule
