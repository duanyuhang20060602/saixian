"""Reproduce and verify the native9K digit-column map."""
from pathlib import Path
import argparse,re
ROOT=Path(__file__).resolve().parents[1];HDL=ROOT/'common/match'
def expected():
 words=[0]*1024
 for group,start,width in [(1,64,32),(2,104,32),(3,144,32),(4,464,32),(5,504,32),(6,544,32),(7,248,20),(8,272,20),(9,302,5),(10,320,20),(11,344,20)]:
  for x in range(width):assert words[start+x]==0;words[start+x]=(group<<5)|x
 return words
def verify():
 words=expected();hex_words=[int(v,16) for v in (HDL/'photo_match_columns.hex').read_text().split()]
 mif={int(a):int(v,16) for a,v in re.findall(r'(\d+)\s*:\s*([A-Fa-f0-9]+)\s*;',(HDL/'photo_match_columns.mif').read_text())}
 assert words==hex_words and mif==dict(enumerate(words)),'Digit-column map is stale'
if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('--write',action='store_true');a=ap.parse_args()
 if a.write:
  words=expected();(HDL/'photo_match_columns.hex').write_text(''.join(f'{v:03x}\n' for v in words))
  (HDL/'photo_match_columns.mif').write_text('WIDTH=9;\nDEPTH=1024;\nADDRESS_RADIX=UNS;\nDATA_RADIX=HEX;\nCONTENT BEGIN\n'+''.join(f'{i} : {v:03X};\n' for i,v in enumerate(words))+'END;\n')
 verify();print('PASS1024 native9K digit columns')
