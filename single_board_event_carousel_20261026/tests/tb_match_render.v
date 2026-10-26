`timescale 1ns/1ps
module tb_match_render;
reg clk=0;always #5 clk=~clk;
reg rst=1,ft=0,de=0,vs=0;reg [10:0] x=0;reg [9:0] y=0;
reg [2:0] state=0,ta=0,tb=1;reg [9:0] a=0,b=0;reg [8:0] sec=30;reg [1:0] cd=0,dur=0;
wire [23:0] rgb;wire od,ov;
reg [1:0] page=0;reg lv=0,summary=0;reg [2:0] la=0,lb=1;reg [9:0] lsa=12,lsb=9;reg [6:0] round=1;
match_render d(clk,rst,ft,de,vs,x,y,state,ta,tb,a,b,sec,cd,dur,rgb,od,ov,page,lv,la,lb,lsa,lsb,round,summary);
integer file,index,row,col,count,scene;reg [3:0] dp=0,vp=0;
task pixel;
 input [10:0] xx;input [9:0] yy;input dd,vv;
 begin
  @(negedge clk);x=xx;y=yy;de=dd;vs=vv;dp={dp[2:0],dd};vp={vp[2:0],vv};
  @(posedge clk);#1;
  if(od!==dp[3] || ov!==vp[3])$fatal(1,"pixel control alignment");
  if(od)begin $fwrite(file,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);count=count+1;end
 end
endtask
task frame;
 input [255:0] path;
 begin
  file=$fopen(path,"wb");$fwrite(file,"P6\n1280 720\n255\n");count=0;
  @(negedge clk);ft=1;@(negedge clk);ft=0;
  for(row=0;row<750;row=row+1)for(col=0;col<1650;col=col+1)pixel(col,row,col<1280 && row<720,row>=725 && row<730);
  repeat(4)pixel(0,0,0,0);
  if(count!=921600)$fatal(1,"frame pixel count %d",count);
  $fclose(file);$display("PASS rendered %s: %d pixels",path,count);
 end
endtask
initial begin
 repeat(4)@(negedge clk);rst=0;
 state=5;page=0;frame("home.ppm");page=1;frame("teams.ppm");page=2;frame("schedule.ppm");page=3;frame("no_result.ppm");
 state=0;frame("setup.ppm");state=1;cd=3;frame("countdown.ppm");
 state=2;a=12;b=9;sec=10;frame("running.ppm");
 state=3;frame("paused.ppm");
 state=4;sec=0;frame("winner_a.ppm");summary=1;frame("summary.ppm");
 state=5;page=3;lv=1;a=0;b=0;round=1;frame("last_result.ppm");
 state=4;summary=0;a=12;b=12;frame("tie.ppm");
 // Inputs changing in active video must not publish a partial scoreboard.
 @(negedge clk);a=999;state=2;repeat(3)@(negedge clk);
 if(d.sa!=12 || d.fs!=4)$fatal(1,"state tore inside frame");
 @(negedge clk);ft=1;@(negedge clk);ft=0;
 if(d.sa!=999 || d.fs!=2)$fatal(1,"blank commit failed");
 $display("PASS atomic frame publication");$finish;
end
endmodule
