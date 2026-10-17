from pathlib import Path
import sys,random,subprocess,json,argparse,math,hashlib
from reference import warp,word,blend
from scaler_reference import resize
from concurrent.futures import ThreadPoolExecutor,as_completed
from photo_reference import WORK as PHOTO_WORK,prepare as prepare_photos
ROOT=Path(__file__).resolve().parents[1];TEST=ROOT/'tests';RTL=ROOT/'rtl'
IVER=r'C:\iverilog\bin\iverilog.exe';VVP=r'C:\iverilog\bin\vvp.exe'

def validation_suite(full):
    geometry=['water_math.v','water_reader.v','water_effect_map.v','water_extra_effect_map.v','water_blend.v','water_frame_mapper.v','water_cache.v','water_reconstruct.v','../tests/sdram_contract.v']
    adapter=geometry+['water_image_writer.v','../vendor/frame_read_write.v','../vendor/frame_fifo_write.v','../vendor/afifo_32_16_256.v','../vendor/afifo_16_32_256.v']
    decoder=['../vendor/bmp_read.v','../vendor/saixian_media_header.v']
    bandwidth=geometry+['water_expand.v','../vendor/afifo_32_16_256.v']
    suite=[('arithmetic',['water_math.v','water_effect_map.v','water_extra_effect_map.v','water_blend.v','water_edge.v']),('surface',['water_effect_map.v']),('cache',['water_cache.v']),('effects',['water_effect_map.v','water_extra_effect_map.v']),('math',['water_math.v']),('reader',geometry),('fx_reader',geometry),('frame',adapter),('expand',['water_expand.v']),('edge',['water_edge.v']),('scene',['water_scene.v']),('transition',['water_transition.v'])]+([('photos',geometry),('bandwidth_dwell',bandwidth),('bandwidth_native',bandwidth),('bandwidth',bandwidth),('bandwidth_metal',bandwidth),('bandwidth_tunnel',bandwidth),('blend',['water_blend.v']),('native',decoder),('scaler_pacing',decoder),('multires',decoder)] if full else [])
    return suite

def test_dependencies(name,files):
    bench='bandwidth' if name in ('bandwidth_dwell','bandwidth_native','bandwidth_metal','bandwidth_tunnel') else name
    deps={TEST/('tb_'+bench+'.v')}
    if name=='arithmetic':deps.update(TEST.glob('water_*.hex'))
    if name in ('effects','fx_reader','photos'):deps.add(ROOT/'tools/effects_reference.py')
    if name=='photos':
        deps.update([ROOT/'tools/photo_reference.py',PHOTO_WORK/'photo_data.hex',PHOTO_WORK/'photo_golden.hex',*sorted((ROOT/'tf_assets').glob('*.bmp'))])
    if name in ('math','reader','fx_reader','photos','frame','bandwidth','bandwidth_dwell','bandwidth_native','bandwidth_metal','bandwidth_tunnel'):
        deps.add(ROOT/'tools/reference.py')
        deps.update(TEST/x for x in ['water_sine.hex','water_wave.hex','water_inverse.hex'])
    if name in ('reader','fx_reader','photos','frame','bandwidth','bandwidth_dwell','bandwidth_native','bandwidth_metal','bandwidth_tunnel','effects'):
        deps.update(TEST/x for x in ['water_flip.hex','water_roll.hex','water_strip.hex','water_fx_recip.hex','water_fx_wave.hex'])
    if name=='edge':deps.add(TEST/'water_edge.hex')
    if name=='multires':deps.add(ROOT/'tools/scaler_reference.py')
    deps.update((RTL/f).resolve() for f in files)
    stimuli={'effects':['effects_vectors.txt'],'math':['math_vectors.txt'],'reader':['reader_vectors.txt'],'fx_reader':['fx_reader_vectors.txt'],'frame':['reader_vectors.txt'],'edge':['edge_vectors.txt'],
             'multires':['scaler_640_480.hex','scaler_1280_720.hex','scaler_1920_1080.hex'],
             'bandwidth':['frame_checksums.hex'],'bandwidth_dwell':['frame_checksums.hex'],'bandwidth_native':['frame_checksums.hex'],'bandwidth_metal':['frame_checksums.hex'],'bandwidth_tunnel':['frame_checksums.hex']}
    deps.update(TEST/f for f in stimuli.get(name,[]))
    return deps

def adopt_existing_results():
    # Preserve proven results across the change to per-test caching. Every HDL,
    # test bench, stimulus and reference model must predate its successful log.
    # Thereafter reuse requires exact hashes and an identical compiler command.
    path=ROOT/'validation/rtl_cache.json'
    if path.exists():return
    cache={}
    for name,files in validation_suite(True):
        log=ROOT/'validation'/(name+'_test.log');deps=test_dependencies(name,files)
        if not log.exists() or any(not p.exists() or p.stat().st_mtime>log.stat().st_mtime for p in deps):continue
        result=log.read_text(encoding='utf-8')
        if 'PASS ' not in result or 'FATAL:' in result or 'ERROR:' in result:continue
        bench='bandwidth' if name in ('bandwidth_dwell','bandwidth_native','bandwidth_metal','bandwidth_tunnel') else name
        extra=['-P','tb.TEST_MODE='+str({'bandwidth_dwell':0,'bandwidth_native':7,'bandwidth_metal':5,'bandwidth_tunnel':9}[name])] if name in ('bandwidth_dwell','bandwidth_native','bandwidth_metal','bandwidth_tunnel') else []
        command=[IVER,'-DWATER_SIM','-g2005' if name=='scene' else '-g2012','-s','tb',*extra,'-o',str(TEST/(name+'.vvp')),str(TEST/('tb_'+bench+'.v'))]+[str(RTL/f) for f in files]
        cache[name]=dict(inputs={str(p.resolve()):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(deps)},command=command,stdout=result,stderr='')
    path.write_text(json.dumps(cache,indent=2),encoding='utf-8')

def main():
    ap=argparse.ArgumentParser();ap.add_argument("--full",action="store_true");ap.add_argument('--jobs',type=int,default=3);args=ap.parse_args()
    assert args.jobs>0,'jobs must be positive'
    adopt_existing_results()
    rng=random.Random(76321)
    cases=[(0,0,0,0,998,346,454,432,0,0)]
    cases += [(1,p,0,0,0,0,0,0,0,0) for p in range(257)]
    cases += [(0,0,1,1,998,346,454,432,r,r+55) for r in [0,1,25,96,400,800,1050,1200]]
    cases += [(0,0,on0,on1,cx,1279-cx,cy,719-cy,r,r+17)
              for on0,on1 in [(1,0),(0,1),(1,1)]
              for cx,cy in [(0,0),(1279,719),(640,360),(91,628)] for r in [0,25,96,719,1400]]
    lines=[str(len(cases))]
    for cfg in cases:
        points=[(0,0),(639,719),(320,360),(639,0),(0,719)]+[(rng.randrange(640),rng.randrange(720)) for _ in range(251)]
        lines.append(' '.join(map(str,cfg))+' '+str(len(points)))
        for x,y in points:lines.append(f'{x} {y} '+' '.join(map(str,warp(x,y,cfg))))
    (TEST/'math_vectors.txt').write_text('\n'.join(lines),encoding='ascii')
    def average565(a,b):
        return (((((a>>11)+(b>>11)+1)//2)<<11) |
                (((((a>>5)&63)+((b>>5)&63)+1)//2)<<5) |
                (((a&31)+(b&31)+1)//2))
    def row_words(case,y):
        cfg=(1,128,0,0,0,0,0,0,0,0) if case==1 else (0,0,1,1,100,200,20,30,80,160) if case==2 else (0,0,0,0,0,0,0,0,0,0)
        base=0 if case==1 else 1382400
        half=[];masks=[]
        for x in range(320):
            sx,sy=warp(x*2,y,cfg)
            a=word(base+460800+sy*320+sx//2)
            p=blend(a,word(1152000+y*320+x),128) if case==1 else a
            half.extend([p>>16,p&65535]);masks.append(case==1 or sx!=x*2 or sy!=y)
        output=[]
        for x in range(320):
            if masks[x]:
                a,b=half[x*2:x*2+2];c=half[min(639,x*2+2)]
                output.extend([(a<<16)|average565(a,b),(b<<16)|average565(b,c)])
            else:output.extend([word(base+y*640+x*2),word(base+y*640+x*2+1)])
        return output
    values=[f'{v:08x}' for case in range(3) for y in range(8) for v in row_words(case,y)]
    (TEST/'reader_vectors.txt').write_text('\n'.join(values),encoding='ascii')
    edge=[]
    for i in range(1000):
        x=rng.choice([0,1,25,75,76,1278,1279,640,rng.randrange(1280)])
        y=rng.choice([0,1,25,75,76,718,719,360,rng.randrange(720)])
        rgb=rng.randrange(1<<24);dark=rng.choice([0,8,16,24,32])
        w=round(max(0,1-min(x,1279-x,y,719-y)/76)**2.2*96);amount=w*128>>8
        values=[min(255,((rgb>>shift)&255)+add)*(32-dark)>>5 for shift,add in [(16,amount>>3),(8,amount>>2),(0,amount>>1)]]
        out=(values[0]<<16)|(values[1]<<8)|values[2]
        edge.append(f'{x} {y} {rgb:06x} {dark} {int(i%20==0)} {int(i%20==19)} {out:06x}')
    (TEST/'edge_vectors.txt').write_text(str(len(edge))+'\n'+'\n'.join(edge),encoding='ascii')
    if args.full:
        prepare_photos(ROOT)
        import numpy as np
        for w,h in [(640,480),(1280,720),(1920,1080)]:
            v=resize(w,h,out_width=1280)
            if (w,h)==(1280,720):
                from scaler_reference import source_rgb
                a=source_rgb(w,h);v=((a[:,:,0]<<16)|(a[:,:,1]<<8)|a[:,:,2]).ravel()
            np.savetxt(TEST/f'scaler_{w}_{h}.hex',v,fmt='%06x')
        def expand565(p):
            r=(p>>11)&31;g=(p>>5)&63;b=p&31
            return (r*8+(r>>2),g*4+(g>>4),b*8+(b>>2))
        checks=[]
        for mode in [6,0,7,5,9]:
            crc=0x811c9dc5
            for y in range(720):
                cfg=(1,128,0,0,0,0,0,0,0,0) if mode==6 else (0,0,1,1,998,346,454,432,600,400) if mode==0 else (0,0,0,0,0,0,0,0,0,0)
                half=[];masks=[]
                for x in range(320):
                    sx,sy=warp(x*2,y,cfg)
                    a=word(460800+sy*320+sx//2)
                    p=blend(a,word(1152000+y*320+x),128) if mode==6 else a
                    if mode in (5,9):
                        from effects_reference import mapped,lighting
                        aa,yy,bb,q,shade,shine=mapped(mode,128,False,x*2,y)
                        p=lighting(blend(word(460800+yy*320+aa//2),word(1152000+y*320+bb//2),q),shade,shine)
                    half.extend([p>>16,p&65535]);masks.append(mode in (5,6,9) or sx!=x*2 or sy!=y)
                for x in range(320):
                    if masks[x]:
                        a,b=half[x*2:x*2+2];c=half[min(639,x*2+2)]
                        pixels=[a,average565(a,b),b,average565(b,c)]
                    else:
                        a=word(y*640+x*2);b=word(y*640+x*2+1);pixels=[a>>16,a&65535,b>>16,b&65535]
                    for p in pixels:
                        c=expand565(p);rgb=(c[0]<<16)|(c[1]<<8)|c[2]
                        crc=((crc^rgb)*0x01000193)&0xffffffff
            checks.append(crc)
        (TEST/'frame_checksums.hex').write_text(''.join(f'{v:08x}\n' for v in checks),encoding='ascii')
    from effects_reference import mapped,lighting
    erng=random.Random(170103)
    elines=[]
    for fx in range(11):
        for p in range(257):
            for right in [0,1]:
                points=[(x,y) for x in [0,2,318,320,638] for y in [0,89,90,359,360,629,630,719]]
                points += [(erng.randrange(320)*2,erng.randrange(720)) for _ in range(8)]
                for x,y in points:
                    rgb=erng.getrandbits(32);values=mapped(fx,p,right,x,y)
                    elines.append(' '.join(map(str,[fx,p,right,1,x,y,x,y,*values]))+f' {rgb:08x} {lighting(rgb,values[-2],values[-1]):08x}')
    for n in range(1024):
        x=erng.randrange(320)*2;y=erng.randrange(720);wx=max(0,min(639,x+erng.randrange(-8,9)));wy=max(0,min(719,y+erng.randrange(-14,15)))
        fx=erng.randrange(11);p=erng.randrange(257);rgb=erng.getrandbits(32);values=mapped(fx,p,0,x,y,wx,wy,False)
        elines.append(' '.join(map(str,[fx,p,0,0,x,y,wx,wy,*values]))+f' {rgb:08x} {lighting(rgb,values[-2],values[-1]):08x}')
    (TEST/'effects_vectors.txt').write_text('\n'.join(elines),encoding='ascii')
    fx_lines=[]
    for fx in range(11):
        for right in [0,1]:
            for progress in [0,64,128,192,256]:
                for y in range(8):
                    half=[]
                    for x in range(320):
                        sx,sy=warp(x*2,y,(1,progress,0,0,0,0,0,0,0,0)) if fx==6 else (x*2,y)
                        a,yy,b,q,shade,shine=mapped(fx,progress,right,x*2,y,sx,sy)
                        v=lighting(blend(word(460800+yy*320+a//2),word(1152000+y*320+b//2),q),shade,shine)
                        half.extend([v>>16,v&65535])
                    for x in range(320):
                        if progress==256:out=[word(691200+y*640+2*x),word(691200+y*640+2*x+1)]
                        else:
                            a,b=half[2*x:2*x+2];c=half[min(639,2*x+2)]
                            out=[(a<<16)|average565(a,b),(b<<16)|average565(b,c)]
                        fx_lines.extend(f'{v:08x}' for v in out)
    (TEST/'fx_reader_vectors.txt').write_text('\n'.join(fx_lines),encoding='ascii')
    logs=[]
    suite=validation_suite(args.full)
    inputs={Path(__file__),ROOT/'tools'/'reference.py',ROOT/'tools'/'scaler_reference.py',*TEST.glob('water_*.hex')}
    if args.full:inputs.update([ROOT/'tools/photo_reference.py',PHOTO_WORK/'photo_data.hex',PHOTO_WORK/'photo_golden.hex',*sorted((ROOT/'tf_assets').glob('*.bmp'))])
    for name,files in suite:
        inputs.add(TEST/('tb_'+('bandwidth' if name in ('bandwidth_dwell','bandwidth_native','bandwidth_metal','bandwidth_tunnel') else name)+'.v'))
        inputs.update((RTL/f).resolve() for f in files)
    def hashes():return {str(p.resolve()):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(inputs)}
    before=hashes()
    cache_path=ROOT/'validation'/'rtl_cache.json'
    cache=json.loads(cache_path.read_text(encoding='utf-8')) if cache_path.exists() else {}
    def run_test(name,files):
        bench='bandwidth' if name in ('bandwidth_dwell','bandwidth_native','bandwidth_metal','bandwidth_tunnel') else name
        extra=['-P','tb.TEST_MODE='+str({'bandwidth_dwell':0,'bandwidth_native':7,'bandwidth_metal':5,'bandwidth_tunnel':9}[name])] if name in ('bandwidth_dwell','bandwidth_native','bandwidth_metal','bandwidth_tunnel') else []
        command=[IVER,'-DWATER_SIM','-g2005' if name=='scene' else '-g2012','-s','tb',*extra,'-o',str(TEST/(name+'.vvp')),str(TEST/('tb_'+bench+'.v'))]+[str(RTL/f) for f in files]
        dependencies=test_dependencies(name,files)
        digests={str(p.resolve()):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(dependencies)}
        entry=cache.get(name,{})
        if all(entry.get('inputs',{}).get(p)==digest for p,digest in digests.items()) and entry.get('command')==command:
            result_stdout=entry['stdout'];result_stderr=entry['stderr']
            cached=True
        else:
            subprocess.run(command,check=True,cwd=TEST)
            vvp_args=[f'+PHOTO_DATA={(PHOTO_WORK/"photo_data.hex").as_posix()}',f'+PHOTO_GOLDEN={(PHOTO_WORK/"photo_golden.hex").as_posix()}'] if name=='photos' else []
            result=subprocess.run([VVP,str(TEST/(name+'.vvp')),*vvp_args],capture_output=True,text=True,cwd=TEST)
            assert result.returncode==0 and 'PASS ' in result.stdout and 'FATAL:' not in result.stdout,(name,result.stdout,result.stderr)
            assert digests=={str(p.resolve()):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(dependencies)},'Test inputs changed'
            result_stdout=result.stdout;result_stderr=result.stderr
            cached=False
        return name,dict(inputs=digests,command=command,stdout=result_stdout,stderr=result_stderr),cached
    # Independent benches have distinct executables and read-only stimuli.
    # Only this parent thread writes the cache and manifests.
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        pending=[pool.submit(run_test,name,files) for name,files in suite]
        for future in as_completed(pending):
            name,entry,cached=future.result()
            stdout,stderr=entry['stdout'],entry['stderr']
            print(('CACHED ' if cached else '')+stdout.splitlines()[0],flush=True)
            if stderr:print(stderr,flush=True)
            cache[name]=entry
            cache_path.write_text(json.dumps(cache,indent=2),encoding='utf-8')
            logs.append(dict(test=name,stdout=stdout,stderr=stderr))
            (ROOT/'validation'/(name+'_test.log')).write_text(stdout+stderr,encoding='utf-8')
    assert before==hashes(),'Test inputs changed during validation'
    (ROOT/'validation'/'rtl_tests.json').write_text(json.dumps(dict(full=args.full,inputs=before,tests=logs),indent=2),encoding='utf-8')

if __name__=='__main__':main()
