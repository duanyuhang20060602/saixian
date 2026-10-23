"""Lossless animation/cache/throughput proofs, with native vendor models."""
from pathlib import Path
import argparse,concurrent.futures,hashlib,json,os,re,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
VENDOR=Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/ip/depot/AXI_Ethernet_Lite_1.0/AXI_Ethernet_Lite/RTL/ram_infer.v')
MULT=Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_mult18.v')
PROCESS=['common/photo_b_processing.v','tests/reference/animation_cache/photo_b_processing.v','common/photo_processing.v','common/photo_color_format.v','common/fluid/water_pack.v','common/photo_audio_link.v']
JOBS={
 'sprite':['tests/tb_compact_sprite.v','common/award_sprite_rom.v','tests/reference/animation_cache/award_sprite_rom.v'],
 'blend':['tests/tb_blend_native.v','common/fluid/water_blend.v','tests/reference/animation_cache/water_blend.v'],
 'blend_dsp':['tests/tb_blend_native.v','common/fluid/water_blend.v','tests/reference/animation_cache/water_blend.v','tests/fx11_water/glbl.v'],
 'fast_processing':['tests/tb_fast_processing.v',*PROCESS],
 'two_slot_cache':['tests/tb_two_slot_cache.v','common/photo_sd_cache.v','common/photo_color_format.v','common/photo_audio_link.v','common/photo_sd_audio_stream.v','common/photo_sd/photo_dlt_reader.v','common/photo_sd/photo_dlt_header.v'],
 'spi_contract':['tests/tb_spi_read_speed.v','common/photo_sd/spi_master.v'],
 'page_link':['tests/tb_fast_page_link.v',*PROCESS,'common/photo_link.v'],
}
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',required=True,type=Path);ap.add_argument('--only',nargs='+',choices=JOBS);ap.add_argument('--jobs',type=int,default=3);a=ap.parse_args()
 out=a.out.resolve();assert out.drive.upper()=='E:';out.mkdir(parents=True,exist_ok=True)
 env=os.environ.copy();temp=Path('E:/Codex/Temp/animation-cache-tests');temp.mkdir(parents=True,exist_ok=True);env.update(TEMP=str(temp),TMP=str(temp),TMPDIR=str(temp))
 model=out/'vendor_mult18_functional.v';text=MULT.read_text().split('`pragma protect begin_protected',1)[0]
 first=text.index('   always @(param_trig)');last=text.index('   end // always',first)+len('   end // always')
 text=text[:first]+text[first:last].replace('always @(param_trig)','always @*').replace('assign ','')+text[last:];model.write_text(text)
 def run(name):
  start=time.monotonic();files=[ROOT/p for p in JOBS[name]];inc=out/name;inc.mkdir(exist_ok=True)
  include=inc/'ip_init_map.vh';include.write_text('localparam HEX_FILE="";\n');evidence=[Path(__file__),include]
  extra=['-DWATER_SIM'];language='-g2012'
  if name in ('fast_processing','page_link'):files+=[ROOT/'tests/ip_vendor_ram_adapter.v',VENDOR]
  if name=='two_slot_cache':extra+=['-DVICTORY_SIM']
  if name=='blend_dsp':files+=[model];evidence+=[MULT];extra+=['-DBLEND_DSP_SIM','-s','glbl'];language='-g2005'
  before={p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p):sha(p) for p in [*files,*evidence]}
  binary=inc/'simulation.vvp';c=subprocess.run(['C:/iverilog/bin/iverilog.exe',language,'-I'+str(inc),*extra,'-s','tb','-o',str(binary),*map(str,files)],cwd=ROOT,env=env,capture_output=True,text=True)
  log=c.stdout+c.stderr
  if c.returncode==0:
   c=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=ROOT,env=env,capture_output=True,text=True,timeout=1200);log+=c.stdout+c.stderr
  path=out/(name+'.log');path.write_text(log,encoding='utf-8')
  unchanged=all(sha(Path(p) if Path(p).is_absolute() else ROOT/p)==h for p,h in before.items())
  passed=c.returncode==0 and 'PASS ' in log and unchanged and not re.search(r'(?im)^(ERROR:|FATAL:)',log)
  print(name+': '+log[-2600:],flush=True)
  return dict(test=name,passed=passed,seconds=round(time.monotonic()-start,2),inputs_sha256=before,log=str(path),log_sha256=sha(path))
 with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as pool:records=list(pool.map(run,a.only or JOBS))
 result=out/'results.json';old=json.loads(result.read_text()) if result.exists() else [];old=[r for r in old if r['test'] not in {r['test'] for r in records}];result.write_text(json.dumps(old+records,indent=2)+'\n')
 if not all(r['passed'] for r in records):raise SystemExit(1)
if __name__=='__main__':main()
