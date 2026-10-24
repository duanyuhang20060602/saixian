"""Lossless 32-bit dictionary -> two-port 16-bit RAM32 initialization."""
from pathlib import Path
import argparse,hashlib

ROOT=Path(__file__).resolve().parents[1]

def prepare(project):
    for name in ['saixian_sprint_atlas','saixian_victory_atlas']:
        source=project/(name+'_dict.hex')
        words=[int(v,16) for v in source.read_text(encoding='utf-8').split()]
        assert len(words)==1024 and all(0<=v<2**32 for v in words)
        halves=[h for word in words for h in (word&65535,word>>16)]
        assert [halves[2*i]|(halves[2*i+1]<<16) for i in range(1024)]==words
        target=project/(name+'_dict_packed16.mif')
        target.write_text('WIDTH=16;\nDEPTH=2048;\nADDRESS_RADIX=HEX;\nDATA_RADIX=HEX;\nCONTENT BEGIN\n'+
                          ''.join(f'{i:X} : {v:04X};\n' for i,v in enumerate(halves))+'END;\n',encoding='utf-8')
        print(name, '1024 exact words; source SHA256',hashlib.sha256(source.read_bytes()).hexdigest(),
              'packed SHA256',hashlib.sha256(target.read_bytes()).hexdigest())

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--project',type=Path,default=ROOT/'src/board_a/user_source/hdl_source')
    prepare(parser.parse_args().project)
