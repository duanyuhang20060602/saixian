"""Independent numerical checks for pointer-centred portal and color ripple."""
from pathlib import Path
import argparse,hashlib,json,math,random,subprocess
from color_ripple_reference import NOISE,phase
ROOT=Path(__file__).resolve().parents[1]

def expected(f,p,x,y,cx,cy):
 if f==7:
  delta=36*p*p-(2*x-cx)**2-(y-cy)**2
  a=2*x+(delta//2048 if abs(delta)<24576 else 0)
  alpha=max(0,min(256,128+delta//128))
  shade=4 if -24576<delta<0 else 0
  shine=7 if abs(delta)<8192 else 2 if abs(delta)<16384 else 0
  if p in (0,256):a=2*x;alpha=p;shade=shine=0
  return max(0,min(639,a//2)),y,x,alpha,shade,shine
 q=phase(p)
 ia=((x+y//2+q)//2)&255;ib=((y+x//2-q)//2)&255
 ic=(x+2*y+2*q)&255;idx=(3*x-y+3*q)&255
 n=NOISE[ia]+NOISE[256+ib]+(NOISE[512+ic]+NOISE[768+idx])//2
 dx,dy=abs(2*x-cx),abs(y-cy)
 radius=max(dx,dy)+min(dx,dy)//4+min(dx,dy)//8
 delta=radius+n-(6*q+q//4)
 alpha=max(0,min(256,128-2*delta))
 t=abs(delta)//8*8
 env=round(31*math.exp(-t*t/(2*110**2))*max(0,math.cos(t/734*5))) if t<512 else 0
 env=min(env,q*4 if q<8 else 256-q if q>224 else 31)
 if q in (0,256):alpha=q;env=0
 sx=max(0,min(638,x+(2*env if x<320 else -2*env)))//2*2
 return sx,y,sx,alpha,env,env//4

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);args=ap.parse_args()
 out=args.out.resolve();out.mkdir(parents=True,exist_ok=True)
 rng=random.Random(20261026);vectors=[]
 for f in (6,7):
  for cx,cy in [(0,0),(1279,0),(0,719),(1279,719),(640,360),(200,150),(1000,600)]:
   for p in [0,1,32,64,96,128,160,192,224,255,256]:
    points=[(0,0),(639,0),(0,719),(639,719),(cx//2,cy)]+[(rng.randrange(640),rng.randrange(720)) for _ in range(35)]
    for x,y in points:vectors.append((f,p,cx,cy,x,y,*expected(f,p,x,y,cx,cy)))
 (out/'vectors.txt').write_text(''.join(' '.join(map(str,v))+'\n' for v in vectors),encoding='ascii')
 bench=r'''`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,iv=0;always #5 clk=~clk;
reg[3:0] fx;reg[8:0] p;reg[10:0] cx;reg[9:0] cy,x,y;
wire ov;wire[9:0] a,b,c,ox,oy;wire[8:0] alpha;wire[4:0] shade;wire[2:0] shine;
water_effect_map #(.POINTER_CENTER(1)) d(.clk(clk),.rst(rst),.valid(iv),.enabled(1'b1),.right(1'b0),.effect(fx),
 .progress(p),.ox(x),.oy(y),.wx(x),.wy(y),.out_valid(ov),.old_x(a),.old_y(b),.new_x(c),.out_x(ox),.out_y(oy),
 .alpha(alpha),.shade(shade),.shine(shine),.center_x(cx),.center_y(cy));
integer fd,n,ea,eb,ec,eq,es,eh,cycles,count=0;
initial begin
 repeat(5)@(negedge clk);rst=0;fd=$fopen("vectors.txt","r");
 while(!$feof(fd))begin
  n=$fscanf(fd,"%d %d %d %d %d %d %d %d %d %d %d %d",fx,p,cx,cy,x,y,ea,eb,ec,eq,es,eh);
  if(n==12)begin
   repeat(15)@(negedge clk);iv=1;@(negedge clk);iv=0;cycles=0;
   while(!ov && cycles<20)begin @(negedge clk);cycles=cycles+1;end
   if(!ov || {a,b,c,alpha,shade,shine}!=={ea[9:0],eb[9:0],ec[9:0],eq[8:0],es[4:0],eh[2:0]} || ox!==x || oy!==y)
    $fatal(1,"pointer map case %d fx%0d p%0d center %0d,%0d xy %0d,%0d got %0d %0d %0d %0d %0d %0d expected %0d %0d %0d %0d %0d %0d",count,fx,p,cx,cy,x,y,a,b,c,alpha,shade,shine,ea,eb,ec,eq,es,eh);
   count=count+1;repeat(2)@(negedge clk);
  end
 end
 $display("PASS pointer-centred map cases=%0d: corner origins, signed range, both effects, near-end coverage and exact endpoints",count);$finish;
end
endmodule
'''
 (out/'effects.v').write_text(bench,encoding='ascii')
 files=[out/'effects.v',ROOT/'common/fluid/water_effect_map_base.v',ROOT/'common/fluid/water_priority_map.v']
 iv=ROOT.parents[1]/'.tools/iverilog/bin/iverilog.exe';binary=out/'effects.vvp'
 r=subprocess.run([str(iv),'-g2005','-DWATER_SIM','-DFX11_ROM_ROOT="'+(ROOT/'common/fluid').as_posix()+'/"','-s','tb','-o',str(binary),*map(str,files)],capture_output=True,text=True,cwd=out);log=r.stdout+r.stderr
 if r.returncode==0:r=subprocess.run([str(iv.with_name('vvp.exe')),str(binary)],cwd=out,capture_output=True,text=True,timeout=300);log+=r.stdout+r.stderr
 (out/'effects.log').write_text(log,encoding='utf-8');print(log[-2500:],flush=True)
 passed=r.returncode==0 and 'PASS ' in log and 'FATAL' not in log
 (out/'results.json').write_text(json.dumps({'passed':passed,'cases':len(vectors),'inputs_sha256':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path(__file__),*files]}},indent=2),encoding='utf-8')
 assert passed
if __name__=='__main__':main()
