from pathlib import Path
import sys,struct,zlib,json,hashlib,re
sys.stdout.reconfigure(encoding='utf-8')
root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root/'tools'))
from delta_codec import encode,decode
from resource_profile import HIGH_ROWS
def prepare():
    assets=root/'examples/TF卡素材'
    raw=(assets/'base_tagged_rgb565.bin').read_bytes()
    words=list(struct.unpack('<460800I',raw))
    streams=[encode(words),encode(words,words)]
    assert decode(streams[0],[0]*460800)==words
    table=bytearray(1024);payload=bytearray()
    for i,stream in enumerate(streams):
     struct.pack_into('<8I',table,i*32,(3+len(payload)//512)*128,len(stream)//4,300000000,zlib.crc32(raw),zlib.crc32(stream),0,0,0)
     payload+=stream;payload+=bytes((-len(stream))%512)
    maps=(assets/'spotlight_maps.bin').read_bytes()
    assert len(maps)==120*14400
    # The reduced on-chip light cache relies on protected rows being zero.
    assert all(not any(maps[i*14400+68*160:(i+1)*14400]) for i in range(120))
    for frame in range(120):
     for y,(base,first,count) in enumerate(HIGH_ROWS):
      for x in range(40):
       if not first<=x<first+count:
        assert all(v<128 for v in maps[frame*14400+y*160+x*4:frame*14400+y*160+x*4+4]), 'MSB profile requires recompilation'
    map_table_offset=(1536+len(payload))//4
    map_table=bytearray(2048);map_payload=bytearray()
    for i in range(120):
     m=maps[i*14400:(i+1)*14400]
     struct.pack_into('<4I',map_table,i*16,map_table_offset+512+len(map_payload)//4,3600,zlib.crc32(m),i)
     map_payload+=m;map_payload+=bytes((-len(m))%512)
    full_payload=table+payload+map_table+map_payload
    header=bytearray(512);total=512+len(full_payload)
    struct.pack_into('<8s4H7I',header,0,b'SXDLT004',4,512,1280,720,1,total,460800,1,32,zlib.crc32(full_payload),2)
    # The memory BIST uses header words 0..63 as scratch. Metadata lives at 64.
    struct.pack_into('<5I',header,256,120,map_table_offset,3600,0x53504f54,6)
    blob=bytes(header+full_payload)
    assert total+3686400<=8388608
    (assets/'AWARD720.DLT').write_bytes(blob)
    (assets/'spotlight_maps.bin').write_bytes(maps)
    report=dict(format='SXDLT004',base_image_frames=1,light_field_frames=120,light_field_size=[160,90],light_field_bytes_per_frame=14400,interpolation='Two temporal fields in external SDRAM; four rolling rows per field with spatial/temporal interpolation',display_frames_per_light_frame=6,loop_seconds_at_current_pixel_clock=120*6*1650*750/75000000,package_bytes=total,external_sdram_bytes=total+3686400,asset_sha256=hashlib.sha256(blob).hexdigest(),payload_crc32=f'{zlib.crc32(full_payload):08X}',preserved_effects=['trophy flow','wall breathing','curved twisting gold ribbons'],preview_scope='Software choreography reference; field sampling and RGB565 output require board comparison')
    report.update(onchip_light_rows=4,onchip_light_allocated_bytes=2048,onchip_light_meaningful_bytes=1280,interpolation_register_bytes=640,sprite_logical_size=[32,32],sprite_stored_size=[21,20],lossless_resource_storage=True,playback_speed_multiplier=2,effective_display_frames_per_light_frame=3,effective_loop_seconds=5.94,brightness_precision_bits=8)
    (assets/'manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    work=Path('E:/Codex/Temp/saixian_softflow720_tests');work.mkdir(parents=True,exist_ok=True)
    (work/'package_bytes.hex').write_text('\n'.join(f'{b:02x}' for b in blob)+'\n')
    (work/'package_words.hex').write_text('\n'.join(f'{v:08x}' for v in struct.unpack('<'+'I'*(len(blob)//4),blob))+'\n')
    for name in ('frame0.hex','frame1.hex'):(work/name).write_text('\n'.join(f'{v:08x}' for v in words)+'\n')
    print(json.dumps(report,ensure_ascii=False,indent=2));return blob

if __name__=="__main__": prepare()
