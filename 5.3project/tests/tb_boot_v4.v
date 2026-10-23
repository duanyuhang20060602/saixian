`timescale 1ns/1ps
module tb_boot_v4;
reg clk=0;always #5 clk=~clk;
reg rst=1,tick=0,memory_ready=0,catalog_ready=0,frame_ready=0;
reg [11:0] x=0;reg [10:0] y=0;wire active;wire [23:0] rgb;
photo_boot_screen #(.MIN_FRAMES(4)) dut(clk,rst,tick,x,y,memory_ready,catalog_ready,frame_ready,active,rgb);
reg [23:0] expected[0:25];integer i,cycles=0;
always @(posedge clk)begin
 if(rst)begin cycles=0;for(i=0;i<26;i=i+1)expected[i]=0;end
 else begin
  for(i=25;i>0;i=i-1)expected[i]=expected[i-1];expected[0]=dut.color;cycles=cycles+1;
  #1;if(cycles>26 && rgb!==expected[25])$fatal(1,"boot HDMI delay mismatch");
 end
end
task frame;
 begin @(negedge clk);tick=1;@(negedge clk);tick=0;repeat(2)@(negedge clk);end
endtask
integer n,px,py,fd;reg [7:0] saved_phase;
initial begin
 repeat(5)@(negedge clk);rst=0;
 repeat(100)frame();if(!active)$fatal(1,"boot exited without an actual display frame");
 x=10;y=10;#1;if(dut.color!==0)$fatal(1,"boot background not black");
 x=635;y=260;#1;if(dut.color==0)$fatal(1,"spinner not drawn");
 saved_phase=dut.phase;repeat(8)frame();if(saved_phase==dut.phase)$fatal(1,"loading spinner stopped");
 memory_ready=1;repeat(30)frame();if(dut.progress!=224)$fatal(1,"memory loading stage");
 catalog_ready=1;repeat(30)frame();if(dut.progress!=400)$fatal(1,"media loading stage");
 // Preview uses the same RTL color function, with the animation state held.
 fd=$fopen("tests/results/boot_preview.ppm","wb");$fwrite(fd,"P6\n1280 720\n255\n");
 for(py=0;py<720;py=py+1)for(px=0;px<1280;px=px+1)begin
  x=px;y=py;#1;$fwrite(fd,"%c%c%c",dut.color[23:16],dut.color[15:8],dut.color[7:0]);
 end
 $fclose(fd);
 frame_ready=1;repeat(9)frame();if(!active)$fatal(1,"boot left before progress settled");
 repeat(4)frame();if(active)$fatal(1,"boot did not reveal ready frame");
 frame_ready=0;catalog_ready=0;memory_ready=0;repeat(20)frame();
 if(active)$fatal(1,"boot replayed after ordinary image/format changes");
 rst=1;repeat(3)@(negedge clk);if(!active)$fatal(1,"power reset failed to restore boot");
 $display("PASS boot: black background, spinner, real stage progress, wait for complete frame, blanking-only one-shot exit, reset, 26-clock HDMI alignment");$finish;
end
initial begin #5000000;$fatal(1,"boot timeout");end
endmodule
