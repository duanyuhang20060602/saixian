// 128 glyphs x 16 rows x 16 bits, stored in one EG4 32K block RAM.
module saixian_font_rom #(parameter TYPED_TEXT=0,TITLE_SD=0,INDEPENDENT_TEXT=0)(
    input[15:0] typed_mask,
    input word_valid,input [6+INDEPENDENT_TEXT:0] word_index,input [31:0] word_data,input [4:0] word_length,
    input rst,frame_tick,output reg [4:0] title_length,output reg [4:0] ticker_length,
    input  wire        clk,
    input  wire [6:0]  glyph_id,
    input  wire [3:0]  row,
    output wire [15:0] bits
);

reg pending,invalid;reg [1:0] complete;reg [6+INDEPENDENT_TEXT:0] low_index;reg [15:0] low_bits;
wire[15:0] raw_bits;reg[5:0] flash_phase;reg[15:0] flash_mask,candidate_mask;reg hidden;
assign bits=hidden ? 16'd0:raw_bits;
always @(posedge clk or posedge rst)begin
 if(rst)begin flash_phase<=0;flash_mask<=0;candidate_mask<=0;hidden<=0;end
 else begin
  if(frame_tick)begin flash_phase<=flash_phase+1'b1;if(complete[1])flash_mask<=candidate_mask;end
  if(TYPED_TEXT && word_valid && word_index==128)candidate_mask<=typed_mask;
  hidden<=TYPED_TEXT && glyph_id>=112 && flash_mask[glyph_id[3:0]] && flash_phase[5];
 end
end
wire [10:0] font_addr = {glyph_id, row};

reg [4:0] candidate_length,candidate_ticker_length;
wire word_bank=INDEPENDENT_TEXT && word_index[6+INDEPENDENT_TEXT];
wire low_bank=INDEPENDENT_TEXT && low_index[6+INDEPENDENT_TEXT];
wire font_we=TITLE_SD && (word_valid || pending);
// Glyphs 96..111 form an aligned 256-row bank; no address adders.
wire [7:0] extended_index=pending ? low_index:word_index;
wire [10:0] font_wa=INDEPENDENT_TEXT ? {2'b11,extended_index,pending}:{3'b110,(pending ? low_index[6:0]:word_index[6:0]),pending};
wire [15:0] font_wd=pending ? low_bits:word_data[31:16];
always @(posedge clk or posedge rst)begin
 if(rst)begin pending<=0;complete<=0;invalid<=0;low_index<=0;low_bits<=0;candidate_length<=0;candidate_ticker_length<=0;title_length<=0;ticker_length<=0;end
 else if(TITLE_SD)begin
  pending<=word_valid;
  if(word_valid)begin
   low_index<=word_index;low_bits<=word_data[15:0];
   if(word_index[6:0]==0)begin
    if(word_bank)begin ticker_length<=0;candidate_ticker_length<=word_length;end
    else begin title_length<=0;candidate_length<=word_length;end
    invalid<=(word_length==0 && !(TYPED_TEXT && word_bank)) || word_length>16;complete[word_bank]<=0;
   end else if(word_length!=(word_bank ? candidate_ticker_length:candidate_length))invalid<=1;
  end
  if(pending && low_index[6:0]==127 && !invalid)complete[low_bank]<=1;
  if(frame_tick)begin
   if(complete[0] && !(word_valid && word_index==0))title_length<=candidate_length;
   if(complete[1] && !(word_valid && word_index==128))ticker_length<=candidate_ticker_length;
  end
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
    .doa(raw_bits),
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
