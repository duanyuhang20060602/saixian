"""Validate the unmodified single-board package; no material conversion."""
from pathlib import Path
import hashlib,json,struct,zlib
ROOT=Path(__file__).resolve().parents[1]

def verify():
    blob=(ROOT/'award_media/AWARD720.DLT').read_bytes()
    h=struct.unpack_from('<8s4H7I',blob)
    assert h[:6]==(b'SXDLT003',3,512,1280,720,1)
    assert h[6:10]==(len(blob),460800,1,32) and h[11]==2
    assert zlib.crc32(blob[512:])==h[10]
    offset,length,duration,frame_crc,stream_crc,source,r0,r1=struct.unpack_from('<8I',blob,512)
    assert offset>=384 and offset%128==0 and length>0 and (offset+length)*4<=len(blob)
    assert duration>0 and duration<=500000000 and source==r0==r1==0
    stream=blob[offset*4:(offset+length)*4]
    assert zlib.crc32(stream)==stream_crc
    words=struct.unpack('<'+'I'*length,stream);result=[];i=0
    while i<len(words):
        cmd=words[i];i+=1;kind,count=cmd>>30,cmd&0x3fffffff
        assert kind in (1,2) and 0<count<=460800-len(result)
        if kind==1: result.extend(words[i:i+count]);i+=count
        else: result.extend([words[i]]*count);i+=1
    assert len(result)==460800 and i==len(words)
    raw=struct.pack('<460800I',*result)
    assert zlib.crc32(raw)==frame_crc
    assert raw==(ROOT/'award_media/base_tagged_rgb565.bin').read_bytes()
    report=dict(format='Original single-board SXDLT003; unchanged bytes',bytes=len(blob),
                sha256=hashlib.sha256(blob).hexdigest(),payload_crc32=f'{h[10]:08X}',
                bootstrap_stream_crc32=f'{stream_crc:08X}',decoded_frame_crc32=f'{frame_crc:08X}',
                tagged_plate_sha256=hashlib.sha256(raw).hexdigest(),exact_single_board_plate=True,
                resolution=[1280,720],descriptors=2,decoded_descriptor=0,
                animation='A-board procedural award_fx; not arbitrary multi-frame GIF playback')
    (ROOT/'award_media/AWARD720_DLT.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report,indent=2));return blob,raw

if __name__=='__main__':verify()
