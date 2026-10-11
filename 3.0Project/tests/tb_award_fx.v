`timescale 1ns/1ps
module tb_award_fx;
reg clk=0;always #5 clk=~clk;
reg rst=1,enable=0,pause=0,tick=0;
reg [10:0] x=640;reg [9:0] y=250;reg [23:0] base=24'hb09040;reg [5:0] tag=31;
wire [23:0] rgb;
award_fx dut(clk,rst,enable,pause,tick,x,y,base,tag,rgb);
integer i,j,rain_pixels=0,min_r=255,max_r=0;reg [9:0] saved_motion,saved_fraction;
task frame;begin @(negedge clk);tick=1;@(negedge clk);tick=0;repeat(6)@(negedge clk);end endtask
initial begin
 repeat(7)@(negedge clk);rst=0;enable=1;repeat(7)@(negedge clk);
 for(i=0;i<60;i=i+1)begin frame;#1;if(rgb!==base)$fatal(1,"first-image hold animated early");end
 frame;
 for(i=0;i<364;i=i+1)begin
  frame;#1;if(rgb[23:16]<min_r)min_r=rgb[23:16];if(rgb[23:16]>max_r)max_r=rgb[23:16];
 end
 if(dut.motion!=0 || dut.fraction!=0)$fatal(1,"six-second loop did not close");
 if(max_r-min_r<90 || min_r<140 || min_r>=base[23:16] || max_r<250)$fatal(1,"bright trophy must retain visible flow: %d %d",min_r,max_r);
 frame;pause=1;repeat(7)@(negedge clk);saved_motion=dut.motion;saved_fraction=dut.fraction;
 repeat(15)frame;
 if(dut.motion!=saved_motion || dut.fraction!=saved_fraction)$fatal(1,"pause did not freeze live effects");
 pause=0;repeat(7)@(negedge clk);frame;
 if(dut.motion==saved_motion)$fatal(1,"resume did not continue effects");
 tag=63;y=600;min_r=255;max_r=0;
 for(i=0;i<364;i=i+1)begin frame;#1;if(rgb[23:16]<min_r)min_r=rgb[23:16];if(rgb[23:16]>max_r)max_r=rgb[23:16];end
 if(max_r-min_r<150)$fatal(1,"wall breathing contrast insufficient");
 tag=0;y=600;repeat(7)@(negedge clk);
 for(i=0;i<1280;i=i+1)begin x=i;@(negedge clk);if(rgb!==base)$fatal(1,"title area modified by live effects");end
 for(j=0;j<548;j=j+1)for(i=0;i<1280;i=i+1)begin x=i;y=j;@(negedge clk);if(rgb!==base)rain_pixels=rain_pixels+1;end
 if(rain_pixels<5000)$fatal(1,"enlarged dense gold rain insufficient");
 enable=0;repeat(7)@(negedge clk);if(rgb!==base)$fatal(1,"effects before display is ready");
 $display("PASS award_fx: first-image hold, soft node/wall brightness range %d..%d, 364-frame closed loop, pause/resume, gold rain pixels=%d, title protection",min_r,max_r,rain_pixels);
 $finish;
end
initial begin #10000000;$fatal(1,"award effects timeout");end
endmodule
