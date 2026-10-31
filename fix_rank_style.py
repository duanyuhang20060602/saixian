from pathlib import Path
from PIL import Image
import struct
r=Path('5.0project/common');v=[int(x,16) for x in Path('5.0project/src/board_a/user_source/hdl_source/saixian_sprint_atlas.hex').read_text().split()]
def alpha(x,y):return (v[y*32+x//16]>>(30-2*(x%16)))&3
# Extract the original proportional score glyphs, including their anti-aliasing.
locations={0:(413,0),1:(400,0),2:(431,0),3:(444,0),4:(431,84),5:(431,112),6:(444,84),7:(431,168),8:(444,56),9:(431,196),10:(426,0)}
words=[0]*512
for d,(x0,y0) in locations.items():
 for y in range(28):
  for x in range(13 if d<10 else 5):words[d*32+y]|=alpha(x0+x,y0+y)<<(30-2*x)
def mif(width,words):
 return f'WIDTH={width};\nDEPTH={len(words)};\nADDRESS_RADIX=HEX;\nDATA_RADIX=HEX;\nCONTENT BEGIN\n'+''.join(f'{i:X} : {w:0{width//4}X};\n' for i,w in enumerate(words))+'END;\n'
(r/'rank_digits.mif').write_text(mif(32,words),newline='\n');(r/'rank_digits.hex').write_text(''.join(f'{w:08x}\n' for w in words),newline='\n')
# The same 16x16 font is used for initial names and UART replacement names.
g=Path('../saixian-serial-title-20261031/GLYPHS.BIN').read_bytes();names=[0]*2048
for row in range(8):
 for c,ch in enumerate(f'选手{row+1:02d}'):
  b=ch.encode('gb2312');idx=b[0] if len(b)==1 else 128+(b[0]-161)*94+b[1]-161;at=(idx//8)*512+16+(idx%8)*32
  for y in range(16):names[(row*2)*128+c*16+y]=int.from_bytes(g[at+y*2:at+y*2+2],'big')
(r/'rank_names.mif').write_text(mif(16,names),newline='\n');(r/'rank_names.hex').write_text(''.join(f'{w:04x}\n' for w in names),newline='\n')
p=r/'photo_rank_text.v';s=p.read_text();s=s.replace('output reg custom,output ink);','output reg custom,output ink,output [1:0] alpha);')
s=s.replace("rank_view ? 12'd164:12'd384","rank_view ? 12'd268:12'd528").replace("rank_view ? 12'd496:12'd736","rank_view ? 12'd524:12'd784")
s=s.replace('wire [10:0] ra={read_entry,name_x[7:5],read_y[4:1]};',"wire [3:0] glyph_row=read_y[4:1]+4'd1;\nwire [10:0] ra={read_entry,name_x[7:5],glyph_row};")
s=s.replace('.RESETMODE("SYNC"),.IMPLEMENT("32K")) glyphs(','.RESETMODE("SYNC"),.INIT_FILE("rank_names.mif"),.IMPLEMENT("32K")) glyphs(')
s=s.replace('enabled<=0;','enabled<=255;')
s=s.replace('for(i=0;i<16;i=i+1)begin lengths[i]<=0;scores[i]<=0;end','for(i=0;i<16;i=i+1)begin lengths[i]<=4;scores[i]<=default_score(i/2);end')
idx=s.index('integer i;');s=s[:idx]+'''function [15:0] default_score;input [2:0] row;begin case(row)
+0:default_score=16'h1023;1:default_score=16'h1031;2:default_score=16'h1038;3:default_score=16'h1046;
+4:default_score=16'h1055;5:default_score=16'h1063;6:default_score=16'h1076;7:default_score=16'h1091;
+endcase end endfunction
+'''.replace('\n+','\n')+s[idx:]
a=s.index('function [34:0] numeral;');s=s[:a]+'''// Original score font, original proportional advances: 13,13,5,13,13.
+reg [3:0] digit;reg [4:0] digit_column;
+wire [15:0] score=scores[read_entry];
+always @*begin
+ if(score_x<13)begin digit=score[15:12];digit_column=score_x[4:0];end
+ else if(score_x<26)begin digit=score[11:8];digit_column=score_x-13;end
+ else if(score_x<31)begin digit=10;digit_column=score_x-26;end
+ else if(score_x<44)begin digit=score[7:4];digit_column=score_x-31;end
+ else begin digit=score[3:0];digit_column=score_x-44;end
+end
+wire [31:0] digit_word;
+wire [8:0] digit_address={digit,read_y[4:0]};
+EG_LOGIC_BRAM #(.DATA_WIDTH_A(32),.ADDR_WIDTH_A(9),.DATA_DEPTH_A(512),
+ .DATA_WIDTH_B(32),.ADDR_WIDTH_B(9),.DATA_DEPTH_B(512),.MODE("SP"),
+ .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),
+ .RESETMODE("SYNC"),.INIT_FILE("rank_digits.mif"),.IMPLEMENT("9K")) score_font(
+ .clka(clk),.rsta(1'b0),.cea(1'b1),.wea(1'b0),.ocea(1'b0),.bea(1'b0),.addra(digit_address),.dia(32'd0),.doa(digit_word),
+ .clkb(clk),.rstb(1'b0),.ceb(1'b0),.web(1'b0),.oceb(1'b0),.beb(1'b0),.addrb(9'd0),.dib(32'd0),.dob());
+reg name_region,score_region;reg [3:0] name_col;reg [4:0] score_bit;
+always @(posedge clk or posedge rst)begin
+ if(rst)begin custom<=0;name_region<=0;name_col<=0;score_region<=0;score_bit<=0;end
+ else begin
+  // Replace only editable columns. Rank, lane and seconds labels stay intact.
+  custom<=read_valid && enabled[read_row] && read_x>=name_start && read_x<score_start+60;
+  name_region<=name_y_valid && read_y<28 && read_x>=name_start && read_x<name_start+256 && {1'b0,name_x[7:5]}<lengths[read_entry];
+  name_col<=name_x[4:1];
+  score_region<=digit_y_valid && read_x>=score_start && read_x<score_start+57;
+  score_bit<=5'd30-{digit_column[3:0],1'b0};
+ end
+end
+wire [1:0] score_alpha=digit_word >> score_bit;
+assign alpha=name_region && name_bits[15-name_col] ? 2'd3:score_region ? score_alpha:2'd0;
+assign ink=|alpha;
+endmodule
+'''.replace('\n+','\n')
p.write_text(s,newline='\n')
p=r/'saixian_battle_result_fx_pipelined.v';s=p.read_text();s=s.replace('wire rank_custom,rank_custom_ink;','wire rank_custom,rank_custom_ink;wire [1:0] rank_custom_alpha;')
s=s.replace('.custom(rank_custom),.ink(rank_custom_ink));','.custom(rank_custom),.ink(rank_custom_ink),.alpha(rank_custom_alpha));')
s=s.replace('reg [1:0] custom_pipe,custom_ink_pipe;','reg [1:0] custom_pipe;reg [3:0] custom_alpha_pipe;')
s=s.replace('custom_ink_pipe<=0','custom_alpha_pipe<=0').replace('custom_ink_pipe<={custom_ink_pipe[0],rank_custom_ink}','custom_alpha_pipe<={custom_alpha_pipe[1:0],rank_custom_alpha}')
s=s.replace('{2{custom_ink_pipe[1]}}','custom_alpha_pipe[3:2]');p.write_text(s,newline='\n')
print('Unified default/UART name font, restored fixed columns, original score anti-aliasing')
