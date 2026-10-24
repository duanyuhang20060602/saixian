`timescale 1ns/1ps
module tb;
reg clk=0,rst=1;always #5 clk=~clk;
reg [11:0] x=0;reg [10:0] y=720;
wire [11:0] x21,x26,x34;wire [10:0] y21,y26,y34;wire v21,v26,v34;
photo_raster_delay #(.DELAY(21)) a(.clk(clk),.rst(rst),.x(x21),.y(y21),.valid(v21));
photo_raster_delay #(.DELAY(26)) b(.clk(clk),.rst(rst),.x(x26),.y(y26),.valid(v26));
photo_raster_delay #(.DELAY(34)) c(.clk(clk),.rst(rst),.x(x34),.y(y34),.valid(v34));
reg [22:0] history[0:63];reg [4:0] flags[0:63];integer pointer=0,age=0,checks=0,i;
reg [22:0] e21,e26,e34;reg [4:0] f21,f26,f34;
wire de=x<1280 && y<720;
always @(posedge clk)begin
 if(rst)begin pointer=0;age=0;for(i=0;i<64;i=i+1)begin history[i]=0;flags[i]=0;end x<=0;y<=720;end
 else begin
  history[pointer]={y,x};flags[pointer]={x==0 && y==720,y>=725 && y<730,de && x==1279,x==0 && y==0,de};
  e21=history[(pointer+64-20)%64];e26=history[(pointer+64-25)%64];e34=history[(pointer+64-33)%64];
  f21=flags[(pointer+64-20)%64];f26=flags[(pointer+64-25)%64];f34=flags[(pointer+64-33)%64];
  pointer=(pointer+1)%64;age=age+1;
  if(x==1649)begin x<=0;if(y==749)y<=0;else y<=y+1'b1;end else x<=x+1'b1;
  #1;
  if({y21,x21}!==e21 || {y26,x26}!==e26 || {y34,x34}!==e34)$fatal(1,"raster phase mismatch age=%0d",age);
  if((v21 && x21<1280 && y21<720)!==f21[0] ||
     {v26 && x26==0 && y26==720,v26 && y26>=725 && y26<730,v26 && x26==1279 && y26<720,v26 && x26==0 && y26==0,v26 && x26<1280 && y26<720}!==f26 ||
     (v34 && x34==1279 && y34<720)!==f34[2] || (v34 && x34==0 && y34==0)!==f34[1])$fatal(1,"raster marker mismatch");
  checks=checks+3;
 end
end
initial begin
 repeat(5)@(negedge clk);rst=0;
 repeat(17)@(negedge clk);rst=1;repeat(3)@(negedge clk);rst=0;
 repeat(357)@(negedge clk);rst=1;repeat(4)@(negedge clk);rst=0;
 repeat(1237600)@(negedge clk);
 if(checks<3700000)$fatal(1,"raster coverage too small");
 $display("PASS %0d exact delayed raster coordinates and DE/SOF/EOL/VS/frame markers, startup resets, every pixel/line/frame boundary",checks);$finish;
end
endmodule
