"""Losslessly pack the edge ROM into the menu map's unused last 128 bytes."""
from pathlib import Path
import argparse,re
ROOT=Path(__file__).resolve().parents[1]
def expected(root=ROOT):
 text=[int(x,16) for x in (root/'src/board_a/user_source/hdl_source/photo_menu_text_lookup.hex').read_text().split()]
 assert len(text)==1024 and text[896:]==[0]*128,'Reserved menu addresses are no longer zero; revise packing before building'
 source=root/'src/board_a/user_source/hdl_source/IP/water_edge_weights.mif';words={}
 for a,b,s,v in re.findall(r'(?mi)^\s*(?:\[([0-9a-f]+)\.\.([0-9a-f]+)\]|([0-9a-f]+))\s*:\s*([0-9a-f]+);',source.read_text()):
  for i in range(int(a or s,16),int(b or s,16)+1):words[i]=int(v,16)
 assert set(words)==set(range(128)) and max(words.values())<=255
 values=text[:896]+[words[i] for i in range(128)]
 return (''.join(f'{v:02x}\n' for v in values),'WIDTH=8;\nDEPTH=1024;\nADDRESS_RADIX=HEX;\nDATA_RADIX=HEX;\nCONTENT BEGIN\n'+''.join(f'{i:03X} : {v:02X};\n' for i,v in enumerate(values))+'END;\n')
def verify(root=ROOT):
 stem=root/'src/board_a/user_source/hdl_source/photo_menu_edge_weights'
 for suffix,value in zip(['.hex','.mif'],expected(root)):assert stem.with_suffix(suffix).read_text()==value,'Packed menu/edge ROM is stale; run tools/prepare_menu_edge_rom.py'
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--check',action='store_true');args=ap.parse_args()
 if args.check:verify()
 else:
  stem=ROOT/'src/board_a/user_source/hdl_source/photo_menu_edge_weights'
  for suffix,value in zip(['.hex','.mif'],expected()):stem.with_suffix(suffix).write_text(value,encoding='utf-8')
  verify()
 print('PASS exact packed menu/edge ROM; reserved text bytes remain externally zero')
if __name__=='__main__':main()
