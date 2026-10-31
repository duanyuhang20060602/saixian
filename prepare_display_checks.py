from pathlib import Path
import subprocess,re
r=Path('5.0project')
# Compare all original scene pixels to the published version when no row is edited.
s=subprocess.check_output(['git','show','HEAD:5.0project/common/saixian_battle_result_fx_pipelined.v']).decode();s=s[:s.index('endmodule')+len('endmodule')].replace('module saixian_battle_result_fx','module before_battle');(r/'tests/before_battle.v').write_text(s,newline='\n')
s=(r/'tests/tb_v4_battle_equivalence.v').read_text().replace('v4_port_ref_saixian_battle_result_fx','before_battle').replace('dut(.clk(clk)','dut(.rank_word_valid(1\'b0),.clk(clk)');(r/'tests/tb_preserved_battle.v').write_text(s,newline='\n')
# RAM model loads the actual generated configuration for the OSD font only.
s=(r/'tests/serial_title_ram_model.v').read_text().replace("initial for(i=0;i<2048;i=i+1)memory[i]=16'ha55a;","initial begin for(i=0;i<2048;i=i+1)memory[i]=16'ha55a; if(INIT_FILE==\"saixian_font_rom.mif\")$readmemh(\"default_font.hex\",memory);end")
(r/'tests/default_font_ram_model.v').write_text(s,newline='\n')
out=Path('validation-display');out.mkdir(exist_ok=True)
s=(r/'common/audio_ui/saixian_font_rom.mif').read_text();words={int(a,16):int(b,16) for a,b in re.findall(r'(?mi)^([0-9A-F]+)\s*:\s*([0-9A-F]+);',s)};assert len(words)==2048
(out/'default_font.hex').write_text(''.join(f'{words[i]:04x}\n' for i in range(2048)))
g=Path('../saixian-serial-title-20261031/GLYPHS.BIN').read_bytes();expected=[]
for bank,text in enumerate(['100米','欢迎来到运动会']):
 for n,c in enumerate(text):
  b=c.encode('gb2312');code=b[0] if len(b)==1 else 128+(b[0]-161)*94+b[1]-161;at=(code//8)*512+16+(code%8)*32
  for y in range(16):
   v=int.from_bytes(g[at+y*2:at+y*2+2],'big');assert words[1536+bank*256+n*16+y]==v;expected.append(v)
(out/'defaults_expected.hex').write_text(''.join(f'{x:04x}\n' for x in expected))
