from pathlib import Path
import argparse,hashlib,json,subprocess,time
R=Path(__file__).resolve().parents[1];O=R/'tests/results';O.mkdir(exist_ok=True)
IV=Path('C:/Users/MR.HUSKY/Desktop/qian/.tools/iverilog/bin/iverilog.exe')
reader='projects/board_a/src/user_source/hdl_source/SD/frame_fifo_read.v'
jobs={'tb_neutral_cleanup':['common/photo_display_pipe.v','common/photo_processing.v'],
      'tb_rgb888_transitions':[reader], 'tb_mapper':[reader],
      'tb_fade_no_flash':['common/photo_display_pipe.v','common/saixian_transition.v'],
      'tb_audio_osd_port':['common/audio_ui/saixian_osd_overlay.v']}
p=argparse.ArgumentParser();p.add_argument('--only',nargs='+',choices=jobs);args=p.parse_args()
report=O/'visual_fx_results.json';results=json.loads(report.read_text()) if report.exists() else []
for name,deps in jobs.items():
 if args.only and name not in args.only:continue
 start=time.monotonic();binary=O/(name+'.vvp');sources=['tests/'+name+'.v',*deps]
 subprocess.run([str(IV),'-g2012','-s',name,'-o',str(binary),*sources],cwd=R,check=True)
 with (O/(name+'.log')).open('w') as f:r=subprocess.run([str(IV.with_name('vvp.exe')),str(binary)],cwd=R,stdout=f,stderr=subprocess.STDOUT,timeout=600)
 log=(O/(name+'.log')).read_text();print(log,flush=True)
 passed=r.returncode==0 and 'PASS' in log and 'FATAL' not in log
 result={'test':name,'passed':passed,'seconds':round(time.monotonic()-start,2),'source_sha256':{s:hashlib.sha256((R/s).read_bytes()).hexdigest() for s in sources}}
 results=[v for v in results if v['test']!=name]+[result];report.write_text(json.dumps(results,indent=2)+'\n')
 if not passed:raise SystemExit(1)
