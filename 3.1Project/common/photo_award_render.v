// Input follows frame_pixels (two clocks from the raster). The original
// award effect takes five clocks; nineteen more align with HDMI's 26 clocks.
module photo_award_render(
 input clk,rst,enable,pause,frame_tick,
 input [10:0] x,input [9:0] y,input [23:0] tagged_rgb,
 output [23:0] rgb,output [23:0] menu_rgb
);
wire [15:0] pixel={tagged_rgb[23:19],tagged_rgb[15:10],tagged_rgb[7:3]};
wire [4:0] blue=pixel[0] ? {1'b0,pixel[10:7]} : {pixel[4:1],1'b0};
wire [5:0] green=pixel[0] ? {pixel[10:6],1'b0} : pixel[10:5];
wire [23:0] base={pixel[15:11],pixel[15:13],green,green[5:4],blue,blue[4:2]};
wire [23:0] effect_rgb;
award_fx #(.INITIAL_HOLD_FRAMES(0)) effect(.clk(clk),.rst(rst),.enable(enable),.pause(pause),.frame_tick(frame_tick),
 .x(x),.y(y),.base_rgb(base),.tag(pixel[5:0]),.rgb(effect_rgb));
reg [23:0] delay_rgb[0:18];integer i;
always @(posedge clk)begin
 if(rst)begin for(i=0;i<19;i=i+1)delay_rgb[i]<=0;end
 else begin delay_rgb[0]<=effect_rgb;
  for(i=1;i<19;i=i+1)delay_rgb[i]<=delay_rgb[i-1];end
end
assign rgb=delay_rgb[18];
assign menu_rgb=delay_rgb[13];
endmodule

// Coordinates and RGB arrive together at the existing 21-cycle menu tap.
// The small combinational banner adds no video latency or font RAM.
module photo_award_notice(input [1:0] notice,input [11:0] x,input [10:0] y,
 input [23:0] rgb_in,output [23:0] rgb_out);
wire box=notice!=0 && x>=16 && x<280 && y>=16 && y<48;
wire letters=x>=24 && x<264 && y>=22 && y<36;
wire [11:0] dx=x-24;wire [10:0] dy=y-22;
reg [119:0] message;reg [7:0] ch;reg [34:0] glyph;reg ink;
always @*begin
 case(notice)
  1:message="AWARD LOADING  ";
  2:message="AWARD NOT FOUND";
  3:message="AWARD ERROR    ";
  default:message=0;
 endcase
 ch=(message >> ((14-dx[7:4])*8));
 case(ch)
  "A":glyph=35'b01110_10001_10001_11111_10001_10001_10001;
  "W":glyph=35'b10001_10001_10001_10101_10101_11011_10001;
  "R":glyph=35'b11110_10001_10001_11110_10100_10010_10001;
  "D":glyph=35'b11110_10001_10001_10001_10001_10001_11110;
  "L":glyph=35'b10000_10000_10000_10000_10000_10000_11111;
  "O":glyph=35'b01110_10001_10001_10001_10001_10001_01110;
  "I":glyph=35'b11111_00100_00100_00100_00100_00100_11111;
  "N":glyph=35'b10001_11001_11001_10101_10011_10011_10001;
  "G":glyph=35'b01110_10001_10000_10111_10001_10001_01110;
  "T":glyph=35'b11111_00100_00100_00100_00100_00100_00100;
  "F":glyph=35'b11111_10000_10000_11110_10000_10000_10000;
  "U":glyph=35'b10001_10001_10001_10001_10001_10001_01110;
  "E":glyph=35'b11111_10000_10000_11110_10000_10000_11111;
  default:glyph=0;
 endcase
 ink=letters && dx[3:1]<5 && glyph[34-(dy[3:1]*5+dx[3:1])];
end
assign rgb_out=box ? (ink ? 24'hffffff:24'h202020):rgb_in;
endmodule
