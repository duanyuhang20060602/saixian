// Eight named results, two glyph banks per row, one 32K block in total.
module photo_rank_text(input clk,rst,frame_tick,
 input word_valid,input [2:0] word_row,input [5:0] word_index,input [31:0] word_data,
 input [3:0] word_length,input [15:0] word_score,
 input read_valid,rank_view,input [2:0] read_row,input [11:0] read_x,
 input [5:0] read_y,input name_y_valid,digit_y_valid,
 output reg custom,output ink,output [1:0] alpha);
reg [7:0] banks,complete,enabled;
reg [3:0] lengths[0:15];reg [15:0] scores[0:15];
reg low_pending;reg [10:0] low_address;reg [15:0] low_bits;reg [5:0] low_index;reg [3:0] low_length;
wire [3:0] write_entry={word_row,!banks[word_row]},read_entry={read_row,banks[read_row]};
wire [10:0] wa=word_valid ? {write_entry,word_index,1'b0}:low_address;
wire [15:0] wd=word_valid ? word_data[31:16]:low_bits;
wire [11:0] name_start=rank_view ? 12'd268:12'd528;
wire [11:0] name_x=read_x-name_start;
wire [11:0] score_start=rank_view ? 12'd524:12'd784;
wire [11:0] score_x=read_x-score_start;
// 24-pixel name cells, matching the score/unit 24-line font box.
// Keep every source glyph row; nearest-neighbour maps 24 pixels to 16.
function [3:0] small_coord;input [4:0] n;begin case(n)
0,1:small_coord=0;2:small_coord=1;3,4:small_coord=2;5:small_coord=3;
6,7:small_coord=4;8:small_coord=5;9,10:small_coord=6;11:small_coord=7;
12,13:small_coord=8;14:small_coord=9;15,16:small_coord=10;17:small_coord=11;
18,19:small_coord=12;20:small_coord=13;21,22:small_coord=14;23:small_coord=15;
default:small_coord=0;endcase end endfunction
reg [2:0] name_character;reg [4:0] name_local_x;
always @*begin
 if(name_x<24)begin name_character=0;name_local_x=name_x;end
 else if(name_x<48)begin name_character=1;name_local_x=name_x-24;end
 else if(name_x<72)begin name_character=2;name_local_x=name_x-48;end
 else if(name_x<96)begin name_character=3;name_local_x=name_x-72;end
 else if(name_x<120)begin name_character=4;name_local_x=name_x-96;end
 else if(name_x<144)begin name_character=5;name_local_x=name_x-120;end
 else if(name_x<168)begin name_character=6;name_local_x=name_x-144;end
 else begin name_character=7;name_local_x=name_x-168;end
end
wire [4:0] name_local_y=read_y-6'd2;
wire [3:0] glyph_row=small_coord(name_local_y);
wire [10:0] ra={read_entry,name_character,glyph_row};
wire [15:0] name_bits;
EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.ADDR_WIDTH_A(11),.DATA_DEPTH_A(2048),
 .DATA_WIDTH_B(16),.ADDR_WIDTH_B(11),.DATA_DEPTH_B(2048),.MODE("PDPW"),
 .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),
 .RESETMODE("SYNC"),.INIT_FILE("rank_names.mif"),.IMPLEMENT("32K")) glyphs(
 .clka(clk),.rsta(1'b0),.cea(1'b1),.wea(word_valid || low_pending),.ocea(1'b0),.bea(1'b0),
 .addra(wa),.dia(wd),.doa(),.clkb(clk),.rstb(1'b0),.ceb(1'b1),.web(1'b0),.oceb(1'b0),.beb(1'b0),
 .addrb(ra),.dib(16'd0),.dob(name_bits));
function [15:0] default_score;input [2:0] row;begin case(row)
0:default_score=16'h1023;1:default_score=16'h1031;2:default_score=16'h1038;3:default_score=16'h1046;
4:default_score=16'h1055;5:default_score=16'h1063;6:default_score=16'h1076;7:default_score=16'h1091;
endcase end endfunction
integer i;
always @(posedge clk or posedge rst)begin
 if(rst)begin
  banks<=0;complete<=0;enabled<=255;low_pending<=0;low_address<=0;low_bits<=0;low_index<=0;low_length<=0;
  for(i=0;i<16;i=i+1)begin lengths[i]<=4;scores[i]<=default_score(i/2);end
 end else begin
  low_pending<=word_valid;
  if(word_valid)begin
   low_address<={write_entry,word_index,1'b1};low_bits<=word_data[15:0];low_index<=word_index;low_length<=word_length;
   if(word_index==0)begin lengths[write_entry]<=word_length;scores[write_entry]<=word_score;complete[word_row]<=0;end
  end
  if(low_pending && ((low_length==0 && low_index==6'd7) ||
      (low_length!=0 && low_index==({low_length[2:0],3'd0}-6'd1))))complete[low_address[10:8]]<=1;
  if(frame_tick)for(i=0;i<8;i=i+1)
   if(complete[i] && !(word_valid && word_row==i && word_index==0))begin banks[i]<=~banks[i];enabled[i]<=1;complete[i]<=0;end
 end
end
// One size smaller; all rows share the same antialiased score and unit font.
reg [3:0] digit;reg [4:0] digit_column;
wire [15:0] score=scores[read_entry];
always @*begin
 if(score_x<12)begin digit=score[15:12];digit_column=score_x[4:0];end
 else if(score_x<24)begin digit=score[11:8];digit_column=score_x-12;end
 else if(score_x<28)begin digit=10;digit_column=score_x-24;end
 else if(score_x<40)begin digit=score[7:4];digit_column=score_x-28;end
 else if(score_x<52)begin digit=score[3:0];digit_column=score_x-40;end
 else if(score_x<72)begin digit=11;digit_column=score_x-56;end
 else begin digit=12;digit_column=score_x-72;end
end
wire [31:0] digit_word;
wire [8:0] digit_address={digit,read_y[4:0]};
EG_LOGIC_BRAM #(.DATA_WIDTH_A(32),.ADDR_WIDTH_A(9),.DATA_DEPTH_A(512),
 .DATA_WIDTH_B(32),.ADDR_WIDTH_B(9),.DATA_DEPTH_B(512),.MODE("SP"),
 .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),
 .RESETMODE("SYNC"),.INIT_FILE("rank_digits.mif"),.IMPLEMENT("9K")) score_font(
 .clka(clk),.rsta(1'b0),.cea(1'b1),.wea(1'b0),.ocea(1'b0),.bea(1'b0),.addra(digit_address),.dia(32'd0),.doa(digit_word),
 .clkb(clk),.rstb(1'b0),.ceb(1'b0),.web(1'b0),.oceb(1'b0),.beb(1'b0),.addrb(9'd0),.dib(32'd0),.dob());
reg name_region,score_region;reg [3:0] name_col;reg [4:0] score_bit;
always @(posedge clk or posedge rst)begin
 if(rst)begin custom<=0;name_region<=0;name_col<=0;score_region<=0;score_bit<=0;end
 else begin
  // Replace only editable columns. Rank, lane and seconds labels stay intact.
  custom<=read_valid && enabled[read_row] && read_x>=name_start && read_x<score_start+84;
  name_region<=name_y_valid && read_y>=2 && read_y<26 && read_x>=name_start && read_x<name_start+192 && {1'b0,name_character}<lengths[read_entry];
  name_col<=small_coord(name_local_x);
  score_region<=digit_y_valid && read_x>=score_start && read_x<score_start+74 && (score_x<52 || score_x>=56);
  score_bit<=5'd30-{digit_column[3:0],1'b0};
 end
end
wire [1:0] score_alpha=digit_word >> score_bit;
assign alpha=name_region && name_bits[15-name_col] ? 2'd3:score_region ? score_alpha:2'd0;
assign ink=|alpha;
endmodule
