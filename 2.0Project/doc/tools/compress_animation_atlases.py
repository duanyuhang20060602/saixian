"""Lossless word dictionaries for the existing animation atlases.

The canonical atlas hex files remain the independent comparison oracle.
One index read plus one dictionary read replaces one wide atlas read.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / 'src/user_source/hdl_source'

def mif(path, values, width):
    path.write_text(f'WIDTH={width};\nDEPTH={len(values)};\nADDRESS_RADIX=HEX;\nDATA_RADIX=HEX;\nCONTENT BEGIN\n'
                    + ''.join(f'{i:04X} : {v:0{(width+3)//4}X};\n' for i, v in enumerate(values))
                    + 'END;\n', encoding='ascii')

def generate():
    for name in ('saixian_victory_atlas', 'saixian_sprint_atlas'):
        words = [int(v, 16) for v in (ROOT / f'{name}.hex').read_text().split()]
        dictionary = list(dict.fromkeys(words))
        assert len(dictionary) <= 1024
        lookup = {word: i for i, word in enumerate(dictionary)}
        indices = [lookup[word] for word in words]
        assert [dictionary[i] for i in indices] == words
        padded = dictionary + [0] * (1024-len(dictionary))
        (ROOT / f'{name}_index.hex').write_text(''.join(f'{i:03x}\n' for i in indices), encoding='ascii')
        (ROOT / f'{name}_dict.hex').write_text(''.join(f'{v:08x}\n' for v in padded), encoding='ascii')
        # TD maps 32-bit logical ports to two 16-bit lanes. Pack in native
        # 16-bit words: two low bytes or eight high pairs, with no padding.
        low = [sum((indices[i+j] & 255) << (8*j) for j in range(2))
               for i in range(0,len(indices),2)]
        high = [sum((indices[i+j] >> 8) << (2*j) for j in range(8))
                for i in range(0,len(indices),8)]
        for suffix, values in (('index_lo',low),('index_hi',high)):
            (ROOT / f'{name}_{suffix}.hex').write_text(''.join(f'{v:04x}\n' for v in values),encoding='ascii')
            mif(ROOT / f'{name}_{suffix}.mif', values, 16)
        mif(ROOT / f'{name}_dict.mif', padded, 32)
        print(f'{name}: {len(words)} words, {len(dictionary)} unique; lossless dictionary verified')

if __name__ == '__main__':
    generate()
