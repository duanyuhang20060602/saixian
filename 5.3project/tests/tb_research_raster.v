`timescale 1ns/1ps
module raster_case #(parameter HT=1650,VT=750,START_Y=720,DELAY=21)(input clk,rst,output reg [31:0] checks=0);
wire [11:0] x;wire [10:0] y;wire valid;wire [8:0] scaled;
photo_raster_delay #(.HT(HT),.VT(VT),.START_Y(START_Y),.DELAY(DELAY),.SCALE_Y(1)) dut(
 .clk(clk),.rst(rst),.x(x),.y(y),.valid(valid),.y_two_thirds(scaled));
integer reference_x=0,reference_y=0,age=0;reg reference_valid=0;
reg [20:0] product;reg [8:0] reference_registered=0,actual_registered=0;
always @(posedge clk or posedge rst)begin
 if(rst)begin reference_x=0;reference_y=0;age=0;reference_valid=0;reference_registered<=0;actual_registered<=0;end
 else begin
  product=reference_y*683;reference_registered<=product[18:10];actual_registered<=scaled;
  if(!reference_valid)begin
   if(age==DELAY-1)begin reference_x=0;reference_y=START_Y;reference_valid=1;end
   else age=age+1;
  end else if(reference_x==HT-1)begin reference_x=0;reference_y=reference_y==VT-1 ? 0:((reference_y+1)&1023);end
  else reference_x=reference_x+1;
 end
 #1;product=reference_y*683;
 if({valid,y,x}!=={reference_valid,11'(reference_y),12'(reference_x)} || scaled!==product[18:10] || actual_registered!==reference_registered)
  $fatal(1,"scaled raster mismatch HT=%0d VT=%0d start=%0d at (%0d,%0d), got=%0d expected=%0d",HT,VT,START_Y,reference_x,reference_y,scaled,product[18:10]);
 if(!rst)checks=checks+1;
end
endmodule
module tb;
reg clk=0,rst=1;always #5 clk=~clk;
wire [31:0] a,b,c,d;
raster_case production(clk,rst,a);
raster_case #(.HT(5),.VT(1024),.START_Y(0),.DELAY(1)) full_y(clk,rst,b);
raster_case #(.HT(7),.VT(1024),.START_Y(721),.DELAY(34)) phase_one(clk,rst,c);
raster_case #(.HT(3),.VT(1024),.START_Y(722),.DELAY(26)) phase_two(clk,rst,d);
integer v;
initial begin
 for(v=0;v<1024;v=v+1)if(((683*v)>>10)!=(2*v)/3)$fatal(1,"algebraic identity failed");
 repeat(4)@(negedge clk);rst=0;
 repeat(9)@(negedge clk);#2;rst=1;#3;rst=0;
 repeat(10003)@(negedge clk);#3;rst=1;repeat(4)@(negedge clk);rst=0;
 repeat(2475100)@(negedge clk);
 $display("PASS incremental raster: %0d exact coordinate/scaled-output checks, 1024 y values, all modulo-3 phases, 9-bit wrap, two 720p frames, asynchronous restart",a+b+c+d);$finish;
end
initial begin #30000000;$fatal(1,"raster timeout");end
endmodule
