"""Generate concise Chinese labels and pack their font with music edge weights.

49 glyphs use 784 16-bit rows. The 128 edge weights occupy 64 rows at 896,
so one dual-port 1024x16 ROM replaces the 2048x16 font and 1024x8 text map.
The pixel port and edge port keep their original single-cycle latency.
"""
from pathlib import Path
import argparse,json,re
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1]
LABELS={0:'设置',1:'亮度',2:'对比',3:'锐度',4:'饱和',5:'反色',6:'复古',7:'增强',
        8:'转场',9:'轮播',14:'音量',15:'音图',16:'频谱',17:'波形',18:'关',19:'开',
        20:'随机',30:'修复',35:'边光',37:'间隔',38:'同切'}
CHARS=' '+''.join(dict.fromkeys(''.join(LABELS.values())+'秒0123456789'))
def expected():
    assert len(CHARS)<=56
    font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',15)
    memory=[0]*1024
    for glyph,ch in enumerate(CHARS):
        if ch==' ':continue
        image=Image.new('L',(16,16));d=ImageDraw.Draw(image)
        l,t,r,b=d.textbbox((0,0),ch,font=font)
        d.text(((16-r+l)//2-l,(16-b+t)//2-t),ch,font=font,fill=255)
        for y in range(16):memory[glyph*16+y]=sum(1<<(15-x) for x in range(16) if image.getpixel((x,y))>=96)
    source=ROOT/'src/board_a/user_source/hdl_source/IP/water_edge_weights.mif'
    weights={}
    for lo,hi,a,v in re.findall(r'(?mi)^\s*(?:\[([0-9a-f]+)\.\.([0-9a-f]+)\]|([0-9a-f]+))\s*:\s*([0-9a-f]+);',source.read_text()):
        for i in range(int(lo or a,16),int(hi or a,16)+1):weights[i]=int(v,16)
    assert set(weights)==set(range(128))
    for i in range(64):memory[896+i]=weights[2*i]*256+weights[2*i+1]
    mif='WIDTH=16;\nDEPTH=1024;\nADDRESS_RADIX=HEX;\nDATA_RADIX=HEX;\nCONTENT BEGIN\n'+''.join(f'{i:03X} : {v:04X};\n' for i,v in enumerate(memory))+'END;\n'
    fn='function [6:0] compact_glyph;\n input [5:0] text_id;input [4:0] index;\n begin compact_glyph=0;case(text_id)\n'
    for i,label in LABELS.items():
        fn+=f'  {i}:case(index)\n'+''.join(f"   {n}:compact_glyph=7'd{CHARS.index(ch)};\n" for n,ch in enumerate(label))+'   default:compact_glyph=0;endcase\n'
    fn+='  default:compact_glyph=0;endcase end\nendfunction\n'
    return memory,mif,fn
def verify():
    _,mif,fn=expected()
    text=(ROOT/'common/photo_settings_overlay.v').read_text(encoding='utf-8')
    generated=f"localparam [6:0] COMPACT_DIGIT=7'd{CHARS.index('0')},COMPACT_SECOND=7'd{CHARS.index('秒')};\n"+fn
    assert (ROOT/'common/photo_compact_menu_font.mif').read_text()==mif, 'Compact menu font/edge table is stale'
    assert generated in text, 'Compact menu label decoder is stale'

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--check',action='store_true');a=ap.parse_args()
    memory,mif,fn=expected()
    p=ROOT/'common/photo_settings_overlay.v';text=p.read_text(encoding='utf-8')
    generated=f"localparam [6:0] COMPACT_DIGIT=7'd{CHARS.index('0')},COMPACT_SECOND=7'd{CHARS.index('秒')};\n"+fn
    if a.check:
        verify()
        return
    (ROOT/'common/photo_compact_menu_font.mif').write_text(mif,encoding='ascii')
    # The font basename is also staged in both saved TD directories.
    for board in ('a','b'):(ROOT/f'src/board_{board}/td_project/photo_compact_menu_font.mif').write_text(mif,encoding='ascii')
    if '// begin COMPACT_MENU_ASSETS' in text:
        text=re.sub(r'// begin COMPACT_MENU_ASSETS.*?// end COMPACT_MENU_ASSETS\n', '',text,flags=re.S)
    text=text.replace('function [6:0] text_glyph;', '// begin COMPACT_MENU_ASSETS\n'+generated+'// end COMPACT_MENU_ASSETS\nfunction [6:0] text_glyph;')
    if 'if(COMPACT_MENU)text_glyph' not in text:text=text.replace('begin text_glyph=0;case(text_id)','begin text_glyph=0;if(COMPACT_MENU)text_glyph=compact_glyph(text_id,index);else case(text_id)')
    p.write_text(text,encoding='utf-8',newline='\n')
    (ROOT/'sd_config/compact_menu_labels.json').write_text(json.dumps({'labels':LABELS,'glyphs':CHARS,'font_bits':len(memory)*16,'edge_rows':[896,959]},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(f'PASS compact font: {len(CHARS)} glyphs; font and edge weights total 16384 bits')
if __name__=='__main__':main()
