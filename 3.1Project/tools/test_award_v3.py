from pathlib import Path
import json,struct,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'tests/results'
OUT.mkdir(exist_ok=True)
# A complete, independently valid header for discovery (no frame decode in
# this test). Do not depend on generated artifacts from another test runner.
header=bytearray(512)
struct.pack_into('<8s4H7I',header,0,b'SXDLT003',3,512,1280,720,1,2048,460800,1,32,0,2)
(OUT/'dlt_catalog_header.hex').write_text(''.join(f'{v:02x}\n' for v in header),encoding='utf-8')
IV=Path('C:/Users/MR.HUSKY/Desktop/qian/.tools/iverilog/bin/iverilog.exe')
jobs={
 'tb_award_notice_v3':['common/photo_award_render.v'],
 'tb_award_mode_v3':['common/photo_cached_control_a.v','common/photo_control.v','common/photo_uart.v','common/photo_link.v','common/saixian_transition.v'],
 'tb_award_catalog_v3':['tests/native_unused_bram.v','common/photo_sd/bmp_read.v','common/photo_sd/saixian_media_header.v','common/photo_sd/photo_dlt_header.v'],
}
results=[]
for name,sources in jobs.items():
 start=time.monotonic();binary=OUT/(name+'.vvp')
 subprocess.run([str(IV),'-g2012','-s',name,'-o',str(binary),'tests/'+name+'.v',*sources],cwd=ROOT,check=True)
 r=subprocess.run([str(IV.with_name('vvp.exe')),str(binary)],cwd=ROOT,capture_output=True,text=True,timeout=600)
 log=r.stdout+r.stderr;(OUT/(name+'.log')).write_text(log,encoding='utf-8');print(log,flush=True)
 passed=r.returncode==0 and 'PASS' in log and 'FATAL' not in log
 results.append(dict(test=name,passed=passed,seconds=round(time.monotonic()-start,2)))
 (OUT/'award_v3_results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
 if not passed:raise SystemExit(1)
