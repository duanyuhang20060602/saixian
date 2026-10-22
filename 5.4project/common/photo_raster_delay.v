// The 720p raster advances every clock, including blanking. Reconstruct a
// delayed phase with counters instead of shifting every coordinate bit.
// Startup zeros match the old asynchronously reset shift registers exactly.
module photo_raster_delay #(parameter DELAY=21,HT=1650,VT=750,START_Y=720,SCALE_Y=0)(
 input clk,rst,output [11:0] x,output [10:0] y,output reg valid,
 output [8:0] y_two_thirds
);
localparam CW=$clog2(DELAY+1);
reg [CW-1:0] startup;reg [10:0] h;reg [9:0] v;
assign x={1'b0,h};assign y={1'b0,v};
always @(posedge clk or posedge rst)
 if(rst)begin startup<=0;h<=0;v<=0;valid<=0;end
 else if(!valid)begin
  if(startup==DELAY-1)begin h<=0;v<=START_Y;valid<=1;end
  else startup<=startup+1'b1;
 end else if(h==HT-1)begin h<=0;if(v==VT-1)v<=0;else v<=v+1'b1;end
 else h<=h+1'b1;
// Integer error accumulation, as in Bresenham's incremental rasterization.
// For every 10-bit y, (683*y)>>10 == floor(2*y/3). Retain the original
// nine-bit wrap and update on the same edge as v, including startup/blanking.
generate if(SCALE_Y)begin: scaled_y
 reg [8:0] quotient;reg [1:0] phase;
 assign y_two_thirds=quotient;
 always @(posedge clk or posedge rst)
  if(rst)begin quotient<=0;phase<=0;end
  else if(!valid)begin
   if(startup==DELAY-1)begin quotient<=(2*START_Y)/3;phase<=START_Y%3;end
  end else if(h==HT-1)begin
   if(v==VT-1 || v==10'd1023)begin quotient<=0;phase<=0;end
   else begin
    if(phase!=0)quotient<=quotient+1'b1;
    phase<=phase==2 ? 2'd0:phase+1'b1;
   end
  end
end else begin: unscaled_y
 assign y_two_thirds=9'd0;
end endgenerate
endmodule
