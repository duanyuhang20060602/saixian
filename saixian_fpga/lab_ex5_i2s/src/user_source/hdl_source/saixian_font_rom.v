// 128 glyphs x 16 rows x 16 bits, stored in one EG4 32K block RAM.
module saixian_font_rom(
    input  wire        clk,
    input  wire [6:0]  glyph_id,
    input  wire [3:0]  row,
    output wire [15:0] bits
);

wire [10:0] font_addr = {glyph_id, row};

EG_LOGIC_BRAM #(
    .DATA_WIDTH_A(16),
    .ADDR_WIDTH_A(11),
    .DATA_DEPTH_A(2048),
    .DATA_WIDTH_B(16),
    .ADDR_WIDTH_B(11),
    .DATA_DEPTH_B(2048),
    .BYTE_ENABLE(0),
    .MODE("SP"),
    .REGMODE_A("NOREG"),
    .REGMODE_B("NOREG"),
    .WRITEMODE_A("NORMAL"),
    .WRITEMODE_B("NORMAL"),
    .RESETMODE("SYNC"),
    .DEBUGGABLE("NO"),
    .PACKABLE("NO"),
    .FORCE_KEEP("OFF"),
    .INIT_FILE("../../user_source/hdl_source/saixian_font_rom.mif"),
    .FILL_ALL("NONE"),
    .IMPLEMENT("32K")
) u_font_bram (
    .doa(bits),
    .dob(),
    .dia(16'd0),
    .dib(16'd0),
    .cea(1'b1),
    .ocea(1'b0),
    .clka(clk),
    .wea(1'b0),
    .rsta(1'b0),
    .ceb(1'b0),
    .oceb(1'b0),
    .clkb(1'b0),
    .web(1'b0),
    .rstb(1'b0),
    .bea(1'b0),
    .beb(1'b0),
    .addra(font_addr),
    .addrb(11'd0)
);

endmodule
