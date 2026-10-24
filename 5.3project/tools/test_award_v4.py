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
 'tb_boot_v4':['common/photo_boot_screen.v'],
 'tb_award_entry_v4':['common/photo_award_render.v','common/award_fx.v','common/award_sprite_rom.v'],
 'tb_award_headers':['tests/native_unused_bram.v','common/photo_sd/bmp_read.v','common/photo_sd/saixian_media_header.v','common/photo_sd/photo_dlt_header.v'],
 'tb_award_mode_v4':['common/photo_cached_control_a.v','common/photo_control.v','common/photo_uart.v','common/photo_link.v','common/saixian_transition.v'],
 'tb_award_catalog_v3':['tests/native_unused_bram.v','common/photo_sd/bmp_read.v','common/photo_sd/saixian_media_header.v','common/photo_sd/photo_dlt_header.v'],
}
report=OUT/'award_v4_results.json'
import argparse
parser=argparse.ArgumentParser();parser.add_argument('--resume',action='store_true');parser.add_argument('--only',nargs='+',choices=list(jobs));args=parser.parse_args()
results=json.loads(report.read_text()) if (args.resume or args.only) and report.exists() else []
for name,sources in jobs.items():
 if args.only and name not in args.only:continue
 if args.resume and any(v['test']==name and v['passed'] for v in results):continue
 results=[v for v in results if v['test']!=name]
 start=time.monotonic();binary=OUT/(name+'.vvp')
 subprocess.run([str(IV),'-g2012','-s',name,'-o',str(binary),'tests/'+name+'.v',*sources],cwd=ROOT,check=True)
 r=subprocess.run([str(IV.with_name('vvp.exe')),str(binary)],cwd=ROOT,capture_output=True,text=True,timeout=600)
 log=r.stdout+r.stderr;(OUT/(name+'.log')).write_text(log,encoding='utf-8');print(log,flush=True)
 passed=r.returncode==0 and 'PASS' in log and 'FATAL' not in log
 results.append(dict(test=name,passed=passed,seconds=round(time.monotonic()-start,2)))
 (OUT/'award_v4_results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
 if not passed:raise SystemExit(1)

# Render the RTL-generated PPM with only Python's standard library.
import zlib
ppm=(OUT/'boot_preview.ppm').read_bytes()
header=b'P6\n1280 720\n255\n';assert ppm.startswith(header)
pixels=ppm[len(header):];assert len(pixels)==1280*720*3
def chunk(tag,data):return struct.pack('>I',len(data))+tag+data+struct.pack('>I',zlib.crc32(tag+data))
scan=b''.join(b'\0'+pixels[y*3840:(y+1)*3840] for y in range(720))
(OUT/'boot_preview.png').write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>2I5B',1280,720,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(scan))+chunk(b'IEND',b''))
