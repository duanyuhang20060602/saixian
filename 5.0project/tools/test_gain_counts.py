"""Prove exact incremental gain thresholds, including count rollover."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);a=ap.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
 files=[ROOT/'common/photo_sd_cache.v',ROOT/'tests/reference/gain_counts/photo_sd_cache_before.v',Path(__file__)]
 s=files[0].read_text();old=files[1].read_text();body=s[s.index('reg [14:0] stat_count3;'):s.index('reg [20:0] words;')];ref=old[old.index('wire [1:0] loaded_gain='):old.index('reg [20:0] words;')].replace('loaded_gain','original_gain')
 wrapper=out/'production_gain.v';wrapper.write_text('module production_gain(input clk,rst,loading,scaler_pixel,load_start,input [10:0] stat_x,input [9:0] stat_y,input [12:0] stat_count,input [20:0] stat_sum,output [1:0] result,reference);\nwire [20:0] count_ext={8\'d0,stat_count};\n'+body+ref+'assign result=loaded_gain;assign reference=original_gain;endmodule\n')
 tb=out/'tb.v';tb.write_text('''`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;reg rst=1,loading=0,scaler_pixel=0,load_start=0;
reg [10:0] stat_x=0;reg [9:0] stat_y=0;reg [12:0] count=0;reg [20:0] sum=0;wire [1:0] result,reference;
production_gain dut(.clk(clk),.rst(rst),.loading(loading),.scaler_pixel(scaler_pixel),.load_start(load_start),.stat_x(stat_x),.stat_y(stat_y),.stat_count(count),.stat_sum(sum),.result(result),.reference(reference));
always @(posedge clk or posedge rst)if(rst)count<=0;else if(loading && scaler_pixel && stat_x[3:0]==0 && stat_y[3:0]==0)count<=count+1'b1;else if(load_start)count<=0;
integer i,j,k,checks=0,wraps=0;reg [31:0] rng=32'h6127def3;
always @(posedge clk)begin #1;if(!rst)begin
 if(dut.stat_count3!==count*3 || dut.stat_count9!==count*9)$fatal(1,"counter multiple changed n=%d",count);
 if(result!==reference)$fatal(1,"gain changed n=%d sum=%d result=%d expected=%d",count,sum,result,reference);
 checks=checks+1;
end end
initial begin
 repeat(5)@(negedge clk);rst=0;
 // Two full count wraps, with all three boundaries and exact equality.
 for(i=0;i<16384;i=i+1)begin
  for(j=0;j<3;j=j+1)for(k=-1;k<=1;k=k+1)begin
   @(negedge clk);loading=0;scaler_pixel=0;sum=count*(j==0 ? 64:j==1 ? 96:144)+k;
  end
  @(negedge clk);loading=1;scaler_pixel=1;stat_x=0;stat_y=0;
  @(negedge clk);loading=0;scaler_pixel=0;if(count==0)wraps=wraps+1;
 end
 for(i=0;i<100000;i=i+1)begin
  @(negedge clk);rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
  loading=rng[0];scaler_pixel=rng[1];load_start=rng[7:2]==0;stat_x=rng[8] ? 0:rng[19:9];stat_y=rng[20] ? 0:rng[30:21];sum=rng[20:0];rst=i%5000==4999;
 end
 @(negedge clk);if(wraps!=2)$fatal(1,"missing count wraps");
 $display("PASS exact gain thresholds: %0d same-cycle comparisons, all 8192 counts at all nine boundary values, two wraps, reset/load/sample/hold priority",checks);$finish;
end
endmodule
''')
 h={p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p):sha(p) for p in files+[wrapper,tb]};start=time.monotonic();exe=out/'gain.vvp';env=os.environ.copy();temp=out/'temp';temp.mkdir(exist_ok=True);env.update(TEMP=str(temp),TMP=str(temp),TMPDIR=str(temp))
 c=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-s','tb','-o',str(exe),str(wrapper),str(tb)],cwd=out,env=env,capture_output=True,text=True);log=c.stdout+c.stderr
 if not c.returncode:c=subprocess.run(['C:/iverilog/bin/vvp.exe',str(exe)],cwd=out,env=env,capture_output=True,text=True,timeout=120);log+=c.stdout+c.stderr
 lp=out/'gain_counts.log';lp.write_text(log);passed=c.returncode==0 and 'PASS ' in log and 'FATAL' not in log and all(sha(ROOT/k if not Path(k).is_absolute() else Path(k))==v for k,v in h.items())
 (out/'results.json').write_text(json.dumps([dict(test='gain_counts',passed=passed,inputs_sha256=h,log=str(lp),log_sha256=sha(lp),seconds=round(time.monotonic()-start,2))],indent=2));print(log,flush=True)
 if not passed:raise SystemExit(1)
if __name__=='__main__':main()
