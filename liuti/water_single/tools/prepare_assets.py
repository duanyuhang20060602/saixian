from pathlib import Path
import argparse,hashlib,json,shutil,struct,datetime,re
from PIL import Image,ImageOps,ImageFilter
ROOT=Path(__file__).resolve().parents[1]

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--source',default=r'C:\Users\39742\Desktop')
    ap.add_argument('--music',default='BGM1.AUD');ap.add_argument('--music-only',action='store_true');args=ap.parse_args()
    source=Path(args.source);out=ROOT/'tf_assets';out.mkdir(exist_ok=True);manifest=[]
    if args.music_only:
        manifest=[entry for entry in json.loads((ROOT/'validation'/'assets.json').read_text(encoding='utf-8')) if not entry['output'].upper().endswith('.AUD')]
    for i in ([] if args.music_only else range(1,6)):
        p=source/f'{i:02}.bmp';im=Image.open(p).convert('RGB');original_size=im.size
        if im.width*720!=im.height*1280:
            frame=ImageOps.fit(im,(1280,720),method=Image.Resampling.LANCZOS).filter(ImageFilter.GaussianBlur(28))
            frame=Image.blend(frame,Image.new('RGB',(1280,720),(10,17,24)),.42)
            front=ImageOps.contain(im,(1280,720),Image.Resampling.LANCZOS)
            frame.paste(front,((1280-front.width)//2,(720-front.height)//2))
        else:frame=im.resize((1280,720),Image.Resampling.LANCZOS)
        dest=out/p.name;frame.save(dest,format='BMP')
        assert Image.open(dest).size==(1280,720)
        manifest.append(dict(source=str(p),source_size=original_size,source_sha256=hashlib.sha256(p.read_bytes()).hexdigest(),
                             output=dest.name,sha256=hashlib.sha256(dest.read_bytes()).hexdigest()))
    music=source/args.music;header=music.read_bytes()[:512];length,rate,bits,channels=struct.unpack_from('<IIHH',header,8)
    assert header[:8]==b'SXAUD001' and (rate,bits,channels)==(48000,16,2)
    assert length%4==0 and music.stat().st_size>=512+length
    # This folder is the generated TF material set. Preserve earlier generated
    # music on E: and leave exactly one AUD, since hardware plays the first hit.
    archive=Path(r'E:\Codex\Work\saixian_water_handoff_fix\previous_music')
    for previous in out.glob('*.AUD'):
        if previous.name!=music.name:
            archive.mkdir(parents=True,exist_ok=True)
            stamp=datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f')
            shutil.move(str(previous),str(archive/(stamp+'_'+previous.name)))
    shutil.copy2(music,out/music.name)
    assert (out/music.name).read_bytes()==music.read_bytes()
    top=ROOT/'rtl'/'top_water_single.v'
    text,n=re.subn(r"SELECTED_AUDIO_BYTES=32'd\d+",f"SELECTED_AUDIO_BYTES=32'd{length}",top.read_text(encoding='utf-8'))
    assert n==1,'Selected music parameter missing'
    if text!=top.read_text(encoding='utf-8'):top.write_text(text,encoding='utf-8')
    manifest.append(dict(source=str(music),output=music.name,sha256=hashlib.sha256(music.read_bytes()).hexdigest(),
                         sample_rate=rate,bits=bits,channels=channels,duration_seconds=length/(rate*4)))
    (ROOT/'validation'/'assets.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    print(out)

if __name__=='__main__':main()
