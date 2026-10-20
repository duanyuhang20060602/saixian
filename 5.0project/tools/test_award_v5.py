"""Accepted-version visual, TF, link, cache, native LUT RAM and audio proofs."""
from pathlib import Path
import argparse,concurrent.futures,hashlib,json,os,re,shutil,struct,subprocess,time
import numpy as np
from prepare_award_v5 import prepare,ACCEPTED
ROOT=Path(__file__).resolve().parents[1]
GEOMETRY=['common/fluid/'+n for n in ['water_drop_small.v','water_reader.v','water_effect_map_base.v','water_priority_map.v','water_surface.v','water_blend.v','water_cache.v','water_reconstruct.v']]
FRAMEBUFFER=['src/board_a/user_source/hdl_source/'+n for n in ['SD/frame_read_write.v','SD/frame_fifo_read.v','SD/frame_fifo_write.v','IP/afifo_32_16_256.v','IP/afifo_16_32_256.v']]
JOBS={
 'reader':['tests/tb_award_v5_reader.v','common/photo_sd/photo_dlt_reader.v','common/photo_sd/photo_dlt_header.v','common/photo_color_format.v'],
 'rows':['tests/tb_award_v5_rows.v','common/photo_spotlight_player.v','common/photo_award_memory.v'],
 'visual':['tests/tb_award_v5_visual.v','tests/reference/award_v5/award_fx.v','common/award_fx.v','common/award_sprite_rom.v'],
 'link':['tests/tb_award_v5_link.v','common/photo_link.v'],
 'bus':['tests/tb_award_v5_bus.v','common/photo_spotlight_player.v','common/photo_award_memory.v',*GEOMETRY,*FRAMEBUFFER],
 'audio':['tests/tb_award_v5_audio.v','common/photo_audio_link.v','common/photo_audio_features.v','common/audio_ui/saixian_audio_repair.v','common/audio_ui/photo_audio_cue_samples.v']}
JOBS['control']=['tests/tb_award_v5_control.v','common/photo_cached_control_a.v','common/photo_control.v','common/photo_uart.v','common/photo_link.v']
JOBS['raster']=['tests/tb_award_v5_raster.v','common/photo_raster_delay.v']
JOBS['native_bus']=JOBS['bus']
JOBS['edge']=['tests/tb_award_v5_edge.v','tests/reference/award_v5/water_edge.v','common/fluid/water_edge.v']
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def hexwords(path,words,width=8):path.write_text('\n'.join(f'{int(v):0{width}x}' for v in words)+'\n',encoding='utf-8')
def vectors(out,reference):
    # Generate the expected packed package independently from the pinned donor.
    prepare(reference,out/'expected-AWARD720.DLT')
    assert (out/'expected-AWARD720.DLT').read_bytes()==(ROOT/'award_media/AWARD720.DLT').read_bytes()
    source=reference.read_bytes();table=struct.unpack_from('<I',source,260)[0];raw=[]
    for f in range(120):
        off,n,crc,seq=struct.unpack_from('<4I',source,(table+f*4)*4)
        raw.extend(struct.unpack_from('<2720I',source,off*4))
    package=(ROOT/'award_media/AWARD720.DLT').read_bytes();tail_offset=struct.unpack_from('<I',package,260)[0]
    tail=struct.unpack_from('<230400I',package,tail_offset*4)
    hexwords(out/'light_tail.hex',tail);hexwords(out/'light_raw.hex',raw)
    hexwords(out/'award_file.hex',struct.unpack('<'+'I'*(len(package)//4),package))
    plate=struct.unpack('<460800I',(out/'base_tagged_rgb565.bin').read_bytes())
    hexwords(out/'award_expected.hex',[((v&65535)<<16)|(v>>16) for v in plate]+list(tail))
    # Integer bilinear/temporal oracle; four distinct images cover five frames,
    # including the 119->0 seam and a paused frame. No RTL geometry is reused.
    fields=np.zeros((120,90,160),dtype=np.int32)
    fields[:,:68]=np.frombuffer(struct.pack('<326400I',*raw),dtype=np.uint8).reshape(120,68,160)
    x,y=np.meshgrid(np.arange(1280),np.arange(720))
    lx=np.minimum(np.maximum(0,x-4)//8,159);uy=np.minimum(np.maximum(0,y-4)//8,89)
    rx=np.minimum(lx+1,159);ly=np.minimum(uy+1,89)
    fx=np.where(x<4,0,(x-4)%8);fy=np.where(y<4,0,(y-4)%8)
    quant=((x%2)^(y%2))*128+(y%2)*64+(((x//2)%2)^((y//2)%2))*32+((y//2)%2)*16+8
    spatial_cache={}
    def spatial(f):
        if f not in spatial_cache:
            top=fields[f,uy,lx]*(8-fx)+fields[f,uy,rx]*fx
            bottom=fields[f,ly,lx]*(8-fx)+fields[f,ly,rx]*fx
            spatial_cache[f]=(top*(8-fy)+bottom*fy+quant//4)//64
        return spatial_cache[f]
    values=[]
    for f,step in [(119,0),(119,1),(119,2),(0,0)]:
        phase=(step*256+1)//3
        a=(spatial(f)*(256-phase)+spatial((f+1)%120)*phase+quant)//256
        a[y>=548]=0;values.append(a.astype(np.uint8).ravel())
    hexwords(out/'light_golden.hex',np.concatenate(values),2)
    for p in (ROOT/'common/fluid').glob('*.hex'):shutil.copy2(p,out/p.name)
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,default=Path('E:/Codex/Work/cooperate-award-v5-tests'))
    ap.add_argument('--reference',type=Path,default=ROOT/'tests/reference/accepted_v3/AWARD720.DLT')
    ap.add_argument('--only',nargs='+',choices=JOBS);ap.add_argument('--jobs',type=int,default=3);a=ap.parse_args()
    out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
    assert digest(a.reference)==ACCEPTED
    if not (out/'light_golden.hex').exists():vectors(out,a.reference)
    else:assert (out/'expected-AWARD720.DLT').read_bytes()==(ROOT/'award_media/AWARD720.DLT').read_bytes()
    vendor=Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_logic_dram.v')
    model=out/'vendor_logic_dram_functional.v';model.write_text(vendor.read_text().split('`pragma protect begin_protected',1)[0],encoding='utf-8')
    # Only the player's bottom-row simulation branch changes. Its native
    # EG_LOGIC_DRAM instances use the unmodified vendor functional model.
    fast=out/'photo_spotlight_player_fast.v'
    player=(ROOT/'common/photo_spotlight_player.v').read_text(encoding='utf-8')
    table={int(i):int(v) for i,v in re.findall(r"7'd(\d+):row_index=2'd(\d+);",player)}
    assert (table=={i:i%3 for i in range(128)}) if table else ('row_index' not in player), 'Unexpected address-index logic'
    fast.write_text(re.sub(r'function \[1:0\] row_index;.*?endfunction',
                          'function [1:0] row_index;input [6:0] row;begin row_index=row%3;end endfunction',player,count=1,flags=re.S),encoding='utf-8')
    native=out/'photo_spotlight_player_native.v'
    native.write_text((ROOT/'common/photo_spotlight_player.v').read_text().replace('`ifdef WATER_SIM','`ifdef AWARD_BOTTOM_FALLBACK'),encoding='utf-8')
    env=os.environ.copy();temp=Path('E:/Codex/Temp/cooperate-award-v5');temp.mkdir(parents=True,exist_ok=True)
    env.update(TEMP=str(temp),TMP=str(temp),TMPDIR=str(temp))
    selected=a.only or list(JOBS)
    fixtures={p.name:digest(p) for p in out.glob('*.hex')}
    common=[Path(__file__),ROOT/'tools/prepare_award_v5.py',ROOT/'award_media/AWARD720.DLT']
    def run(name):
        started=time.monotonic();files=[ROOT/p for p in JOBS[name]]
        hashes={p.relative_to(ROOT).as_posix():digest(p) for p in files+common}
        external={str(a.reference):digest(a.reference)}
        extra=['-DWATER_SIM','-DVICTORY_SIM','-DFX11_ROM_ROOT=""']
        top={'visual':'tb_award_v5_visual','audio':'tb_award_v5_audio'}.get(name,'tb')
        language='-g2012'
        if name=='bus':files=[fast if p.name=='photo_spotlight_player.v' else p for p in files]
        if name=='native_bus':
            files=[native if p.name=='photo_spotlight_player.v' else p for p in files]
            files.append(model);language='-g2005';extra+=['-P','tb.TEST_FRAMES=1','-P','tb.IMAGE_ROWS=720'];external[str(vendor)]=digest(vendor)
        binary=out/(name+'.vvp')
        p=subprocess.run(['C:/iverilog/bin/iverilog.exe',language,*extra,'-s',top,'-o',str(binary),*map(str,files)],cwd=out,env=env,capture_output=True,text=True)
        log=p.stdout+p.stderr
        if not p.returncode:
            p=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=out,env=env,capture_output=True,text=True,timeout=900);log+=p.stdout+p.stderr
        (out/(name+'.log')).write_text(log,encoding='utf-8')
        unchanged=all(digest(ROOT/f)==h for f,h in hashes.items()) and all(digest(Path(f))==h for f,h in external.items())
        passed=p.returncode==0 and 'PASS ' in log and not re.search(r'(?im)^(ERROR:|FATAL:)',log) and unchanged
        print(name+': '+next((s for s in log.splitlines() if s.startswith('PASS ')),log[-2500:]),flush=True)
        return dict(test=name,passed=passed,inputs_unchanged=unchanged,seconds=round(time.monotonic()-started,2),inputs_sha256=hashes,
                    external_inputs_sha256=external,stimuli_sha256=fixtures,log_sha256=digest(out/(name+'.log')))
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as pool:results=list(pool.map(run,selected))
    report=out/'results.json'
    previous=json.loads(report.read_text()) if report.exists() and a.only else []
    previous=[r for r in previous if r['test'] not in selected]
    report.write_text(json.dumps(previous+results,indent=2)+'\n',encoding='utf-8')
    if not all(r['passed'] for r in results):raise SystemExit('Award migration proof failed')
if __name__=='__main__':main()
