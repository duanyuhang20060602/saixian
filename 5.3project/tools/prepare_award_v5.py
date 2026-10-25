"""Losslessly pack the accepted trophy plate and 120 spotlight fields for A/B."""
from pathlib import Path
import argparse,struct,zlib,hashlib,json
ROOT=Path(__file__).resolve().parents[1]
ACCEPTED='6ba3b06f56978615f436e680fd459e7113bceba6317dbe9fe1ab42d936358c27'
def digest(b):return hashlib.sha256(b).hexdigest()
def prepare(source,output):
    original=source.read_bytes()
    assert digest(original)==ACCEPTED,'Reference must be the accepted 3ac3c59 trophy asset'
    frames,table,map_words,magic,period=struct.unpack_from('<5I',original,256)
    assert (frames,map_words,magic,period)==(120,3600,0x53504f54,6)
    packed=[0]*8160;raw=[]
    for f in range(120):
        off,n,crc,sequence=struct.unpack_from('<4I',original,(table+f*4)*4)
        field=original[off*4:(off+n)*4]
        assert n==3600 and sequence==f and zlib.crc32(field)==crc
        for y in range(68):
            words=struct.unpack_from('<40I',field,y*160)
            bitmap=sum(int(v!=0)<<i for i,v in enumerate(words))
            packed[f*68+y]=len(packed)
            packed.extend([bitmap&0xffffffff,bitmap>>32])
            packed.extend(v for v in words if v)
            while len(packed)%4:packed.append(0)
            raw.extend(words)
    used=len(packed);assert used<=230400
    packed.extend([0]*(230400-used))
    offset,length,duration,frame_crc,stream_crc,*_=struct.unpack_from('<8I',original,512)
    stream=original[offset*4:(offset+length)*4];assert zlib.crc32(stream)==stream_crc
    words=struct.unpack('<'+'I'*length,stream);plate=[];i=0
    while i<len(words):
        kind,count=words[i]>>30,words[i]&0x3fffffff;i+=1
        assert kind in (1,2) and 0<count<=460800-len(plate)
        if kind==1:plate.extend(words[i:i+count]);i+=count
        else:plate.extend([words[i]]*count);i+=1
    plate_bytes=struct.pack('<460800I',*plate)
    assert zlib.crc32(plate_bytes)==frame_crc
    blob=bytearray(original[:((offset+length+127)//128)*512])
    tail_offset=len(blob)//4
    blob.extend(struct.pack('<230400I',*packed))
    blob[:8]=b'SXDLT005';struct.pack_into('<H',blob,8,5)
    struct.pack_into('<I',blob,20,len(blob))
    struct.pack_into('<5I',blob,256,120,tail_offset,230400,0x53505835,6)
    struct.pack_into('<I',blob,36,zlib.crc32(blob[512:]))
    # Independent expansion verifies every original field word, including zeros.
    restored=[]
    for row in range(8160):
        pos=packed[row];bitmap=packed[pos]|(packed[pos+1]<<32);pos+=2
        for col in range(40):
            restored.append(packed[pos] if bitmap>>col&1 else 0)
            pos+=int(bool(bitmap>>col&1))
    assert restored==raw
    output.parent.mkdir(parents=True,exist_ok=True);output.write_bytes(blob)
    manifest={'format':'SXDLT005','version':5,'reference_commit':'3ac3c59','reference_asset_sha256':ACCEPTED,
              'bytes':len(blob),'sha256':digest(blob),'resolution':[1280,720],'light_frames':120,
              'light_precision_bits':8,'cycle_display_frames':360,'light_rows':68,
              'light_raw_words':326400,'sparse_used_words':used,'tail_words':230400,
              'tail_offset':tail_offset,'transport_words':691200,'lossless':True,
              'raw_light_sha256':digest(struct.pack('<326400I',*raw)),
              'tagged_plate_sha256':digest(plate_bytes),'bootstrap_decoded_crc32':f'{frame_crc:08X}'}
    output.with_name('AWARD720_DLT.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    output.with_name('base_tagged_rgb565.bin').write_bytes(plate_bytes)
    return manifest
if __name__=='__main__':
    ap=argparse.ArgumentParser()
    ap.add_argument('--source',type=Path,default=ROOT/'tests/reference/accepted_v3/AWARD720.DLT')
    ap.add_argument('--output',type=Path,default=ROOT/'award_media/AWARD720.DLT')
    a=ap.parse_args();print(json.dumps(prepare(a.source,a.output),indent=2))
