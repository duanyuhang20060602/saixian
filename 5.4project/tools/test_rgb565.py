"""Fixed RGB565 data-path acceptance; no board outputs or baseline are altered."""
from pathlib import Path
import argparse,concurrent.futures,hashlib,json,os,re,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
VENDOR=Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/ip/depot/AXI_Ethernet_Lite_1.0/AXI_Ethernet_Lite/RTL/ram_infer.v')
JOBS={
 'rgb565_equivalence':['tests/tb_rgb565_equivalence.v','common/photo_color_format.v','tests/reference/rgb565/photo_color_format.v','src/board_a/user_source/hdl_source/frame_pixels.v','tests/reference/rgb565/frame_pixels.v'],
 'rgb565_scaler':['tests/tb_ip_scaler.v','common/photo_sd/bmp_read.v'],
 'rgb565_award_link':['tests/tb_award_v5_link.v','common/photo_link.v'],
 'rgb565_link_abort':['tests/tb_research_link_abort.v','common/photo_link.v'],
 'rgb565_settings':['tests/tb_rgb565_settings.v','common/photo_unified_settings_controller.v'],
 'rgb565_award_sdram':['tests/tb_award_v5_sdram_link.v','src/board_b/user_source/hdl_source/frame_store.v','src/board_b/user_source/hdl_source/SD/frame_read_write.v','src/board_b/user_source/hdl_source/SD/frame_fifo_read.v','src/board_b/user_source/hdl_source/SD/frame_fifo_write.v','src/board_b/user_source/hdl_source/IP/afifo_32_16_256.v','src/board_b/user_source/hdl_source/IP/afifo_16_32_256.v','common/photo_link.v','common/photo_spotlight_player.v','common/photo_award_memory.v'],
}
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',required=True,type=Path);ap.add_argument('--only',nargs='+',choices=JOBS);ap.add_argument('--award-fixtures',type=Path);a=ap.parse_args()
 out=a.out.resolve();assert out.drive.upper()=='E:';out.mkdir(parents=True,exist_ok=True)
 env=os.environ.copy();temp=Path('E:/Codex/Temp/rgb565-tests');temp.mkdir(parents=True,exist_ok=True);env.update(TEMP=str(temp),TMP=str(temp),TMPDIR=str(temp))
 def run(name):
  start=time.monotonic();files=[ROOT/p for p in JOBS[name]];inc=out/name;inc.mkdir(exist_ok=True)
  include=inc/'ip_init_map.vh';include.write_text('localparam HEX_FILE="";\n')
  if name in ('rgb565_processing','rgb565_scaler'):files+=[ROOT/'tests/ip_vendor_ram_adapter.v',VENDOR]
  extra=[];cwd=ROOT;fixtures=[]
  if name=='rgb565_award_sdram':
   import shutil
   assert a.award_fixtures
   for p in a.award_fixtures.glob('*.hex'):shutil.copy2(p,inc/p.name)
   fixtures=[*inc.glob('*.hex')];extra=['-DWATER_SIM'];cwd=inc
  before={p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p):sha(p) for p in [*files,Path(__file__),include,*fixtures]}
  binary=inc/'simulation.vvp'
  c=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-I'+str(inc),*extra,'-s','tb','-o',str(binary),*map(str,files)],cwd=cwd,env=env,capture_output=True,text=True)
  log=c.stdout+c.stderr
  if c.returncode==0:
   c=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=cwd,env=env,capture_output=True,text=True,timeout=900);log+=c.stdout+c.stderr
  path=out/(name+'.log');path.write_text(log,encoding='utf-8')
  unchanged=all(sha(Path(p) if Path(p).is_absolute() else ROOT/p)==h for p,h in before.items())
  passed=c.returncode==0 and 'PASS ' in log and unchanged and not re.search(r'(?im)^(ERROR:|FATAL:)',log)
  print(name+': '+log[-2200:],flush=True)
  return dict(test=name,passed=passed,seconds=round(time.monotonic()-start,2),inputs_sha256=before,log=str(path),log_sha256=sha(path))
 with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:records=list(pool.map(run,a.only or JOBS))
 result=out/'results.json';old=json.loads(result.read_text()) if result.exists() else [];old=[r for r in old if r['test'] not in {r['test'] for r in records}]
 result.write_text(json.dumps(old+records,indent=2)+'\n')
 if not all(r['passed'] for r in records):raise SystemExit(1)
if __name__=='__main__':main()
