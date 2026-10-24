from pathlib import Path
import argparse,json,os,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'tests/results';OUT.mkdir(parents=True,exist_ok=True)
IV=Path(os.environ.get('IVERILOG','C:/Users/MR.HUSKY/Desktop/qian/.tools/iverilog/bin/iverilog.exe'))
jobs={
 'tb_award_headers':['tests/tb_award_headers.v','tests/native_unused_bram.v','common/photo_sd/bmp_read.v','common/photo_sd/saixian_media_header.v'],
 'tb_bmp':['tests/tb_bmp.v','tests/native_unused_bram.v','common/photo_sd/bmp_read.v','common/photo_sd/saixian_media_header.v'],
 'tb_award_control':['tests/tb_award_control.v','common/photo_cached_control_a.v','common/photo_control.v','common/photo_uart.v','common/photo_link.v','common/saixian_transition.v'],
 'tb_award_fx':['tests/tb_award_fx.v','common/award_fx.v','common/award_sprite_rom.v'],
 'tb_award_fifo_link':['tests/tb_award_fifo_link.v','common/photo_link.v','src/board_b/user_source/hdl_source/IP/afifo_32_16_256.v','src/board_b/user_source/hdl_source/IP/afifo_16_32_256.v'],
 'tb_award_pixels':['tests/tb_award_pixels.v','src/board_a/user_source/hdl_source/frame_pixels.v','common/photo_award_render.v','common/award_fx.v','common/award_sprite_rom.v'],
}
p=argparse.ArgumentParser();p.add_argument('--only',nargs='+',choices=list(jobs));args=p.parse_args()
report=OUT/'award_regression.json'
results=json.loads(report.read_text()) if args.only and report.exists() else []
for name,files in jobs.items():
 if args.only and name not in args.only:continue
 if 'common/photo_sd/bmp_read.v' in files:files=files+['common/photo_sd/photo_dlt_header.v']
 results=[r for r in results if r['test']!=name]
 start=time.monotonic();binary=OUT/(name+'.vvp')
 result=subprocess.run([str(IV),'-g2012','-s',name,'-o',str(binary),*files],cwd=ROOT,capture_output=True,text=True)
 if result.returncode:print(result.stdout+result.stderr);raise SystemExit(result.returncode)
 result=subprocess.run([str(IV.with_name('vvp.exe')),str(binary)],cwd=ROOT,capture_output=True,text=True,timeout=600)
 log=result.stdout+result.stderr;(OUT/(name+'.log')).write_text(log,encoding='utf-8');print(log,flush=True)
 passed=result.returncode==0 and 'PASS' in log and 'FATAL' not in log
 results.append(dict(test=name,passed=passed,seconds=round(time.monotonic()-start,2)))
 (OUT/'award_regression.json').write_text(json.dumps(results,indent=2)+'\n')
 if not passed:raise SystemExit(1)
