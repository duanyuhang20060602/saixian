// 128 glyphs x 16 rows x 16 bits, stored in one EG4 32K block RAM.
module photo_menu_font #(parameter COMPACT=0)(
    input  wire        clk,
    input  wire [6:0]  glyph,
    input  wire [3:0]  row,
    input [6:0] edge_address,output [7:0] edge_weight,
    output wire [15:0] bits
);

localparam AW=COMPACT ? 10:11,DEPTH=COMPACT ? 1024:2048;
wire [AW-1:0] font_addr = {glyph,row};
wire [AW-1:0] edge_addr=10'd896+{4'd0,edge_address[6:1]};
wire [15:0] edge_word;reg edge_half;
always @(posedge clk)edge_half<=edge_address[0];
assign edge_weight=COMPACT ? (edge_half ? edge_word[7:0]:edge_word[15:8]):8'd0;

EG_LOGIC_BRAM #(
    .DATA_WIDTH_A(16),
    .ADDR_WIDTH_A(AW),
    .DATA_DEPTH_A(DEPTH),
    .DATA_WIDTH_B(16),
    .ADDR_WIDTH_B(AW),
    .DATA_DEPTH_B(DEPTH),
    .BYTE_ENABLE(0),
    .MODE(COMPACT ? "DP":"SP"),
    .REGMODE_A("NOREG"),
    .REGMODE_B("NOREG"),
    .WRITEMODE_A("NORMAL"),
    .WRITEMODE_B("NORMAL"),
    .RESETMODE("SYNC"),
    .DEBUGGABLE("NO"),
    .PACKABLE("NO"),
    .FORCE_KEEP("OFF"),
    .INIT_FILE(COMPACT ? "photo_compact_menu_font.mif":"photo_menu_font.mif"),
    .FILL_ALL("NONE"),
    .IMPLEMENT(COMPACT ? "9K":"32K")
) u_font_bram (
    .doa(bits),
    .dob(edge_word),
    .dia(16'd0),
    .dib(16'd0),
    .cea(1'b1),
    .ocea(1'b0),
    .clka(clk),
    .wea(1'b0),
    .rsta(1'b0),
    .ceb(COMPACT!=0),
    .oceb(1'b0),
    .clkb(clk),
    .web(1'b0),
    .rstb(1'b0),
    .bea(1'b0),
    .beb(1'b0),
    .addra(font_addr),
    .addrb(edge_addr)
);

endmodule
