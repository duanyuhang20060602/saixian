module photo_award_notice_before(input clk,rst,input [2:0] notice,input [11:0] x,input [10:0] y,
 input [23:0] rgb_in,output [23:0] rgb_out);
reg notice_visible;
wire box=notice_visible && x>=16 && x<280 && y>=16 && y<48;
wire letters=x>=24 && x<264 && y>=22 && y<36;
wire [11:0] dx=x-24;wire [10:0] dy=y-22;
reg [2:0] notice_code;reg [7:0] ch;reg [34:0] glyph;reg ink;
// The message has only four fixed alternatives. Select the character
// directly; a 120-bit variable barrel shift is unnecessary on every pixel.
function [7:0] notice_character;input[2:0] code;input[3:0] position;begin
 notice_character=0;
 case(code)
 1:case(position)
  0:notice_character=8'h41;
  1:notice_character=8'h57;
  2:notice_character=8'h41;
  3:notice_character=8'h52;
  4:notice_character=8'h44;
  5:notice_character=8'h20;
  6:notice_character=8'h4c;
  7:notice_character=8'h4f;
  8:notice_character=8'h41;
  9:notice_character=8'h44;
  10:notice_character=8'h49;
  11:notice_character=8'h4e;
  12:notice_character=8'h47;
  13:notice_character=8'h20;
  14:notice_character=8'h20;
  default:notice_character=0;
 endcase
 2:case(position)
  0:notice_character=8'h41;
  1:notice_character=8'h57;
  2:notice_character=8'h41;
  3:notice_character=8'h52;
  4:notice_character=8'h44;
  5:notice_character=8'h20;
  6:notice_character=8'h4e;
  7:notice_character=8'h4f;
  8:notice_character=8'h54;
  9:notice_character=8'h20;
  10:notice_character=8'h46;
  11:notice_character=8'h4f;
  12:notice_character=8'h55;
  13:notice_character=8'h4e;
  14:notice_character=8'h44;
  default:notice_character=0;
 endcase
 3:case(position)
  0:notice_character=8'h41;
  1:notice_character=8'h57;
  2:notice_character=8'h41;
  3:notice_character=8'h52;
  4:notice_character=8'h44;
  5:notice_character=8'h20;
  6:notice_character=8'h45;
  7:notice_character=8'h52;
  8:notice_character=8'h52;
  9:notice_character=8'h4f;
  10:notice_character=8'h52;
  11:notice_character=8'h20;
  12:notice_character=8'h20;
  13:notice_character=8'h20;
  14:notice_character=8'h20;
  default:notice_character=0;
 endcase
 4:case(position)
  0:notice_character=8'h50;
  1:notice_character=8'h48;
  2:notice_character=8'h4f;
  3:notice_character=8'h54;
  4:notice_character=8'h4f;
  5:notice_character=8'h20;
  6:notice_character=8'h45;
  7:notice_character=8'h52;
  8:notice_character=8'h52;
  9:notice_character=8'h4f;
  10:notice_character=8'h52;
  11:notice_character=8'h20;
  12:notice_character=8'h20;
  13:notice_character=8'h20;
  14:notice_character=8'h20;
  default:notice_character=0;
 endcase
 default:notice_character=0;
 endcase
end endfunction
always @(posedge clk or posedge rst)begin
 if(rst)begin notice_code<=0;notice_visible<=0;end
 else begin notice_code<=notice;notice_visible<=notice!=0;end
end
always @*begin
 ch=notice_character(notice_code,dx[7:4]);
 case(ch)
  "P":glyph=35'b11110_10001_10001_11110_10000_10000_10000;
  "H":glyph=35'b10001_10001_10001_11111_10001_10001_10001;
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
