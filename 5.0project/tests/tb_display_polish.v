`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;reg rst=1,tick=0;reg [11:0] x=0;reg [10:0] y=0;
wire active;wire [23:0] boot;
photo_boot_screen #(.BAR_ONLY(1),.VIDEO_DELAY(26),.MIN_FRAMES(0),.COMPLETE_SCAN(1),.STAGED_LOADING(1)) ui(
 .clk(clk),.rst(rst),.frame_tick(tick),.x(x),.y(y),.memory_ready(1'b1),.catalog_ready(1'b1),.frame_ready(1'b1),.animation_ready(1'b1),.audio_ready(1'b1),
 .scan_ready(1'b1),.font_ready(1'b1),.photo_present(1'b1),.music_present(1'b1),.font_present(1'b1),.active(active),.rgb(boot));
reg [31:0] material=0;reg signed [5:0] lx=0,ly=0;reg wall=0;wire [23:0] bright,old;
photo_relief_shade_kernel shade(.clk(clk),.rst(rst),.material(material),.light_x(lx),.light_y(ly),.wall(wall),.wall_level(7'd48),.rgb(bright));
original_relief_shade_kernel original(.clk(clk),.rst(rst),.material(material),.light_x(lx),.light_y(ly),.wall(wall),.wall_level(7'd48),.rgb(old));
integer i,improved=0;reg [31:0] rng=32'h91827364;
task pixel;input integer px,py;input [23:0] wanted;begin
 @(negedge clk);x=px;y=py;repeat(28)@(negedge clk);if(boot!==wanted)$fatal(1,"boot extra graphics (%0d,%0d) got=%h wanted=%h",px,py,boot,wanted);
end endtask
initial begin
 repeat(5)@(negedge clk);rst=0;
 for(i=0;i<70;i=i+1)begin tick=1;@(negedge clk);tick=0;@(negedge clk);end
 if(active)$fatal(1,"startup completion changed");
 pixel(0,0,0);pixel(640,292,0);pixel(600,332,0);pixel(398,372,24'h163044);pixel(400,374,24'h359cd0);pixel(879,385,24'h359cd0);pixel(900,380,0);
 for(i=0;i<1000;i=i+1)begin
  rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
  material={16'h4208,rng[15:0]};lx=rng[21:16];ly=rng[27:22];wall=i[0];
  repeat(18)@(negedge clk);
  if(wall && bright!==old)$fatal(1,"wall shading changed");
  if(!wall)begin
   if(bright[23:16]<old[23:16] || bright[15:8]<old[15:8] || bright[7:0]<old[7:0])$fatal(1,"highlight darkened cup");
   if(bright!=old)improved=improved+1;
  end
 end
 if(improved<20)$fatal(1,"highlight improvement not exercised %0d",improved);
 $display("PASS bar-only startup latency/completion and stronger cup highlights (%0d samples), wall response exact",improved);$finish;
end
initial begin #10000000;$fatal(1,"timeout");end
endmodule
