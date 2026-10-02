"""Deterministic Q15 Hann/twiddle and nonempty logarithmic band tables."""
from pathlib import Path
import math

ROOT = Path(__file__).resolve().parents[2] / 'src/user_source/hdl_source'

def edges():
    result = [1]
    for i in range(1, 32):
        result.append(max(result[-1]+1, round(512 ** (i/32))))
    return result + [512]

def generate():
    def q15(x):
        return max(-32768, min(32767, round(x*32768))) & 65535
    tables = {
        'saixian_av_hann.hex': [q15(.5-.5*math.cos(2*math.pi*n/1024)) for n in range(1024)],
        'saixian_av_twiddle.hex': [(q15(math.cos(2*math.pi*n/1024)) << 16) | q15(-math.sin(2*math.pi*n/1024)) for n in range(512)],
    }
    for name, values in tables.items():
        width = 8 if 'twiddle' in name else 4
        (ROOT/name).write_text(''.join(f'{v:0{width}x}\n' for v in values), encoding='ascii')
        # Production ROMs use explicit 512x16 EG4 RAM9K blocks.
        for bank in range((len(values)+511)//512):
            for lane in range(2 if 'twiddle' in name else 1):
                words=[(v>>(16*lane))&65535 for v in values[bank*512:(bank+1)*512]]
                mif='WIDTH=16;\nDEPTH=512;\nADDRESS_RADIX=HEX;\nDATA_RADIX=HEX;\nCONTENT BEGIN\n'
                mif+=''.join(f'{i:03X} : {v:04X};\n' for i,v in enumerate(words))+'END;\n'
                (ROOT/f'{name}_{bank}_{lane}.mif').write_text(mif,encoding='ascii')
    e = edges()
    # Each band occupies [start,end); average energy uses Q15 reciprocal.
    values = [(e[i+1] << 16) | round(32768/(e[i+1]-e[i])) for i in range(32)]
    (ROOT/'saixian_av_bands.hex').write_text(''.join(f'{v:08x}\n' for v in values), encoding='ascii')
    # Add previously unused glyph slots, preserving all existing 0..86 glyphs.
    letters = {
        'F':['11111','10000','10000','11110','10000','10000','10000'],
        'T':['11111','00100','00100','00100','00100','00100','00100'],
        'W':['10001','10001','10001','10101','10101','10101','01010'],
        'A':['01110','10001','10001','11111','10001','10001','10001'],
        'V':['10001','10001','10001','10001','10001','01010','00100'],
        'L':['10000','10000','10000','10000','10000','10000','11111'],
        'R':['11110','10001','10001','11110','10100','10010','10001'],
        'H':['10001','10001','10001','11111','10001','10001','10001'],
        'z':['00000','00000','11111','00010','00100','01000','11111'],
        'k':['10000','10000','10010','10100','11000','10100','10010'],
        '-':['00000','00000','00000','11111','00000','00000','00000'],
        'd':['00001','00001','01101','10011','10001','10001','01111'],
        'B':['11110','10001','10001','11110','10001','10001','11110'],
        '+':['00000','00100','00100','11111','00100','00100','00000'],
    }
    font = ROOT/'saixian_font_rom.mif'
    import re
    text = font.read_text(encoding='ascii')
    text = re.sub(r'^([0-9A-F]{3}) : [0-9A-F]+;\n',
                  lambda m: '' if 87*16 <= int(m[1],16) < 101*16 else m[0], text, flags=re.M)
    rows=[]
    for glyph, pattern in enumerate(letters.values(), 87):
        for row,bits in enumerate(pattern):
            word=0
            for col,bit in enumerate(bits):
                if bit=='1': word |= 3 << (11-2*col)
            for dy in range(2): rows.append(f'{glyph*16+1+row*2+dy:03X} : {word:04X};\n')
    font.write_text(text.replace('END;', ''.join(rows)+'END;'), encoding='ascii')
    memory=[0]*2048
    for addr,value in re.findall(r'^([0-9A-F]{3}) : ([0-9A-F]+);',font.read_text(),re.M):
        memory[int(addr,16)]=int(value,16)
    (ROOT/'saixian_av_font.hex').write_text(''.join(f'{v:04x}\n' for v in memory),encoding='ascii')
    print('band edges:', e)

if __name__ == '__main__':
    generate()
