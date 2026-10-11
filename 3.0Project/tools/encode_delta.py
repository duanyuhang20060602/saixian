"""Encode the tagged 720p plate using the proven skip/literal/fill protocol."""
from pathlib import Path
import hashlib,json,struct,zlib
from delta_codec import encode,decode

ROOT=Path(__file__).resolve().parents[1]
WORK=Path('E:/Codex/Temp/saixian_softflow720_tests')
WIDTH,HEIGHT=1280,720
FRAME_WORDS=WIDTH*HEIGHT//2

def prepare():
    WORK.mkdir(parents=True,exist_ok=True)
    raw=(ROOT/'examples/TF卡素材/base_tagged_rgb565.bin').read_bytes()
    words=list(struct.unpack('<'+'I'*FRAME_WORDS,raw))
    streams=[encode(words),encode(words,words)]
    assert decode(streams[0],[0]*FRAME_WORDS)==words
    assert decode(streams[1],words)==words
    # Keep the proven two-sector index reservation: player validates >=384.
    table=bytearray(1024);payload=bytearray()
    for i,s in enumerate(streams):
        struct.pack_into('<8I',table,i*32,(3+len(payload)//512)*128,len(s)//4,
            300000000,zlib.crc32(raw),zlib.crc32(s),0,0,0)
        payload+=s;payload+=bytes((-len(s))%512)
    total=1536+len(payload);header=bytearray(512)
    struct.pack_into('<8s4H7I',header,0,b'SXDLT003',3,512,WIDTH,HEIGHT,
        1,total,FRAME_WORDS,1,32,zlib.crc32(table+payload),2)
    blob=bytes(header+table+payload)
    assert total+FRAME_WORDS*8<=8388608
    (ROOT/'examples/TF卡素材/AWARD720.DLT').write_bytes(blob)
    (WORK/'package_words.hex').write_text('\n'.join(f'{v:08x}' for v in struct.unpack('<'+'I'*(len(blob)//4),blob))+'\n')
    (WORK/'package_bytes.hex').write_text('\n'.join(f'{v:02x}' for v in blob)+'\n')
    frame='\n'.join(f'{v:08x}' for v in words)+'\n'
    (WORK/'frame0.hex').write_text(frame)
    (WORK/'frame1.hex').write_text(frame)
    report=dict(resolution=[WIDTH,HEIGHT],frame_words=FRAME_WORDS,package_words=len(blob)//4,
        package_bytes=len(blob),payload_crc32=f'{zlib.crc32(blob[512:]):08X}',
        package_sha256=hashlib.sha256(blob).hexdigest(),plate_sha256=hashlib.sha256(raw).hexdigest(),
        sdram_required_bytes=total+FRAME_WORDS*8,encoded_frame_bytes=list(map(len,streams)),
        static_plate_count=1,descriptors=2,live_effects=True,
        format='SXDLT003; flag in blue bit0, soft weight in blue bits4:1, wall lamp type in green bit0',
        preview_motion='Similar composition and live effects; not a frame-for-frame GIF decode')
    (ROOT/'examples/TF卡素材/manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report,indent=2));return blob

if __name__=='__main__':prepare()
