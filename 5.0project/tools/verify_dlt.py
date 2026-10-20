"""Validate the current trophy package without generating reports or archives."""
from pathlib import Path
import hashlib,json,struct,zlib
ROOT=Path(__file__).resolve().parents[1]
def verify():
    path=ROOT/'award_media/AWARD720.DLT';blob=path.read_bytes()
    manifest=json.loads(path.with_name('AWARD720_DLT.json').read_text(encoding='utf-8'))
    h=struct.unpack_from('<8s4H7I',blob)
    assert h[:6]==(b'SXDLT005',5,512,1280,720,1)
    assert h[6:10]==(len(blob),460800,1,32) and h[11]==2
    assert zlib.crc32(blob[512:])==h[10]
    offset,length,duration,frame_crc,stream_crc,source,r0,r1=struct.unpack_from('<8I',blob,512)
    assert offset>=384 and offset%128==0 and length>0 and (offset+length)*4<=len(blob)
    assert 0<duration<=500000000 and source==r0==r1==0
    stream=blob[offset*4:(offset+length)*4];assert zlib.crc32(stream)==stream_crc
    words=struct.unpack('<'+'I'*length,stream);result=[];i=0
    while i<len(words):
        kind,count=words[i]>>30,words[i]&0x3fffffff;i+=1
        assert kind in (1,2) and 0<count<=460800-len(result)
        if kind==1:result.extend(words[i:i+count]);i+=count
        else:result.extend([words[i]]*count);i+=1
    raw=struct.pack('<460800I',*result)
    assert len(result)==460800 and i==len(words) and zlib.crc32(raw)==frame_crc
    assert raw==path.with_name('base_tagged_rgb565.bin').read_bytes()
    frames,tail_offset,tail_words,magic,period=struct.unpack_from('<5I',blob,256)
    assert (frames,tail_words,magic,period)==(120,230400,0x53505835,6)
    assert tail_offset%128==0 and tail_offset>=offset+length and (tail_offset+tail_words)*4==len(blob)
    packed=struct.unpack_from('<230400I',blob,tail_offset*4);lights=[];end=8160
    for row in range(8160):
        pos=packed[row];assert pos==end and pos%4==0
        bitmap=packed[pos]|(packed[pos+1]<<32);assert bitmap>>40==0;pos+=2
        for col in range(40):
            if bitmap>>col&1:
                assert packed[pos]!=0;lights.append(packed[pos]);pos+=1
            else:lights.append(0)
        end=(pos+3)//4*4
        assert end<=230400 and all(v==0 for v in packed[pos:end])
    assert all(v==0 for v in packed[end:]) and end==manifest['sparse_used_words']
    assert hashlib.sha256(struct.pack('<326400I',*lights)).hexdigest()==manifest['raw_light_sha256']
    assert hashlib.sha256(blob).hexdigest()==manifest['sha256']
    assert hashlib.sha256(raw).hexdigest()==manifest['tagged_plate_sha256']
    print('PASS trophy v5 package: plate CRC, 8160 sparse rows, lossless field hash, padding and SHA256')
    return blob,raw
if __name__=='__main__':verify()
