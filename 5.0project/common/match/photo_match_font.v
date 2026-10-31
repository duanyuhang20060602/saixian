// One32K dual-port ROM: A reads two packed character IDs from spare
// words1792..2047; B reads the selected16x16 bitmap one clock later.
module photo_match_font(input clk,input[8:0] text_address,input direct,input[6:0] direct_glyph,
 input[3:0] row,output[15:0] bits);
reg half,direct_q;reg[6:0] direct_glyph_q;reg[3:0] row_q;
wire[15:0] text_word;
wire[6:0] glyph=direct_q ? direct_glyph_q:half ? text_word[6:0]:text_word[14:8];
wire[10:0] text_row={3'b111,text_address[8:1]},bitmap_row={glyph,row_q};
always @(posedge clk)begin half<=text_address[0];direct_q<=direct;direct_glyph_q<=direct_glyph;row_q<=row;end
`ifdef MATCH_SIM
reg[15:0] font[0:2047];reg[15:0] text_q,bitmap_q;
initial $readmemh("photo_match_font.hex",font);
always @(posedge clk)begin text_q<=font[text_row];bitmap_q<=font[bitmap_row];end
assign text_word=text_q;assign bits=bitmap_q;
`else
EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.ADDR_WIDTH_A(11),.DATA_DEPTH_A(2048),
 .DATA_WIDTH_B(16),.ADDR_WIDTH_B(11),.DATA_DEPTH_B(2048),.MODE("DP"),
 .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),
 .RESETMODE("SYNC"),.IMPLEMENT("32K"),.INIT_FILE("photo_match_font.mif")) memory(
 .clka(clk),.cea(1'b1),.ocea(1'b1),.wea(1'b0),.rsta(1'b0),.dia(16'd0),.addra(text_row),.doa(text_word),.bea(1'b0),
 .clkb(clk),.ceb(1'b1),.oceb(1'b1),.web(1'b0),.rstb(1'b0),.dib(16'd0),.addrb(bitmap_row),.dob(bits),.beb(1'b0));
`endif
endmodule
