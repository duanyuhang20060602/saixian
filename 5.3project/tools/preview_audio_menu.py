"""Render the menu's actual glyph ROM and layout, with audio repair selected."""
from pathlib import Path
import re
from PIL import Image,ImageDraw
R=Path(__file__).resolve().parents[1]
t=(R/'common/photo_settings_overlay.v').read_text(encoding='utf-8')
glyphs={}
for ident,body in re.findall(r'(?m)^\s*(\d+):case\(index\)(.*?)endcase',t,re.S):
 glyphs[int(ident)]={int(i):int(g) for i,g in re.findall(r'(\d+):text_glyph=7\'d(\d+);',body)}
rom=[0]*2048
for a,v in re.findall(r'(?m)^([0-9A-F]+)\s*:\s*([0-9A-F]+);',(R/'common/photo_menu_font.mif').read_text()):rom[int(a,16)]=int(v,16)
im=Image.new('RGB',(1280,720),(0,0,0));d=ImageDraw.Draw(im)
d.rectangle((64,80,863,623),fill='#142332')
def text(ident,x,y,scale=2,color='#ebebeb'):
 for index,g in glyphs[ident].items():
  for row in range(16):
   for col in range(16):
    if rom[g*16+row] & (1<<(15-col)):
     xx=x+index*16*scale+col*scale;yy=y+row*scale
     d.rectangle((xx,yy,xx+scale-1,yy+scale-1),fill=color)
text(0,96,96,color='#7de3ff');text(11,688,96,color='#7de3ff')
for i in range(13):
 y=144+32*i
 if i==12:d.rectangle((64,y,863,y+31),fill='#20405a')
 text({0:14,10:15,11:27,12:30}.get(i,i),96,y)
 if i in [5,6,9,12]:text(19 if i==12 else 18,608,y,color='#ffd166')
 elif i in [8,10,11]:text({8:20,10:16,11:28}[i],608,y,color='#ffd166')
 else:
  value={0:5,1:4,2:4,3:1,4:4,7:1}[i]
  width=value*({3:72,7:112}.get(i,28))
  d.rectangle((320,y+10,543,y+21),fill='#334456');d.rectangle((320,y+10,319+width,y+21),fill='#32b8d4')
  # Existing ROM digits are glyphs 35..43.
  glyphs[31]={0:35+value};text(31,608,y,color='#ffd166')
text(12,96,560,scale=1,color='#7de3ff');text(13,96,584,scale=1,color='#7de3ff')
(R/'delivery').mkdir(exist_ok=True)
im.save(R/'delivery/audio_repair_menu_preview.png')
print('Rendered actual menu font ROM and 13-row layout')
