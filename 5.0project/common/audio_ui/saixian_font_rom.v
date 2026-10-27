// 128 glyphs x 16 rows x 16 bits, stored in one EG4 32K block RAM.
module saixian_font_rom #(parameter TITLE_SD=0)(
    input word_valid,input [6:0] word_index,input [31:0] word_data,input [4:0] word_length,
    input rst,frame_tick,output reg [4:0] title_length,
    input  wire        clk,
    input  wire [6:0]  glyph_id,
    input  wire [3:0]  row,
    output wire [15:0] bits
);

wire [10:0] font_addr = {glyph_id, row};
reg pending,complete,invalid;reg [6:0] low_index;reg [15:0] low_bits;
reg [4:0] candidate_length;
wire font_we=TITLE_SD && (word_valid || pending);
// Glyphs 96..111 form an aligned 256-row bank; no address adders.
wire [10:0] font_wa={3'b110,(pending ? low_index:word_index),pending};
wire [15:0] font_wd=pending ? low_bits:word_data[31:16];
always @(posedge clk or posedge rst)begin
 if(rst)begin pending<=0;complete<=0;invalid<=0;low_index<=0;low_bits<=0;candidate_length<=0;title_length<=0;end
 else if(TITLE_SD)begin
  pending<=word_valid;
  if(word_valid)begin
   low_index<=word_index;low_bits<=word_data[15:0];
   if(word_index==0)begin title_length<=0;candidate_length<=word_length;invalid<=0;complete<=0;end
   else if(word_length!=candidate_length)invalid<=1;
  end
  if(pending && low_index==127 && !invalid)complete<=1;
  if(frame_tick && complete && !(word_valid && word_index==0))title_length<=candidate_length;
 end
end

EG_LOGIC_BRAM #(
    .DATA_WIDTH_A(16),
    .ADDR_WIDTH_A(11),
    .DATA_DEPTH_A(2048),
    .DATA_WIDTH_B(16),
    .ADDR_WIDTH_B(11),
    .DATA_DEPTH_B(2048),
    .BYTE_ENABLE(0),
    .MODE(TITLE_SD ? "DP":"SP"),
    .REGMODE_A("NOREG"),
    .REGMODE_B("NOREG"),
    .WRITEMODE_A("NORMAL"),
    .WRITEMODE_B("NORMAL"),
    .RESETMODE("SYNC"),
    .DEBUGGABLE("NO"),
    .PACKABLE("NO"),
    .FORCE_KEEP("OFF"),
    .INIT_FILE("saixian_font_rom.mif"),
    .FILL_ALL("NONE"),
    .IMPLEMENT("32K")
) u_font_bram (
    .doa(bits),
    .dob(),
    .dia(16'd0),
    .dib(font_wd),
    .cea(1'b1),
    .ocea(1'b0),
    .clka(clk),
    .wea(1'b0),
    .rsta(1'b0),
    .ceb(TITLE_SD!=0),
    .oceb(1'b0),
    .clkb(clk),
    .web(font_we),
    .rstb(1'b0),
    .bea(1'b0),
    .beb(1'b0),
    .addra(font_addr),
    .addrb(font_wa)
);

endmodule
