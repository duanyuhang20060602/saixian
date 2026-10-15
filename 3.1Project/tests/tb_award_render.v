`timescale 1ns/1ps
// Exhaustive tag/base reconstruction and both output latencies, then the
// imported effect's pause/resume and reset-on-exit lifecycle.
module tb_award_render;
reg clk=0;always #5 clk=~clk;
reg rst=1,enable=0,pause=0,tick=0;
reg [15:0] p=0;reg [10:0] x=0;reg [9:0] y=0;
wire [23:0] input_rgb={p[15:11],p[15:13],p[10:5],p[10:9],p[4:0],p[4:2]};
wire [23:0] rgb,menu_rgb;
photo_award_render dut(clk,rst,enable,pause,tick,x,y,input_rgb,rgb,menu_rgb);
function [23:0] restored;
 input [15:0] v;reg [5:0] g;reg [4:0] b;
 begin
  b=v[0] ? {1'b0,v[10:7]}:{v[4:1],1'b0};
  g=v[0] ? {v[10:6],1'b0}:v[10:5];
  restored={v[15:11],v[15:13],g,g[5:4],b,b[4:2]};
 end
endfunction
reg [23:0] golden[0:23];integer i,n,cycles=0;reg check=1;
always @(posedge clk)begin
 if(rst)begin cycles=0;for(i=0;i<24;i=i+1)golden[i]=0;end
 else begin
  for(i=23;i>0;i=i-1)golden[i]=golden[i-1];
  golden[0]=restored(p);cycles=cycles+1;
  #1;
  if(check && cycles>24)begin
   if(rgb!==golden[23])$fatal(1,"26-cycle HDMI alignment or base decode cycle=%0d got=%h expected=%h",cycles,rgb,golden[23]);
   if(menu_rgb!==golden[18])$fatal(1,"21-cycle menu alignment");
  end
 end
end
task frame;
 begin @(negedge clk);tick=1;@(negedge clk);tick=0;repeat(4)@(negedge clk);end
endtask
reg [9:0] stopped;
initial begin
 repeat(4)@(negedge clk);rst=0;
 for(n=0;n<65536;n=n+1)begin p=n;x=n%1280;y=(n/1280)%720;@(negedge clk);end
 repeat(30)@(negedge clk);check=0;enable=1;
 repeat(72)frame();
 if(dut.effect.motion==0)$fatal(1,"motion never started");
 pause=1;repeat(5)@(negedge clk);stopped=dut.effect.motion;
 repeat(20)frame();if(dut.effect.motion!==stopped)$fatal(1,"paused motion changed");
 pause=0;repeat(5)@(negedge clk);repeat(10)frame();
 if(dut.effect.motion==stopped)$fatal(1,"resume failed");
 enable=0;repeat(5)@(negedge clk);
 if(dut.effect.motion!=0 || dut.effect.initial_frames!=0)$fatal(1,"exit did not reset effect");
 $display("PASS award all 65536 tag words, exact base restoration, HDMI/menu latency, motion pause/resume and mode exit");$finish;
end
endmodule
