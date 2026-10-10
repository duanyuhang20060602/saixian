`timescale 1ns/1ps
// Exact native BMP test layout, RGB565 quantization and AVI limited range.
// Two clocks from raster coordinate to RGB, matching image-mode controls.
module builtin_pattern565(input clk,rst,input [11:0] x,input [10:0] y,
 output reg [15:0] rgb);
reg [7:0] ramp[0:2047]; /* fehdl force_ram=1, ram_style="bram" */
integer i;
initial for(i=0;i<2048;i=i+1)ramp[i]=i<1366 ? (i*255)/1365 : 0;
reg [7:0] gradient;
reg [11:0] x1;reg [10:0] y1;
always @(posedge clk)gradient<=ramp[x[10:0]];
always @(posedge clk or posedge rst)
 if(rst)begin x1<=0;y1<=768;end else begin x1<=x;y1<=y;end
reg [23:0] full_rgb;reg [7:0] value;
always @* begin
 full_rgb=0;value=0;
 if(y1<256)begin
  if(x1<171)full_rgb=24'hffffff;
  else if(x1<342)full_rgb=24'hffff00;
  else if(x1<513)full_rgb=24'h00ffff;
  else if(x1<683)full_rgb=24'h00ff00;
  else if(x1<854)full_rgb=24'hff00ff;
  else if(x1<1025)full_rgb=24'hff0000;
  else if(x1<1196)full_rgb=24'h0000ff;
 end else if(y1<512)begin
  case(y1[7:6])
   0:full_rgb={gradient,gradient,gradient};
   1:full_rgb={gradient,16'd0};
   2:full_rgb={8'd0,gradient,8'd0};
   3:full_rgb={16'd0,gradient};
  endcase
 end else begin
  if(x1<455)value=(x1[3]^y1[3]) ? 255 : 0;
  else if(x1<910)value=x1[0] ? 255 : 0;
  else value=y1[0] ? 255 : 0;
  full_rgb={value,value,value};
 end
 if(x1<4 || x1>=1362 || y1<4 || y1>=764)full_rgb=24'hffffff;
 if(x1==682 || x1==683 || y1==383 || y1==384)full_rgb=24'hff00ff;
end
wire [15:0] packed_rgb={full_rgb[23:19],full_rgb[15:10],full_rgb[7:3]};
always @(posedge clk or posedge rst)
 if(rst)rgb<=0;else rgb<=packed_rgb;
endmodule
