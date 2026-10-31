from pathlib import Path
import re
p=Path('5.0project/common/top_photo_a.v');s=p.read_text().replace('photo_boot_screen #(.VIDEO_DELAY','photo_boot_screen #(.BAR_ONLY(1),.VIDEO_DELAY').replace('saixian_font_rom #(.SERIAL_TEXT(1)','saixian_font_rom #(.DEFAULT_TEXT(1),.SERIAL_TEXT(1)');p.write_text(s,newline='\n')
p=Path('5.0project/common/photo_relief_remote.v');s=p.read_text().replace("{2'b00,specular7[7:1]}","{1'b0,specular7}").replace("{3'b000,specular7[7:2]}","{2'b00,specular7[7:1]}").replace("{4'b0000,specular7[7:3]}","{3'b000,specular7[7:2]}");p.write_text(s,newline='\n')
# Reuse the existing 32K OSD font's 32 dynamic glyph slots for defaults.
p=Path('5.0project/common/audio_ui/saixian_font_rom.mif');s=p.read_text();words=[0]*2048
for a,b,c,v in re.findall(r'(?mi)^\s*(?:\[([0-9A-F]+)\.\.([0-9A-F]+)\]|([0-9A-F]+))\s*:\s*([0-9A-F]+)\s*;',s):
 for i in range(int(a or c,16),int(b or c,16)+1):words[i]=int(v,16)
glyphs=Path('../saixian-serial-title-20261031/GLYPHS.BIN').read_bytes()
for bank,text in enumerate(['100米','欢迎来到运动会']):
 for n in range(16):
  bitmap=bytes(32)
  if n<len(text):
   code=text[n].encode('gb2312');idx=code[0] if len(code)==1 else 128+(code[0]-161)*94+code[1]-161
   start=(idx//8)*512+16+(idx%8)*32;bitmap=glyphs[start:start+32]
  for row in range(16):words[1536+bank*256+n*16+row]=int.from_bytes(bitmap[row*2:row*2+2],'big')
content='WIDTH=16;\nDEPTH=2048;\nADDRESS_RADIX=HEX;\nDATA_RADIX=HEX;\nCONTENT BEGIN\n'+''.join(f'{i:03X} : {v:04X};\n' for i,v in enumerate(words))+'END;\n'
for f in Path('5.0project').rglob('saixian_font_rom.mif'):f.write_text(content,newline='\n')
print('Default glyphs initialized in existing font RAM')
