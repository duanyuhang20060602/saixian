// Synchronous simulation of the unchanged production font ROM contents.
module photo_menu_font(input clk,input [6:0] glyph,input [3:0] row,output reg [15:0] bits);
reg [15:0] rom[0:2047];
initial $readmemh("tests/touchscreen_results/menu_font.hex",rom);
always @(posedge clk)bits<=rom[{glyph,row}];
endmodule
