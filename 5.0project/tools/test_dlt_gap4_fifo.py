"""Production gap4 plus real native FIFO, using the complete repaired relief asset."""
from pathlib import Path
import argparse,hashlib,json,os,re,subprocess,time
import numpy as np
from test_relief_bus import decode,savehex
ROOT=Path(__file__).resolve().parents[1];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);a=ap.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True);start=time.monotonic()
 temp=Path('E:/Codex/Temp/saixian-dlt-gap4-fifo-20261025');temp.mkdir(parents=True,exist_ok=True);env=os.environ.copy();env.update(TEMP=str(temp),TMP=str(temp),TMPDIR=str(temp))
 asset=ROOT/'award_media/RELIEF720.DLT';blob,_,_,expected=decode(asset);savehex(out/'award_file.hex',np.frombuffer(blob,dtype='<u4'));savehex(out/'award_expected.hex',expected)
 assert 'photo_dlt_reader #(.PIXEL_GAP(4)) dlt(' in (ROOT/'common/photo_sd_cache.v').read_text(encoding='utf-8')
 original=ROOT/'tests/tb_relief_reader.v';tb=original.read_text(encoding='utf-8');tb=tb.replace('photo_dlt_reader dut(', 'photo_dlt_reader #(.PIXEL_GAP(4)) dut(')
 tb=tb.replace('reg full=0;','wire full;');tb=tb.replace('always @(negedge clk)full=!rst && cycles%127<11;','')
 marker='''reg mc=0;always #11 mc=~mc;
wire empty;wire[31:0] fifo_data;integer drained=0,full_cycles=0;
wire drain=!empty && cycles%20000<6500;
wfifo_32_32_512 fifo(.rst(rst || write_req),.clkw(clk),.clkr(mc),.we(word_valid && !full),.di(word_data),.re(drain),.dout(fifo_data),.empty_flag(empty),.full_flag(full),.valid(),.afull(),.aempty(),.wrusedw(),.rdusedw());
always @(posedge clk)begin
 if(full)full_cycles<=full_cycles+1;
 if(!rst && word_valid && full)$fatal(1,"Gap4 FIFO overflow");
end
always @(posedge mc)begin
 if(rst || write_req)drained<=0;
 else if(drain)begin
  if(drained>=EXPECTED_WORDS || fifo_data!==expected[drained])$fatal(1,"Gap4 FIFO loss/reorder index=%0d",drained);
  drained<=drained+1;
 end
end
'''
 tb=tb.replace('photo_dlt_reader #(.PIXEL_GAP(4)) dut(',marker+'photo_dlt_reader #(.PIXEL_GAP(4)) dut(',1)
 tb=tb.replace('if(checks!=EXPECTED_WORDS || !aligned)', 'wait(drained==EXPECTED_WORDS);repeat(4)@(negedge mc);\n if(full_cycles==0)$fatal(1,"No full FIFO coverage");\n if(checks!=EXPECTED_WORDS || !aligned)')
 tb=tb.replace('PASS SXDLT TF decoding and RGB565 packing:', 'PASS production gap4, native asynchronous FIFO, real full stalls and complete ordered drain:')
 fixture=out/'dlt_gap4_fifo.v';fixture.write_text(tb,encoding='utf-8')
 files=[fixture,ROOT/'common/photo_sd/photo_dlt_reader.v',ROOT/'common/photo_sd/photo_dlt_header.v',ROOT/'common/photo_color_format.v',ROOT/'src/board_b/user_source/hdl_source/IP/afifo_16_32_256.v']
 evidence=files+[Path(__file__),ROOT/'tools/test_relief_bus.py',ROOT/'common/photo_sd_cache.v',original,asset,out/'award_file.hex',out/'award_expected.hex'];hashes={p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p):sha(p) for p in evidence};binary=out/'gap4.vvp'
 p=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-s','tb','-P',f'tb.FILE_WORDS={len(blob)//4}','-P',f'tb.EXPECTED_WORDS={len(expected)}','-o',str(binary),*map(str,files)],cwd=out,env=env,capture_output=True,text=True);log=p.stdout+p.stderr
 if p.returncode==0:
  p=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=out,env=env,capture_output=True,text=True,timeout=1800);log+=p.stdout+p.stderr
 path=out/'dlt_gap4_fifo.log';path.write_text(log,encoding='utf-8');unchanged=all(sha(q)==hashes[q.relative_to(ROOT).as_posix() if q.is_relative_to(ROOT) else str(q)] for q in evidence);passed=p.returncode==0 and 'PASS production gap4' in log and unchanged and not re.search(r'(?im)^(ERROR:|FATAL:)',log)
 record=dict(test='dlt_gap4_fifo',passed=passed,seconds=round(time.monotonic()-start,2),inputs_sha256=hashes,inputs_unchanged=unchanged,asset_sha256=sha(asset),log=str(path),log_sha256=sha(path));(out/'results.json').write_text(json.dumps([record],indent=2)+'\n',encoding='utf-8');print(log,flush=True)
 if not passed:raise SystemExit(1)
if __name__=='__main__':main()
