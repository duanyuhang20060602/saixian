// Boot/status lettering is independent of the SD font, so a missing card
// never looks like an HDMI failure. Pure combinational glyph/region decode.
module demo_diagnostics(input clk,input[11:0] x,input[10:0] y,input ready,fault,empty,input[1:0] slot,input[5:0] heartbeat,input initialized,input[2:0] sd_init_stage,input[15:0] rx_count,input[7:0] rx_last,input[15:0] good_count,error_count,input[3:0] fs_error,output reg active,output reg[23:0] color);
function[7:0] hex;input[3:0] n;begin hex=n<10?8'd48+n:8'd65+n-10;end endfunction
function[34:0] font;input[7:0] c;begin case(c)
"A":font=35'b01110_10001_10001_11111_10001_10001_10001;
"B":font=35'b11110_10001_10001_11110_10001_10001_11110;
"C":font=35'b01111_10000_10000_10000_10000_10000_01111;
"D":font=35'b11110_10001_10001_10001_10001_10001_11110;
"E":font=35'b11111_10000_10000_11110_10000_10000_11111;
"F":font=35'b11111_10000_10000_11110_10000_10000_10000;
"G":font=35'b01111_10000_10000_10111_10001_10001_01111;
"I":font=35'b11111_00100_00100_00100_00100_00100_11111;
"K":font=35'b10001_10010_10100_11000_10100_10010_10001;
"L":font=35'b10000_10000_10000_10000_10000_10000_11111;
"M":font=35'b10001_11011_10101_10101_10001_10001_10001;
"N":font=35'b10001_11001_10101_10011_10001_10001_10001;
"O":font=35'b01110_10001_10001_10001_10001_10001_01110;
"P":font=35'b11110_10001_10001_11110_10000_10000_10000;
"R":font=35'b11110_10001_10001_11110_10100_10010_10001;
"S":font=35'b01111_10000_10000_01110_00001_00001_11110;
"T":font=35'b11111_00100_00100_00100_00100_00100_00100;
"U":font=35'b10001_10001_10001_10001_10001_10001_01110;
"W":font=35'b10001_10001_10001_10101_10101_10101_01010;
"X":font=35'b10001_10001_01010_00100_01010_10001_10001;
"Y":font=35'b10001_10001_01010_00100_00100_00100_00100;
"0":font=35'b01110_10001_10011_10101_11001_10001_01110;
"1":font=35'b00100_01100_00100_00100_00100_00100_01110;
"2":font=35'b01110_10001_00001_00010_00100_01000_11111;
"3":font=35'b11110_00001_00001_01110_00001_00001_11110;
"4":font=35'b00010_00110_01010_10010_11111_00010_00010;
"5":font=35'b11111_10000_10000_11110_00001_00001_11110;
"6":font=35'b01110_10000_10000_11110_10001_10001_01110;
"7":font=35'b11111_00001_00010_00100_01000_01000_01000;
"8":font=35'b01110_10001_10001_01110_10001_10001_01110;
"9":font=35'b01110_10001_10001_01111_00001_00001_01110;
default:font=0;endcase end endfunction
reg[127:0] message;reg[11:0] lx;reg[10:0] ly;reg region;reg[7:0] letter;reg[34:0] bitmap;reg[5:0] bitpos;
reg base_active;reg[23:0] base_color;
reg region_q,base_q,fault_q;reg[7:0] letter_q;reg[2:0] row_q,col_q;reg[23:0] base_color_q;
wire[34:0] glyph=font(letter_q);wire[5:0] pixel_index=34-row_q*5-col_q;
always @(posedge clk)begin
 region_q<=region;letter_q<=letter;row_q<=ly[4:2];col_q<=lx[4:2];base_q<=base_active;base_color_q<=base_color;fault_q<=fault;
 active<=base_q || (region_q && col_q<5 && glyph[pixel_index]);
 color<=(region_q && col_q<5 && glyph[pixel_index])?(fault_q?24'hff6050:24'hf0e8c0):base_color_q;
end
always @*begin
 base_active=0;base_color=24'h304860;message=0;lx=0;ly=0;region=0;letter=32;bitmap=0;bitpos=0;
 if(x<8 || x>=1272 || y<8 || y>=712)begin base_active=1;base_color=24'h30c8e0;end
 if(y>=64 && y<92 && x>=64 && x<576)begin message="UART TEXT DEMO  ";lx=x-64;ly=y-64;region=1;end
 if(y>=128 && y<156 && x>=64 && x<576)begin
 if(fs_error!=0)message="FAT ERROR 0     ";else if(fault)message="FONT ERROR      ";else if(ready)message="FONT OK TYPE NOW";else if(initialized && sd_init_stage==4)message="READ FONT       ";else message="SD INIT 0       ";
 lx=x-64;ly=y-128;region=1;end
 if(y>=192 && y<220 && x>=64 && x<576)begin message="RX 0000 BYTE 00 ";lx=x-64;ly=y-192;region=1;end
 if(y>=240 && y<268 && x>=64 && x<576)begin message="OK 0000 ERR 0000";lx=x-64;ly=y-240;region=1;end
 if(empty && y>=300 && y<328 && x>=128 && x<640)begin message="WAITING FOR TEXT";lx=x-128;ly=y-300;region=1;end
 if(region)begin
 // Character cells are 32 pixels wide; letters occupy 20 pixels.
 letter=message>>(8*(15-lx[8:5]));
 if(y>=192 && y<220)case(lx[8:5])
 3:letter=hex(rx_count[15:12]);4:letter=hex(rx_count[11:8]);5:letter=hex(rx_count[7:4]);6:letter=hex(rx_count[3:0]);
 13:letter=hex(rx_last[7:4]);14:letter=hex(rx_last[3:0]);default:;endcase
 if(y>=240 && y<268)case(lx[8:5])
 3:letter=hex(good_count[15:12]);4:letter=hex(good_count[11:8]);5:letter=hex(good_count[7:4]);6:letter=hex(good_count[3:0]);
 12:letter=hex(error_count[15:12]);13:letter=hex(error_count[11:8]);14:letter=hex(error_count[7:4]);15:letter=hex(error_count[3:0]);default:;endcase
 if(y>=128 && y<156 && !ready && !fault && !(initialized && sd_init_stage==4) && lx[8:5]==8)letter=8'd48+sd_init_stage;
 if(y>=128 && y<156 && fs_error!=0 && lx[8:5]==10)letter=hex(fs_error);
 end
 if(y>=440 && y<468 && x>=128 && x<256)begin
 base_active=1;base_color=(x[6:5]==slot)?24'hffd166:24'h405870;
 end
 if(y>=600 && y<624 && x>=64 && x<1216)begin
 base_active=1;
 if(x<448)base_color=heartbeat[5]?24'he06050:24'ha04030;
 else if(x<832)base_color=24'h50b878;else base_color=24'h5088e0;
 end
end
endmodule
