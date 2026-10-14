`timescale 1ns/1ps
// An opaque black panel with 2x 5x7 white lettering: SRC 1920x1080.
// Parallel mask pipelines match the existing video pipeline; no RGB delay.
module photo_resolution_overlay #(parameter VIDEO_DELAY=21)(
 input clk,rst,de,display_valid,input [11:0] x,input [10:0] y,
 input [15:0] source_width,source_height,input [23:0] rgb_in,
 output [15:0] width_bcd,height_bcd,output [23:0] rgb_out
);
reg [15:0] seen_width,seen_height,width_bits,height_bits;
reg [15:0] width_work,height_work,width_digits,height_digits;
assign width_bcd=width_digits;assign height_bcd=height_digits;
reg [4:0] steps;reg converting,digits_valid;
function [15:0] adjust;
 input [15:0] value;integer i;reg [15:0] result;
 begin result=value;for(i=0;i<4;i=i+1)
  if(value[i*4+:4]>=5)result[i*4+:4]=value[i*4+:4]+4'd3;
  adjust=result;
 end
endfunction
wire [15:0] width_adjusted=adjust(width_work),height_adjusted=adjust(height_work);
wire [15:0] width_shift={width_adjusted[14:0],width_bits[15]};
wire [15:0] height_shift={height_adjusted[14:0],height_bits[15]};
always @(posedge clk or posedge rst)begin
 if(rst)begin
  seen_width<=0;seen_height<=0;width_bits<=0;height_bits<=0;
  width_work<=0;height_work<=0;width_digits<=0;height_digits<=0;
  steps<=0;converting<=0;digits_valid<=0;
 end else if(source_width!=seen_width || source_height!=seen_height)begin
  seen_width<=source_width;seen_height<=source_height;
  width_bits<=source_width;height_bits<=source_height;width_work<=0;height_work<=0;
  steps<=0;converting<=1;digits_valid<=0;
 end else if(converting)begin
  width_work<=width_shift;height_work<=height_shift;
  width_bits<=width_bits<<1;height_bits<=height_bits<<1;
  if(steps==15)begin
   width_digits<=width_shift;height_digits<=height_shift;converting<=0;
   digits_valid<=seen_width!=0 && seen_height!=0;
  end else steps<=steps+1'b1;
 end
end
function [34:0] font;
 input [7:0] ch;
 begin case(ch)
  "0":font={5'b01110,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b01110};
  "1":font={5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
  "2":font={5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b01000,5'b11111};
  "3":font={5'b11110,5'b00001,5'b00001,5'b01110,5'b00001,5'b00001,5'b11110};
  "4":font={5'b00010,5'b00110,5'b01010,5'b10010,5'b11111,5'b00010,5'b00010};
  "5":font={5'b11111,5'b10000,5'b10000,5'b11110,5'b00001,5'b00001,5'b11110};
  "6":font={5'b01110,5'b10000,5'b10000,5'b11110,5'b10001,5'b10001,5'b01110};
  "7":font={5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b01000,5'b01000};
  "8":font={5'b01110,5'b10001,5'b10001,5'b01110,5'b10001,5'b10001,5'b01110};
  "9":font={5'b01110,5'b10001,5'b10001,5'b01111,5'b00001,5'b00001,5'b01110};
  "S":font={5'b01111,5'b10000,5'b10000,5'b01110,5'b00001,5'b00001,5'b11110};
  "R":font={5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001};
  "C":font={5'b01110,5'b10001,5'b10000,5'b10000,5'b10000,5'b10001,5'b01110};
  "x":font={5'b00000,5'b00000,5'b10001,5'b01010,5'b00100,5'b01010,5'b10001};
  default:font=0;
 endcase end
endfunction
wire [11:0] text_x=x-12'd20;
wire [10:0] text_y=y-11'd20;
wire [6:0] cell_x=text_x[7:1];
wire [3:0] char_index=cell_x/6;
wire [2:0] column=cell_x%6,row=text_y[3:1];
wire panel=de && display_valid && digits_valid && x>=16 && x<180 && y>=16 && y<38;
wire text_area=panel && x>=20 && x<176 && y>=20 && y<34;
reg [3:0] char_index_s1;
reg [2:0] column_s1,row_s1,column_s2,row_s2;
reg panel_s1,text_s1,panel_s2,text_s2;
reg [34:0] glyph_s2;
reg [7:0] character;
always @*begin
 character=" ";
 case(char_index_s1)
  0:character="S";1:character="R";2:character="C";
  4:character=width_digits[15:12]==0 ? " ":8'h30+width_digits[15:12];
  5:character=8'h30+width_digits[11:8];
  6:character=8'h30+width_digits[7:4];
  7:character=8'h30+width_digits[3:0];
  8:character="x";
  9:character=height_digits[15:12]==0 ? " ":8'h30+height_digits[15:12];
  10:character=8'h30+height_digits[11:8];
  11:character=8'h30+height_digits[7:4];
  12:character=8'h30+height_digits[3:0];
 endcase
end
wire ink=text_s2 && column_s2<5 && row_s2<7 && glyph_s2[34-row_s2*5-column_s2];
// Two early stages break coordinate -> divide -> glyph -> bit-select.
// The remaining stages keep total mask latency at VIDEO_DELAY clocks.
reg [VIDEO_DELAY-3:0] panel_pipe,ink_pipe;
always @(posedge clk or posedge rst)
 if(rst)begin
  char_index_s1<=0;column_s1<=0;row_s1<=0;column_s2<=0;row_s2<=0;
  panel_s1<=0;text_s1<=0;panel_s2<=0;text_s2<=0;glyph_s2<=0;
  panel_pipe<=0;ink_pipe<=0;
 end else begin
  char_index_s1<=char_index;column_s1<=column;row_s1<=row;
  panel_s1<=panel;text_s1<=text_area;
  glyph_s2<=font(character);column_s2<=column_s1;row_s2<=row_s1;
  panel_s2<=panel_s1;text_s2<=text_s1;
  panel_pipe<={panel_pipe[VIDEO_DELAY-4:0],panel_s2};
  ink_pipe<={ink_pipe[VIDEO_DELAY-4:0],ink};
 end
assign rgb_out=panel_pipe[VIDEO_DELAY-3] ? (ink_pipe[VIDEO_DELAY-3] ? 24'hffffff:24'h000000):rgb_in;
endmodule
