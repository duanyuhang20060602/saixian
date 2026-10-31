from pathlib import Path
from PIL import Image
v=[int(x,16) for x in Path('5.0project/src/board_a/user_source/hdl_source/saixian_sprint_atlas.hex').read_text().split()]
def a(x,y):return (v[y*32+x//16]>>(30-2*(x%16)))&3
places={0:(413,0),1:(400,0),2:(431,0),3:(444,0),4:(431,84),5:(431,112),6:(444,84),7:(431,168),8:(444,56),9:(431,196),10:(426,0),11:(462,0)}
font={};words=[0]*512
for d,(x0,y0) in places.items():
 sw=13 if d<10 else 5 if d==10 else 20;tw=12 if d<10 else 4 if d==10 else 18
 im=Image.new('L',(sw,28));im.putdata([85*a(x0+x,y0+y) for y in range(28) for x in range(sw)])
 im=im.resize((tw,24),Image.Resampling.LANCZOS);pix=list(im.getdata());q=[min(3,(n+42)//85) for n in pix]
 font[d]=(tw,q)
 for y in range(24):
  for x in range(tw):
   symbol=d if x<16 else 12;col=x if x<16 else x-16
   words[symbol*32+y+2]|=q[y*tw+x]<<(30-2*col)
p=Path('5.0project/common');p.joinpath('rank_digits.mif').write_text('WIDTH=32;\nDEPTH=512;\nADDRESS_RADIX=HEX;\nDATA_RADIX=HEX;\nCONTENT BEGIN\n'+''.join(f'{i:X} : {w:08X};\n' for i,w in enumerate(words))+'END;\n',newline='\n');p.joinpath('rank_digits.hex').write_text(''.join(f'{w:08x}\n' for w in words),newline='\n')
# Independent expected alpha canvas: edited score 12.34 plus its Chinese unit.
canvas=[0]*(84*28)
for d,x0 in [(1,0),(2,12),(10,24),(3,28),(4,40),(11,56)]:
 w,q=font[d]
 for y in range(24):
  for x in range(w):canvas[(y+2)*84+x0+x]=q[y*w+x]
Path('5.0project/tests/rank_style_expected_score.hex').write_text(''.join(f'{x:x}\n' for x in canvas),newline='\n')
p=Path('5.0project/common/photo_rank_text.v');s=p.read_text();start=s.index('// Original score font,');end=s.index('wire [31:0] digit_word;',start)
s=s[:start]+'''// One size smaller; all rows share the same antialiased score and unit font.
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
'''+s[end:]
s=s.replace('read_x<score_start+60','read_x<score_start+84').replace('read_x<score_start+57',"read_x<score_start+74 && (score_x<52 || score_x>=56)");p.write_text(s,newline='\n')
p=Path('5.0project/tests/tb_rank_style.v');s=p.read_text().replace('reg [31:0] atlas[0:8191];','reg [31:0] atlas[0:8191];reg [1:0] expected_small[0:2351];')
s=s.replace('qx[7]<644','qx[7]<668').replace('qx[7]<641','qx[7]<668')
a=s.index('   if(virtual_x<13)');b=s.index('   expected_color=',a)
s=s[:a]+'''   reference_alpha=expected_small[row_offset*84+virtual_x];
'''+s[b:]
s=s.replace('$readmemh("tests/rank_style_update.hex",updates);','$readmemh("tests/rank_style_expected_score.hex",expected_small);$readmemh("tests/rank_style_update.hex",updates);')
s=s.replace('score_pixels!=1596','score_pixels!=2352').replace('original-font edited-score pixels','smaller antialiased score/unit pixels')
p.write_text(s,newline='\n')
p=Path('run_rank_style_test.py');s=p.read_text().replace("'tests/rank_style_update.hex',","'tests/rank_style_update.hex','tests/rank_style_expected_score.hex',");p.write_text(s,newline='\n')
