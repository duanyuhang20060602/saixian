module photo_award_notice_reference(input clk,rst,input [2:0] notice,input [11:0] x,input [10:0] y,
 input [23:0] rgb_in,output [23:0] rgb_out);
reg notice_visible;
wire box=notice_visible && x>=16 && x<280 && y>=16 && y<48;
wire letters=x>=24 && x<264 && y>=22 && y<36;
wire [11:0] dx=x-24;wire [10:0] dy=y-22;
reg [119:0] message;reg [7:0] ch;reg [34:0] glyph;reg ink;
always @(posedge clk or posedge rst)begin
 if(rst)begin message<=0;notice_visible<=0;end
 else begin
 notice_visible<=notice!=0;
 case(notice)
  1:message<="AWARD LOADING  ";
  2:message<="AWARD NOT FOUND";
  3:message<="AWARD ERROR    ";
  4:message<="PHOTO ERROR    ";
  default:message<=0;
 endcase
 end
end
always @*begin
 ch=(message >> ((14-dx[7:4])*8));
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
