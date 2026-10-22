module touch_test_scene(
 input clk,rst,frame_tick,de,input [11:0] x,input [10:0] y,
 input [10:0] cursor_x,input [9:0] cursor_y,raw_x,input [8:0] raw_y,
 input mode_enabled,contact,input [15:0] rx_count,error_count,tap_count,
 input [1:0] selection,output reg [23:0] rgb
);
reg [9:0] rx_hold;reg [8:0] ry_hold;
reg [10:0] cx_hold;reg [9:0] cy_hold;
reg mode_hold,contact_hold;reg [1:0] sel_hold;
reg [15:0] count_hold,error_hold,tap_hold;
always @(posedge clk or posedge rst)begin
 if(rst)begin rx_hold<=0;ry_hold<=0;cx_hold<=640;cy_hold<=360;mode_hold<=1;contact_hold<=0;
  sel_hold<=0;count_hold<=0;error_hold<=0;tap_hold<=0;end
 else if(frame_tick)begin rx_hold<=raw_x;ry_hold<=raw_y;cx_hold<=cursor_x;cy_hold<=cursor_y;
  mode_hold<=mode_enabled;contact_hold<=contact;sel_hold<=selection;
  count_hold<=rx_count;error_hold<=error_count;tap_hold<=tap_count;end
end
function [7:0] hexchar;input [3:0] n;
 begin hexchar=n<10 ? 8'd48+{4'd0,n}:8'd55+{4'd0,n};end
endfunction
function [31:0] hexword;input [15:0] n;
 begin hexword={hexchar(n[15:12]),hexchar(n[11:8]),hexchar(n[7:4]),hexchar(n[3:0])};end
endfunction
// Five columns, seven rows, row zero at bit 34. Geometry is scaled 4x.
function [34:0] glyph;input [7:0] c;
 begin case(c)
  "0":glyph=35'b01110_10001_10011_10101_11001_10001_01110;
  "1":glyph=35'b00100_01100_00100_00100_00100_00100_01110;
  "2":glyph=35'b01110_10001_00001_00010_00100_01000_11111;
  "3":glyph=35'b11110_00001_00001_01110_00001_00001_11110;
  "4":glyph=35'b00010_00110_01010_10010_11111_00010_00010;
  "5":glyph=35'b11111_10000_10000_11110_00001_00001_11110;
  "6":glyph=35'b01110_10000_10000_11110_10001_10001_01110;
  "7":glyph=35'b11111_00001_00010_00100_01000_01000_01000;
  "8":glyph=35'b01110_10001_10001_01110_10001_10001_01110;
  "9":glyph=35'b01110_10001_10001_01111_00001_00001_01110;
  "A":glyph=35'b01110_10001_10001_11111_10001_10001_10001;
  "B":glyph=35'b11110_10001_10001_11110_10001_10001_11110;
  "C":glyph=35'b01111_10000_10000_10000_10000_10000_01111;
  "D":glyph=35'b11110_10001_10001_10001_10001_10001_11110;
  "E":glyph=35'b11111_10000_10000_11110_10000_10000_11111;
  "F":glyph=35'b11111_10000_10000_11110_10000_10000_10000;
  "G":glyph=35'b01111_10000_10000_10111_10001_10001_01111;
  "H":glyph=35'b10001_10001_10001_11111_10001_10001_10001;
  "I":glyph=35'b01110_00100_00100_00100_00100_00100_01110;
  "K":glyph=35'b10001_10010_10100_11000_10100_10010_10001;
  "L":glyph=35'b10000_10000_10000_10000_10000_10000_11111;
  "M":glyph=35'b10001_11011_10101_10101_10001_10001_10001;
  "N":glyph=35'b10001_11001_10101_10011_10001_10001_10001;
  "O":glyph=35'b01110_10001_10001_10001_10001_10001_01110;
  "P":glyph=35'b11110_10001_10001_11110_10000_10000_10000;
  "R":glyph=35'b11110_10001_10001_11110_10100_10010_10001;
  "S":glyph=35'b01111_10000_10000_01110_00001_00001_11110;
  "T":glyph=35'b11111_00100_00100_00100_00100_00100_00100;
  "U":glyph=35'b10001_10001_10001_10001_10001_10001_01110;
  "V":glyph=35'b10001_10001_10001_10001_10001_01010_00100;
  "W":glyph=35'b10001_10001_10001_10101_10101_11011_10001;
  "X":glyph=35'b10001_10001_01010_00100_01010_10001_10001;
  "Y":glyph=35'b10001_10001_01010_00100_00100_00100_00100;
  ":":glyph=35'b00000_00100_00100_00000_00100_00100_00000;
  default:glyph=0;
 endcase end
endfunction
reg [255:0] line;
reg [11:0] tx;reg [10:0] ty;
reg text_area;reg [23:0] background;
reg [11:0] dx;reg [10:0] dy;reg arrow,outline;
reg [7:0] character;
always @* begin
 line=0;tx=0;ty=0;text_area=0;
 background=(x[6]^y[6]) ? 24'h142132:24'h18283a;
 if(y>=400 && y<528)begin
  if(x>=128 && x<416)background=sel_hold==1 ? 24'heb5050:24'h782c38;
  if(x>=496 && x<784)background=sel_hold==2 ? 24'h50db80:24'h245c48;
  if(x>=864 && x<1152)background=sel_hold==3 ? 24'h509ceb:24'h294b78;
 end
 if(x>=496 && x<784 && y>=592 && y<656)background=24'h52627a;
 // Highlight the button underneath the pointer using a white upper edge.
 if(y>=400 && y<404 && cy_hold>=400 && cy_hold<528 &&
   ((x>=128 && x<416 && cx_hold>=128 && cx_hold<416) ||
    (x>=496 && x<784 && cx_hold>=496 && cx_hold<784) ||
    (x>=864 && x<1152 && cx_hold>=864 && cx_hold<1152)))background=24'hebebeb;
 if(x>=64 && x<1088 && y>=32 && y<352)begin
  tx=x-64;ty=y-32;text_area=ty[5:0]<28;
  case(ty[8:6])
   0:line="SINGLE BOARD TOUCHPAD TEST      ";
   1:line={"RAW X:",hexword({6'd0,rx_hold})," Y:",hexword({7'd0,ry_hold})," DOWN:",contact_hold?"1":"0","        "};
   2:line={"CUR X:",hexword({5'd0,cx_hold})," Y:",hexword({6'd0,cy_hold})," MODE:",mode_hold?"1":"0","        "};
   3:line={"RX:",hexword(count_hold)," ERR:",hexword(error_hold)," TAP:",hexword(tap_hold),"       "};
   4:line="SLIDE MOVE  TAP SELECT  HEX DATA";
   default:line=0;
  endcase
 end else if(y>=448 && y<476)begin
  if(x>=224 && x<320)begin tx=x-224;ty=y-448;text_area=1;line="RED                             ";end
  else if(x>=560 && x<720)begin tx=x-560;ty=y-448;text_area=1;line="GREEN                           ";end
  else if(x>=944 && x<1072)begin tx=x-944;ty=y-448;text_area=1;line="BLUE                            ";end
 end else if(x>=560 && x<720 && y>=608 && y<636)begin
  tx=x-560;ty=y-608;text_area=1;line="CLEAR                           ";
 end
 character=(line >> ((31-tx[9:5])*8));
 dx=x-{1'b0,cursor_x};dy=y-{1'b0,cursor_y};
 arrow=mode_hold && de && x>={1'b0,cursor_x} && y>={1'b0,cursor_y} && dx<16 && dy<24 && ({1'b0,dx}<<1)<=({2'b00,dy}+2);
 outline=dx<2 || dy>21 || ({1'b0,dx}<<1)>={2'b00,dy};
end
reg [7:0] char_s1;reg [2:0] gx_s1,gy_s1;
reg text_s1,de_s1,arrow_s1,outline_s1;
reg [23:0] bg_s1;
wire [34:0] bits=glyph(char_s1);
wire ink=text_s1 && gx_s1<5 && gy_s1<7 && bits[34-(gy_s1*5+gx_s1)];
always @(posedge clk or posedge rst)begin
 if(rst)begin char_s1<=0;gx_s1<=0;gy_s1<=0;text_s1<=0;de_s1<=0;arrow_s1<=0;outline_s1<=0;bg_s1<=0;rgb<=0;end
 else begin
  char_s1<=character;gx_s1<=tx[4:2];gy_s1<=ty[4:2];text_s1<=text_area;
  de_s1<=de;arrow_s1<=arrow;outline_s1<=outline;bg_s1<=background;
  rgb<=!de_s1 ? 24'h101010:arrow_s1 ? (outline_s1?24'h101010:24'hebebeb):ink ? 24'hebebeb:bg_s1;
 end
end
endmodule
