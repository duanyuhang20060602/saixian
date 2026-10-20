from pathlib import Path
import argparse,json,os,struct,subprocess,time,zlib
from verify_dlt import ROOT,verify
OUT=ROOT/'tests/results';OUT.mkdir(parents=True,exist_ok=True)
IV=Path(os.environ.get('IVERILOG','C:/Users/MR.HUSKY/Desktop/qian/.tools/iverilog/bin/iverilog.exe'))
blob,raw=verify()
(OUT/'dlt_bytes.hex').write_text(''.join(f'{v:02x}\n' for v in blob))
(OUT/'dlt_frame.hex').write_text(''.join(f'{v:08x}\n' for v in struct.unpack('<460800I',raw)))
pair=0x89103412
def fixture(mode):
 h=bytearray(512);table=bytearray(1024);payload=bytearray(512)
 command=0x80000000|460800;length=2;offset=384
 if mode==2:offset=385
 if mode==3:command=0xc0000001
 if mode==7:command=460800
 if mode==8:command=0x80000000
 if mode==9:command=0x40000001
 if mode==10:command=0x80000000|460801
 struct.pack_into('<2I',payload,0,command,pair)
 frame_crc=zlib.crc32(struct.pack('<I',pair)*460800)^(mode==6)
 stream_crc=zlib.crc32(payload[:8])^(mode==5)
 struct.pack_into('<8I',table,0,offset,length,50000000,frame_crc,stream_crc,0,0,0)
 body=table+payload
 struct.pack_into('<8s4H7I',h,0,b'SXDLT003',3,512,1280,720,1,2048,460800,1,32,zlib.crc32(body),2)
 result=h+body
 if mode==0:result[8]=4
 if mode==1:result[-1]^=1
 return result
for mode in range(12):
 (OUT/f'dlt_fault{mode}.hex').write_text(''.join(f'{v:02x}\n' for v in fixture(mode)))
jobs={
 'tb_dlt_reader':['tests/tb_dlt_reader.v','common/photo_sd/photo_dlt_reader.v','common/photo_sd/photo_dlt_header.v','common/photo_color_format.v'],
 'tb_dlt_faults':['tests/tb_dlt_faults.v','common/photo_sd/photo_dlt_reader.v','common/photo_sd/photo_dlt_header.v'],
 'tb_dlt_orientation':['tests/tb_dlt_orientation.v','src/board_b/user_source/hdl_source/SD/frame_fifo_write.v'],
 'tb_dlt_cache':['tests/tb_dlt_cache.v','tests/native_unused_bram.v','common/photo_sd_cache.v','common/photo_sd/bmp_read.v','common/photo_sd/saixian_media_header.v','common/photo_sd/photo_dlt_reader.v','common/photo_sd/photo_dlt_header.v','common/photo_color_format.v'],
}
p=argparse.ArgumentParser();p.add_argument('--only',nargs='+',choices=list(jobs));p.add_argument('--report',default='dlt_results.json');p.add_argument('--prepare-only',action='store_true');args=p.parse_args()
if args.prepare_only:raise SystemExit(0)
report=OUT/args.report;results=json.loads(report.read_text()) if args.only and report.exists() else []
for name,files in jobs.items():
 if args.only and name not in args.only:continue
 results=[r for r in results if r['test']!=name];start=time.monotonic();binary=OUT/(name+'.vvp')
 result=subprocess.run([str(IV),'-g2012','-s',name,'-o',str(binary),*files],cwd=ROOT,capture_output=True,text=True)
 if result.returncode:print(result.stdout+result.stderr);raise SystemExit(result.returncode)
 result=subprocess.run([str(IV.with_name('vvp.exe')),str(binary)],cwd=ROOT,capture_output=True,text=True,timeout=1200)
 log=result.stdout+result.stderr;(OUT/(name+'.log')).write_text(log,encoding='utf-8');print(log,flush=True)
 passed=result.returncode==0 and 'PASS' in log and 'FATAL' not in log
 results.append(dict(test=name,passed=passed,seconds=round(time.monotonic()-start,2)))
 report.write_text(json.dumps(results,indent=2)+'\n')
 if not passed:raise SystemExit(1)
