"""KEY2 sequencing, shared FIFO regression, and full TF player simulation."""
from pathlib import Path
import argparse, hashlib, json, os, re, shutil, struct, subprocess, zlib

ROOT=Path(__file__).resolve().parents[1]
HDL=ROOT/'src/user_source/hdl_source'
WORK=ROOT/'validation/key2_tf_20261010'
WORK.mkdir(parents=True,exist_ok=True)
BIN=Path('D:/qiansai/.tools/iverilog-portable/ucrt64/bin')
os.environ['PATH']=str(BIN)+os.pathsep+os.environ.get('PATH','')

def run(name,sources,args=(),defines=(),missing=False):
    target=WORK/f'{name}.vvp'
    cmd=[str(BIN/'iverilog.exe'),'-g2012','-s',name,'-I',str(HDL/'SD'),'-o',str(target)]
    if missing:cmd+=['-i']
    cmd+=[f'-D{x}' for x in defines]
    # Table-driven CRC is equivalent to the production bit-at-a-time function,
    # and avoids billions of interpreter operations in the full-media test.
    # Generated simulation sources never enter the TD source list.
    simulated=[]
    table=[]
    for byte in range(256):
        crc=byte
        for _ in range(8):crc=(crc>>1)^0xEDB88320 if crc&1 else crc>>1
        table.append(crc)
    for p in sources:
        source=p.read_text(encoding='utf-8')
        if name in ('tb_tf_integration','tb_tf_preload','tb_decoder') and re.search(r'function \[31:0\] crc_(word|byte);',source):
            initialization='reg [31:0] sim_crc_table [0:255];\ninitial begin\n'+''.join(f'sim_crc_table[{i}]=32\'h{x:08x};\n' for i,x in enumerate(table))+'end\n'
            def crc_function(match):
                kind=match.group(1)
                return initialization+f'''function [31:0] crc_{kind};
 input [31:0] old;input [{31 if kind=='word' else 7}:0] value;
 reg [31:0] c;integer n;
 begin c=old;for(n=0;n<{4 if kind=='word' else 1};n=n+1)
 c=(c>>8)^sim_crc_table[(c^(value>>(n*8)))&255];crc_{kind}=c;end
endfunction'''
            source=re.sub(r'function \[31:0\] crc_(word|byte);.*?endfunction',crc_function,source,flags=re.S)
            sim_path=WORK/('sim_'+p.name);sim_path.write_text(source,encoding='utf-8');simulated.append(sim_path)
        else:simulated.append(p)
    cmd+=[str(p) for p in simulated]
    compile_result=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True)
    (WORK/f'{name}_compile.log').write_text(compile_result.stdout+compile_result.stderr,encoding='utf-8')
    if compile_result.returncode:raise RuntimeError(compile_result.stderr)
    with (WORK/f'{name}.log').open('w',encoding='utf-8') as log:
        result=subprocess.run([str(BIN/'vvp.exe'),'-i',str(target),*args],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
    print((WORK/f'{name}.log').read_text(encoding='utf-8'),flush=True)
    if result.returncode:raise RuntimeError(f'{name} failed')

def prepare():
    blob=(ROOT/'examples/TF卡新增动图/TROPHY.DLT').read_bytes()
    magic,version,header,width,height,count,size,framewords,format_,entry,crc,descriptors=struct.unpack_from('<8s4H7I',blob)
    assert magic==b'SXDLT001' and size==len(blob) and width==height==480
    assert zlib.crc32(blob[512:])==crc and framewords==115200 and descriptors==count+1
    words=struct.unpack('<'+'I'*(len(blob)//4),blob)
    (WORK/'package_words.hex').write_text('\n'.join(f'{v:08x}' for v in words)+'\n',encoding='ascii')
    (WORK/'package_bytes.hex').write_text('\n'.join(f'{v:02x}' for v in blob)+'\n',encoding='ascii')
    frame=[0]*framewords
    for descriptor in range(descriptors):
        offset,n,duration,pixel_crc,stream_crc,source,_,_=struct.unpack_from('<8I',blob,512+descriptor*32)
        encoded=blob[offset*4:(offset+n)*4]
        assert zlib.crc32(encoded)==stream_crc
        commands=struct.unpack('<'+'I'*n,encoded);cursor=0;index=0
        while index<n:
            command=commands[index];index+=1;kind=command>>30;length=command&0x3fffffff
            assert kind<3 and 0<length<=framewords-cursor
            if kind==1:frame[cursor:cursor+length]=commands[index:index+length];index+=length
            elif kind==2:frame[cursor:cursor+length]=[commands[index]]*length;index+=1
            cursor+=length
        assert cursor==framewords and index==n
        assert zlib.crc32(struct.pack('<'+'I'*framewords,*frame))==pixel_crc
        (WORK/f'frame{descriptor}.hex').write_text('\n'.join(f'{v:08x}' for v in frame)+'\n',encoding='ascii')
    assert (WORK/'frame0.hex').read_bytes()==(WORK/f'frame{count}.hex').read_bytes()
    print(f'PASS asset: {count} original frames, all descriptor/decoded CRCs, exact loop closure, sha256={hashlib.sha256(blob).hexdigest()}',flush=True)
    return count

def fixture():
    folder=WORK/'integration_fixture';folder.mkdir(exist_ok=True)
    blob=bytearray(4096)
    colors=[0xF800001F,0xFFE007E0,0xF800001F]
    for i,color in enumerate(colors):
        raw=struct.pack('<II',0x80000000|115200,color)
        offset=384+i*128
        blob[offset*4:offset*4+len(raw)]=raw
        frame=struct.pack('<I',color)*115200
        struct.pack_into('<8I',blob,512+i*32,offset,2,1000000,zlib.crc32(frame),zlib.crc32(raw),i%2,0,0)
        (folder/f'frame{i}.hex').write_text((f'{color:08x}\n')*115200,encoding='ascii')
    struct.pack_into('<8s4H7I',blob,0,b'SXDLT001',1,512,480,480,2,len(blob),115200,1,32,zlib.crc32(blob[512:]),3)
    words=struct.unpack('<1024I',blob)
    (folder/'package_words.hex').write_text('\n'.join(f'{w:08x}' for w in words)+'\n',encoding='ascii')
    return folder

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--pipeline',action='store_true');parser.add_argument('--real-media',action='store_true');parser.add_argument('--commits',type=int,default=4);parser.add_argument('--work',type=Path);opts=parser.parse_args()
    if opts.work:
        WORK=(ROOT/opts.work).resolve();WORK.mkdir(parents=True,exist_ok=True)
    count=prepare()
    if not opts.pipeline:
        run('tb_static_bus_ownership',[ROOT/'tests/tb_static_bus_ownership.v',HDL/'SD/frame_fifo_read.v',HDL/'delta_memory.v'])
        run('tb_enhance_term_equivalence',[ROOT/'tests/tb_enhance_term_equivalence.v',HDL/'top_tf_hdmi_audio.v',ROOT/'tests/reference/key2_tf/baseline_enhance.v'])
        run('tb_scan_target_equivalence',[ROOT/'tests/tb_scan_target_equivalence.v',HDL/'SD/bmp_read.v',HDL/'SD/saixian_media_header.v'],missing=True)
        run('tb_fifo_full_equivalence',[ROOT/'tests/tb_fifo_full_equivalence.v',HDL/'IP/afifo_32_16_256.v'],missing=True)
        for name in ('tb_enhance','tb_enhance_detail','tb_enhance_numeric','tb_enhance_tap_range'):
            run(name,[ROOT/'tests'/f'{name}.v',HDL/'top_tf_hdmi_audio.v'])
        for name in ('tb_bmp_payload_limits','tb_audio_header_stream'):
            run(name,[ROOT/'tests'/f'{name}.v',HDL/'SD/bmp_read.v',HDL/'SD/saixian_media_header.v'],missing=True)
        run('tb_media_header',[ROOT/'tests/tb_media_header.v',HDL/'SD/saixian_media_header.v'])
        run('tb_medal_equivalence',[ROOT/'tests/tb_medal_equivalence.v',HDL/'saixian_battle_result_fx_pipelined.v'],defines=['VICTORY_SIM'])
        run('tb_cache_crc',[ROOT/'tests/tb_cache_crc.v',HDL/'delta_memory.v'])
        run('tb_scaler_equivalence',[ROOT/'tests/tb_scaler_equivalence.v',HDL/'SD/bmp_read.v',ROOT/'tests/reference/key2_tf/baseline_load_scaler.v'],missing=True)
        run('tb_preload_controls',[ROOT/'tests/tb_preload_controls.v',HDL/'saixian_battle_result_fx_pipelined.v'],defines=['VICTORY_SIM'])
        run('tb_photo_retention',[ROOT/'tests/tb_photo_retention.v',HDL/'SD/sd_card_bmp.v'],missing=True)
        run('tb_loader_hint',[ROOT/'tests/tb_loader_hint.v',HDL/'delta_loader.v'])
        run('tb_preload_lifecycle',[ROOT/'tests/tb_preload_lifecycle.v',HDL/'saixian_tf_preload.v'],missing=True)
        run('tb_video_handoff',[ROOT/'tests/tb_video_handoff.v',HDL/'top_tf_hdmi_audio.v'],missing=True)
        run('tb_descriptor_bounds',[ROOT/'tests/tb_descriptor_bounds.v',ROOT/'tests/reference/key2_tf/baseline_delta_player.v',HDL/'delta_player.v',HDL/'delta_decoder.v'])
        header_file=WORK/'actual_header.hex'
        header_file.write_text(''.join(f'{b:02x}\n' for b in (ROOT/'examples/TF卡新增动图/TROPHY.DLT').read_bytes()[:44]))
        run('tb_loader_header',[ROOT/'tests/tb_loader_header.v',ROOT/'tests/reference/key2_tf/baseline_delta_loader.v',HDL/'delta_loader.v'],args=[f'+HEADER={header_file.as_posix()}'])
        run('tb_repair_equivalence',[ROOT/'tests/tb_repair_equivalence.v',ROOT/'tests/reference/key2_tf/baseline_audio_repair.v',HDL/'saixian_audio_repair.v'],defines=['VICTORY_SIM'])
        run('tb_crc_network',[ROOT/'tests/tb_crc_network.v',HDL/'delta_memory.v',HDL/'delta_player.v',HDL/'delta_decoder.v'])
        run('tb_loading_policy',[ROOT/'tests/tb_loading_policy.v',HDL/'top_tf_hdmi_audio.v'],missing=True)
        run('tb_volume_boost',[ROOT/'tests/tb_volume_boost.v',HDL/'top_tf_hdmi_audio.v'])
        run('tb_audio_repair',[ROOT/'tests/tb_audio_repair.v',HDL/'saixian_audio_repair.v'],defines=['VICTORY_SIM'],args=['+GAP=318'])
        run('tb_audio_repair_controls',[ROOT/'tests/tb_audio_repair_controls.v',HDL/'top_tf_hdmi_audio.v'])
        font=[0]*2048
        for address,value in re.findall(r'(?m)^\s*([0-9A-Fa-f]{3})\s*:\s*([0-9A-Fa-f]{4})\s*;', (HDL/'saixian_font_rom.mif').read_text()):
            font[int(address,16)]=int(value,16)
        assert any(font[101*16:103*16]), 'missing repair glyphs'
        font_file=WORK/'font.hex';font_file.write_text(''.join(f'{value:04x}\n' for value in font))
        run('tb_audio_repair_osd',[ROOT/'tests/tb_audio_repair_osd.v',HDL/'saixian_osd_overlay.v'],args=[f'+FONT={font_file.as_posix()}'])
        run('tb_audio_repair_integration',[ROOT/'tests/tb_audio_repair_integration.v',HDL/'top_tf_hdmi_audio.v',HDL/'saixian_audio_repair.v'],defines=['VICTORY_SIM'],missing=True)
        run('tb_result_controls',[ROOT/'tests/tb_result_controls.v',HDL/'saixian_battle_result_fx_pipelined.v'],defines=['VICTORY_SIM'])
        run('tb_key2_short_long',[ROOT/'tests/tb_key2_short_long.v',HDL/'top_tf_hdmi_audio.v'])
        run('tb_key2_tf_flow',[ROOT/'tests/tb_key2_tf_flow.v',HDL/'top_tf_hdmi_audio.v',HDL/'saixian_battle_result_fx_pipelined.v'],defines=['VICTORY_SIM'])
        run('tb_shared_media_fifo',[ROOT/'tests/tb_shared_media_fifo.v',HDL/'SD/frame_read_write.v',HDL/'SD/frame_fifo_read.v',HDL/'SD/frame_fifo_write.v',HDL/'saixian_shared_video_fifo.v',HDL/'IP/afifo_16_32_256.v',HDL/'IP/afifo_32_16_256.v'])
        run('tb_stream_crc',[ROOT/'tests/tb_stream_crc.v',HDL/'delta_player.v',HDL/'delta_decoder.v'])
        run('tb_mapper_equivalence',[ROOT/'tests/tb_mapper_equivalence.v',ROOT/'tests/reference/key2_tf/baseline_mapper.v',HDL/'SD/frame_fifo_read.v'])
        run('tb_cue_equivalence',[ROOT/'tests/tb_cue_equivalence.v',ROOT/'tests/reference/key2_tf/baseline_cue.v',HDL/'saixian_audio_cue.v'])
        run('tb_decoder',[ROOT/'tests/tb_decoder.v',HDL/'delta_decoder.v'],args=[f'+package={(WORK/"package_words.hex").as_posix()}',f'+folder={WORK.as_posix()}'])
        run('tb_axis',[ROOT/'tests/tb_axis.v',HDL/'video_rgb_to_axis_640x480.v'])
        run('tb_first_hold',[ROOT/'tests/tb_first_hold.v',HDL/'delta_player.v',HDL/'delta_decoder.v'])
    else:
        folder=WORK if opts.real_media else fixture()
        commits=opts.commits if opts.real_media else 3
        size=472576 if opts.real_media else 1024
        run('tb_tf_integration',[ROOT/'tests/tb_tf_integration.v',HDL/'saixian_tf_animation.v',HDL/'delta_decoder.v',HDL/'delta_player.v',HDL/'delta_memory.v',HDL/'delta_loader.v',HDL/'delta_video.v',HDL/'delta_read_capture.v',HDL/'SD/frame_read_write.v',HDL/'SD/frame_fifo_read.v',HDL/'SD/frame_fifo_write.v',HDL/'saixian_shared_video_fifo.v',HDL/'IP/afifo_16_32_256.v'],
            args=[f'+package={(folder/"package_words.hex").as_posix()}',f'+folder={folder.as_posix()}',f'+commits={commits}',f'+package_words={size}'])
