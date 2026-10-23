"""Focused resource-allocation proofs; work products remain on E:."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
TD=Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116')
VENDOR=TD/'ip/depot/AXI_Ethernet_Lite_1.0/AXI_Ethernet_Lite/RTL/ram_infer.v'
DRAM=TD/'sim_release/eg4/eg_logic_dram.v'
JOBS={
 'hybrid_fifo':('tb',['tests/tb_ip_audio_fifo.v','tests/reference/award_v5/photo_audio_fifo.v','common/photo_audio_link.v','tests/ip_vendor_ram_adapter.v',VENDOR],[]),
 'typed_protocol':('tb_fx_protocol',['tests/tb_fx_protocol.v','common/photo_audio_link.v'],['VICTORY_SIM']),
 'av_link':('tb_resource_av_link',['tests/tb_resource_av_link.v','common/photo_audio_link.v','common/photo_av_metadata.v','common/photo_av_receiver.v','tests/resource_av_analysis_stub.v','tests/av_bram_model.v'],[]),
 'metadata':('tb_resource_metadata',['tests/tb_resource_metadata.v','common/photo_av_metadata.v','common/photo_av_receiver.v','common/audio_ui/saixian_audio_visualizer.v','tests/av_bram_model.v'],[]),
 'delay':('tb',['tests/tb_eram_video_delay.v','common/photo_display_pipe.v','tests/reference/award_v5/photo_display_pipe.v'],['ERAM_SIM']),
 'delay_vendor':('tb',['tests/tb_eram_video_delay.v','common/photo_display_pipe.v','tests/reference/award_v5/photo_display_pipe.v','tests/ip_vendor_ram_adapter.v',VENDOR,DRAM],[]),
}
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--work',type=Path,required=True);ap.add_argument('--only',nargs='+',choices=list(JOBS));args=ap.parse_args()
 out=args.work.resolve();assert out.drive.upper()=='E:';out.mkdir(parents=True,exist_ok=True)
 (out/'ip_init_map.vh').write_text('localparam HEX_FILE="";\n')
 env=os.environ.copy();temp=Path('E:/Codex/Temp/resource-tests');temp.mkdir(parents=True,exist_ok=True);env.update(TEMP=str(temp),TMP=str(temp),TMPDIR=str(temp))
 result_file=out/'results.json';results={r['test']:r for r in json.loads(result_file.read_text())} if result_file.exists() else {}
 for name in args.only or JOBS:
  top,paths,defines=JOBS[name];sources=[(ROOT/p).resolve() for p in paths]
  external=[]
  if name=='delay_vendor':
   # Icarus cannot parse the appended encrypted simulator alternatives.
   # Use the complete, unmodified plaintext module supplied before them.
   plain=out/'vendor_dram_plain.v';source=DRAM.read_text()
   plain.write_text(source[:source.index('endmodule')+len('endmodule')]+'\n')
   sources=[plain if p==DRAM else p for p in sources];external=[DRAM]
  evidence=sources+[Path(__file__)]+list((ROOT/'common/audio_ui').glob('saixian_av_*.hex')) if name=='metadata' else sources+[Path(__file__)]
  evidence+=external
  hashes={p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p):sha(p) for p in evidence}
  start=time.monotonic();binary=out/(name+'.vvp')
  run=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2005' if name=='delay_vendor' else '-g2012','-I'+str(out),*['-D'+d for d in defines],'-s',top,'-o',str(binary),*map(str,sources)],cwd=ROOT,env=env,capture_output=True,text=True)
  log=run.stdout+run.stderr
  if run.returncode==0:
   run=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=ROOT,env=env,capture_output=True,text=True,timeout=600);log+=run.stdout+run.stderr
  logfile=out/(name+'.log');logfile.write_text(log,encoding='utf-8')
  unchanged=all(sha(p)==hashes[p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p)] for p in evidence)
  passed=run.returncode==0 and 'PASS' in log and 'FATAL' not in log and 'ERROR:' not in log and unchanged
  results[name]={'test':name,'passed':passed,'seconds':round(time.monotonic()-start,2),'inputs_sha256':hashes,'defines':defines,'log':str(logfile),'log_sha256':sha(logfile),'inputs_unchanged':unchanged}
  result_file.write_text(json.dumps(list(results.values()),indent=2)+'\n')
  print(name+': '+log[-3500:],flush=True)
  if not passed:raise SystemExit(1)
if __name__=='__main__':main()
