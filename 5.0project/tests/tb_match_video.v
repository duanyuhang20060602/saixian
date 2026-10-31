`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=1,active=0;wire[11:0] x;wire[10:0] y;wire valid;
photo_raster_delay #(.DELAY(34)) raster(.clk(clk),.rst(rst),.x(x),.y(y),.valid(valid),.y_two_thirds());
wire de=valid && x<1280 && y<720;
wire[23:0] base={x[7:0],y[7:0],x[7:0]^y[7:0]},rgb;wire od;
photo_match_video d(.clk(clk),.rst(rst),.active(active),.x34(x),.y34(y),.valid34(valid),.rgb_in(base),.de_in(de),.rgb_out(rgb),.de_out(od),
 .state(3'd2),.team_a(3'd0),.team_b(3'd1),.score_a(10'd123),.score_b(10'd45),.seconds(9'd29),.duration_index(2'd0),.countdown(2'd0));
integer cycles=0,score_pixels=0,base_pixels=0,changes=0;reg previous=0;reg entered=0,left=0;
always @(negedge clk)if(!rst)begin
 cycles=cycles+1;
 if(od!==de)$fatal(1,"34-clock DE alignment x=%d y=%d out=%b expected=%b",x,y,od,de);
 if(d.display!=previous)begin
  if(y<720)$fatal(1,"mode changed in active video");
  changes=changes+1;previous=d.display;
 end
 if(de)begin
  if(d.display)score_pixels=score_pixels+1;
  else begin base_pixels=base_pixels+1;if(rgb!==base)$fatal(1,"legacy pixels changed");end
 end
 if(valid && x==100 && y==100 && !entered)begin active=1;entered=1;end
 if(valid && x==200 && y==100 && d.display && !left)begin active=0;left=1;end
 if(left && !d.display && x==500 && y==720)begin
  if(changes!=2 || score_pixels!=921600 || base_pixels<921600)$fatal(1,"mode accounting changes=%d score=%d legacy=%d",changes,score_pixels,base_pixels);
  $display("PASS video integration: 34-clock RGB/DE, %d full scoreboard pixels, %d legacy pixels, blank-only mode switching",score_pixels,base_pixels);$finish;
 end
 if(cycles>4000000)$fatal(1,"video integration timeout");
end
initial begin repeat(4)@(negedge clk);rst=0;end
endmodule
