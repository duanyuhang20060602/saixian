"""Check the chosen memory/DSP IP configurations without changing pixels or PCM."""
from pathlib import Path
import concurrent.futures,hashlib,json,os,re,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
OUT=Path('E:/Codex/Work/cooperate-ip-global/tests')
VENDOR=Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/ip/depot/AXI_Ethernet_Lite_1.0/AXI_Ethernet_Lite/RTL/ram_infer.v')
MULT=Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_mult18.v')
MULT_MODEL=Path('E:/Codex/Work/cooperate-fx11-water-tests-20261018/vendor_mult18_functional.v')
JOBS={
 'ip_fifo':['tests/tb_ip_audio_fifo.v','tests/reference/award_v5/photo_audio_fifo.v','common/photo_audio_link.v'],
 'ip_processing':['tests/tb_ip_processing.v','tests/reference/award_v5/photo_b_processing.v','common/photo_b_processing.v','common/photo_processing.v','common/photo_color_format.v','common/fluid/water_pack.v','common/photo_audio_link.v'],
 'ip_scaler':['tests/tb_ip_scaler.v','common/photo_sd/bmp_read.v'],
 'ip_atlas':['tests/tb_ip_atlas.v','common/saixian_battle_result_fx_pipelined.v'],
 'ip_av':['tests/tb_audio_visual_real.v','common/audio_ui/saixian_audio_visualizer.v'],
 'ip_edge_native':['tests/tb_award_v5_edge.v','tests/reference/award_v5/water_edge.v','common/fluid/water_edge.v']}
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def hexwords(p,words,width):p.write_text(''.join(f'{v:0{width}x}\n' for v in words),encoding='utf-8')
def main():
    OUT.mkdir(parents=True,exist_ok=True)
    assets=[];mapping={}
    project=ROOT/'src/board_a/user_source/hdl_source'
    for mif in project.glob('saixian_*atlas*.mif'):
        source=mif.read_text(encoding='utf-8');depth=int(re.search(r'DEPTH\s*=\s*(\d+)',source,re.I)[1])
        width=int(re.search(r'WIDTH\s*=\s*(\d+)',source,re.I)[1]);words=[None]*depth
        for a,v in re.findall(r'(?mi)^\s*([0-9a-f]+)\s*:\s*([0-9a-f]+)\s*;',source):words[int(a,16)]=int(v,16)
        assert all(v is not None for v in words),mif
        destination=OUT/(mif.stem+'.hex');hexwords(destination,words,(width+3)//4)
        mapping['../src/board_a/user_source/hdl_source/'+mif.name]=destination
        assets.append(mif)
    for name in ['saixian_av_twiddle_serial.hex','saixian_av_hann_half.hex']:
        p=ROOT/'common/audio_ui'/name;assets.append(p)
        mapping[name+'_0_0.mif']=p;mapping['common/audio_ui/'+name+'_0_0.mif']=p
    expression='""'
    for key,p in mapping.items():expression=f'INIT_FILE=="{key}" ? "{p.as_posix()}" : '+expression
    (OUT/'ip_init_map.vh').write_text('localparam HEX_FILE='+expression+';\n',encoding='utf-8')
    for name,addr in [('saixian_sprint_atlas',13),('saixian_victory_atlas',12)]:
        paths=[project/(name+s+'.hex') for s in ['_index_lo','_index_hi','_dict']];assets+=paths
        lo,hi,d=[[int(v,16) for v in p.read_text(encoding='utf-8').split()] for p in paths]
        raw=[d[(((hi[i//8]>>(i%8*2))&3)<<8)|((lo[i//2]>>(i%2*8))&255)] for i in range(1<<addr)]
        hexwords(OUT/('sprint_golden.hex' if addr==13 else 'victory_golden.hex'),raw,8)
    av=OUT/'tb_ip_av.v'
    av.write_text((ROOT/'tests/tb_audio_visual_real.v').read_text(encoding='utf-8').replace('saixian_av_fft fft(', 'saixian_av_fft #(.SMALL_RAM(1)) fft(').replace('saixian_av_wave wave(', 'saixian_av_wave #(.SMALL_RAM(1)) wave('),encoding='utf-8')
    (OUT/'glbl.v').write_text("module glbl;reg gsrn=1'b1;reg done_gwe=1'b1;endmodule\n",encoding='utf-8')
    stimuli={p.name:digest(p) for p in OUT.iterdir() if p.suffix in ('.hex','.vh') or p.name in ('tb_ip_av.v','glbl.v')}
    env=os.environ.copy();temp=Path('E:/Codex/Temp/cooperate-ip-global');temp.mkdir(parents=True,exist_ok=True)
    env.update(TEMP=str(temp),TMP=str(temp),TMPDIR=str(temp))
    def run(name):
        start=time.monotonic();sources=[ROOT/p for p in JOBS[name]]
        evidence=sources+[ROOT/'tests/ip_vendor_ram_adapter.v',Path(__file__),*assets]
        hashes={p.relative_to(ROOT).as_posix():digest(p) for p in evidence}
        external={str(VENDOR):digest(VENDOR)};top='tb';extra=[];language='-g2012'
        if name=='ip_av':sources[0]=av;top='tb_audio_visual_real'
        if name=='ip_atlas':language='-g2005'
        if name=='ip_edge_native':
            language='-g2005';sources += [MULT_MODEL,OUT/'glbl.v'];extra=['-s','glbl']
            external.update({str(MULT):digest(MULT),str(MULT_MODEL):digest(MULT_MODEL)})
        else:sources += [ROOT/'tests/ip_vendor_ram_adapter.v',VENDOR]
        binary=OUT/(name+'.vvp')
        result=subprocess.run(['C:/iverilog/bin/iverilog.exe',language,'-I',str(OUT),'-s',top,*extra,'-o',str(binary),*map(str,sources)],cwd=OUT,env=env,capture_output=True,text=True)
        log=result.stdout+result.stderr
        if not result.returncode:
            result=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=OUT,env=env,capture_output=True,text=True,timeout=600);log+=result.stdout+result.stderr
        (OUT/(name+'.log')).write_text(log,encoding='utf-8')
        unchanged=all(digest(ROOT/p)==h for p,h in hashes.items()) and all(digest(Path(p))==h for p,h in external.items())
        passed=result.returncode==0 and 'PASS ' in log and unchanged and not re.search(r'(?im)^(ERROR:|FATAL:)',log)
        print(name+': '+log[-1800:],flush=True)
        return dict(test=name,passed=passed,inputs_unchanged=unchanged,seconds=round(time.monotonic()-start,2),inputs_sha256=hashes,
                    external_inputs_sha256=external,stimuli_sha256=stimuli,log_sha256=digest(OUT/(name+'.log')))
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:results=list(pool.map(run,JOBS))
    (OUT/'results.json').write_text(json.dumps(results,indent=2)+'\n',encoding='utf-8')
    if not all(r['passed'] for r in results):raise SystemExit('IP configuration proof failed')
if __name__=='__main__':main()
