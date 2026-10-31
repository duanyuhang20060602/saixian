from pathlib import Path
r=Path('5.0project');s=(r/'tests/serial_title_ram_model.v').read_text().replace("initial for(i=0;i<2048;i=i+1)memory[i]=16'ha55a;",'''initial begin
 for(i=0;i<2048;i=i+1)memory[i]=16'ha55a;
 if(INIT_FILE=="rank_names.mif")$readmemh("common/rank_names.hex",memory);
 if(INIT_FILE=="rank_digits.mif")$readmemh("common/rank_digits.hex",memory,0,511);
end''');(r/'tests/rank_style_ram_model.v').write_text(s,newline='\n')
g=Path('../saixian-serial-title-20261031/GLYPHS.BIN').read_bytes();words=[]
for ch in '张三':
 b=ch.encode('gb2312');idx=128+(b[0]-161)*94+b[1]-161;at=(idx//8)*512+16+(idx%8)*32
 for n in range(8):words.append(int.from_bytes(g[at+n*4:at+n*4+4],'big'))
(r/'tests/rank_style_update.hex').write_text(''.join(f'{w:08x}\n' for w in words),newline='\n')
