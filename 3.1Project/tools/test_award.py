from pathlib import Path
import argparse,json, os, struct, subprocess, time
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'tests/results';OUT.mkdir(parents=True,exist_ok=True)
IV=Path(os.environ.get('IVERILOG', 'C:/Users/MR.HUSKY/Desktop/qian/.tools/iverilog/bin/iverilog.exe'))
jobs={
 'tb_award_render':['tests/tb_award_render.v','common/photo_award_render.v','common/award_fx.v','common/award_sprite_rom.v'],
 'tb_award_asset':['tests/tb_award_asset.v','tests/native_unused_bram.v','common/photo_sd/bmp_read.v','common/photo_sd/saixian_media_header.v','common/photo_color_format.v'],
}
p=argparse.ArgumentParser();p.add_argument('--only',nargs='+',choices=list(jobs),default=['tb_award_render']);args=p.parse_args()
if 'tb_award_asset' in args.only:
 bmp=(ROOT/'award_media/AWARD720.BMP').read_bytes()
 assert bmp[6:10]==b'SXAW' and len(bmp)==2764854
 (OUT/'award_bytes.hex').write_text(''.join(f'{v:02x}\n' for v in bmp+bytes((-len(bmp))%512)))
 pixels=[(bmp[i+2]<<16)|(bmp[i+1]<<8)|bmp[i] for i in range(54,len(bmp),3)]
 (OUT/'award_pixels.hex').write_text(''.join(f'{v:06x}\n' for v in pixels))
results=[]
for name,sources in jobs.items():
 if args.only and name not in args.only:continue
 if 'common/photo_sd/bmp_read.v' in sources:sources=sources+['common/photo_sd/photo_dlt_header.v']
 start=time.monotonic();binary=OUT/(name+'.vvp')
 subprocess.run([str(IV),'-g2012','-s',name,'-o',str(binary),*sources],cwd=ROOT,check=True)
 result=subprocess.run([str(IV.with_name('vvp.exe')),str(binary)],cwd=ROOT,capture_output=True,text=True,timeout=600)
 log=result.stdout+result.stderr;(OUT/(name+'.log')).write_text(log,encoding='utf-8');print(log,flush=True)
 passed=result.returncode==0 and 'PASS' in log and 'FATAL' not in log
 results.append(dict(test=name,passed=passed,seconds=round(time.monotonic()-start,2)))
 (OUT/'award_results.json').write_text(json.dumps(results,indent=2)+'\n')
 if not passed:raise SystemExit(1)
