# Compare exact production timer slices, including unusual parameter widths.
from pathlib import Path
import argparse,hashlib,json,os,re,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);a=ap.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
 source=ROOT/'common/photo_cached_control_a.v';reference=ROOT/'tests/reference/timer_before/photo_cached_control_a.v';meta=ROOT/'tests/reference/timer_before/source.json';old=reference.read_text(encoding='utf-8');new=source.read_text(encoding='utf-8');metadata=json.loads(meta.read_text(encoding='utf-8'))
 assert hashlib.sha256(old.encode()).hexdigest()==metadata['original_normalized_sha256']
 start=old.index('reg timer_reset;');end=old.index('reg direction,done_seen,end_seen;',start);before=old[start:end]
 match=re.search(r'// begin RELIEF_TIMER_PIPELINE\n(.*?)// end RELIEF_TIMER_PIPELINE\n',new,re.S);assert match
 assert new.replace(match[0],before,1)==old,'Control/packet logic changed outside timer'
 def timer_module(name,body):
  body=body.replace('reg timer_reset;','',1)
  return 'module '+name+' #(parameter TIME_HZ=75000000)(input clk,rst,timer_reset,output [31:0] observed_count,output [4:0] flags);\n'+body+'\nassign observed_count=timer_count;assign flags={timeout45,timeout40,timeout5,timeout2,timeout1};\nendmodule\n'
 tb='`timescale 1ns/1ps\n'+timer_module('timer_original',before)+timer_module('timer_new',match[1])+'''
module timer_case #(parameter TIME_HZ=75000000)(input clk,output reg done=0);
reg rst=1,timer_reset=0;wire[31:0] old_count,new_count;wire[4:0] old_flags,new_flags;
timer_original #(.TIME_HZ(TIME_HZ)) original(.clk(clk),.rst(rst),.timer_reset(timer_reset),.observed_count(old_count),.flags(old_flags));
timer_new #(.TIME_HZ(TIME_HZ)) actual(.clk(clk),.rst(rst),.timer_reset(timer_reset),.observed_count(new_count),.flags(new_flags));
integer checks=0,i;reg[31:0] rng=32'h871209ab;
always @(posedge clk)begin
 #1;if(old_count!==new_count || old_flags!==new_flags)$fatal(1,"timer mismatch HZ=%0d clear=%0d count=%h/%h flags=%b/%b",TIME_HZ,timer_reset,old_count,new_count,old_flags,new_flags);
 if(!rst)checks=checks+1;
end
task probe;input[31:0] seed;begin
 @(negedge clk);original.timer_count=seed;actual.timer_count=seed;
 repeat(3)@(negedge clk);
end endtask
task threshold;input[63:0] value;begin probe(value-2);probe(value-1);probe(value);probe(value+1);end endtask
initial begin
 repeat(3)@(negedge clk);rst=0;
 probe(0);probe(1);probe(2);probe(32'hfffffffd);probe(32'hfffffffe);probe(32'hffffffff);
 threshold(TIME_HZ);threshold(TIME_HZ*2);threshold(64'd5*TIME_HZ);threshold(64'd40*TIME_HZ);threshold(64'd45*TIME_HZ);
 for(i=0;i<128;i=i+1)begin rng=rng*32'd1664525+32'd1013904223;timer_reset=i%7==0;probe(rng);end
 timer_reset=1;repeat(5)@(negedge clk);timer_reset=0;repeat(5)@(negedge clk);
 #2;rst=1;#1;if(old_count!==new_count || old_flags!==new_flags)$fatal(1,"async reset mismatch");#1;rst=0;
 repeat(5)@(negedge clk);if(checks<450)$fatal(1,"incomplete timer coverage");done=1;
end
endmodule
module tb;
reg clk=0;always #5 clk=~clk;wire[8:0]done;
timer_case #(.TIME_HZ(0)) a(clk,done[0]);timer_case #(.TIME_HZ(1)) b(clk,done[1]);timer_case #(.TIME_HZ(7)) c(clk,done[2]);
timer_case #(.TIME_HZ(75000000)) d(clk,done[3]);timer_case #(.TIME_HZ(150000000)) e(clk,done[4]);
timer_case #(.TIME_HZ(32'h80000000)) f(clk,done[5]);timer_case #(.TIME_HZ(64'd4294967296)) g(clk,done[6]);
timer_case #(.TIME_HZ(-1)) h(clk,done[7]);timer_case #(.TIME_HZ(32'hffffffff)) j(clk,done[8]);
initial begin wait(&done);$display("PASS production timer lookahead: exact cycle equivalence in 9 parameter configurations, all 1/2/5/40/45-second boundaries, 32-bit wrap, clears, async reset and randomized states; other controller logic unchanged");$finish;end
initial begin #2000000;$fatal(1,"timer test timeout");end
endmodule
'''
 fixture=out/'timer_equivalence.v';fixture.write_text(tb,encoding='utf-8');files=[source,reference,meta,Path(__file__),fixture];hashes={p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p):sha(p) for p in files};temp=out/'temp';temp.mkdir(exist_ok=True);env=os.environ.copy();env.update(TEMP=str(temp),TMP=str(temp),TMPDIR=str(temp));started=time.monotonic();binary=out/'timer.vvp'
 p=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-s','tb','-o',str(binary),str(fixture)],cwd=out,env=env,capture_output=True,text=True);log=p.stdout+p.stderr
 if p.returncode==0:
  p=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=out,env=env,capture_output=True,text=True,timeout=60);log+=p.stdout+p.stderr
 path=out/'timer_equivalence.log';path.write_text(log,encoding='utf-8');unchanged=all(sha(Path(k) if Path(k).is_absolute() else ROOT/k)==h for k,h in hashes.items());passed=p.returncode==0 and 'PASS production timer' in log and not re.search(r'(?im)^(ERROR:|FATAL:)',log) and unchanged
 result=dict(test='timer_equivalence',passed=passed,inputs_sha256=hashes,inputs_unchanged=unchanged,seconds=round(time.monotonic()-started,2),log=str(path),log_sha256=sha(path),scope=metadata['scope']+' Actual old/new timer code compared around each threshold, wrap and randomized clears in nine parameter configurations.')
 (out/'results.json').write_text(json.dumps([result],indent=2)+'\n',encoding='utf-8');print(log,flush=True)
 if not passed:raise SystemExit('Timer equivalence failed')
if __name__=='__main__':main()
