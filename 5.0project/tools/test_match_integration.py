# Behavioral and real-UART regressions for the integrated match mode.
from pathlib import Path
import argparse,concurrent.futures,hashlib,json,shutil,subprocess
ROOT=Path(__file__).resolve().parents[1]
HDL=ROOT/'common/match'
IV='C:/iverilog/bin/iverilog.exe'
VVP='C:/iverilog/bin/vvp.exe'

def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True)
 ap.add_argument('--only',nargs='+',choices=['control','keys','numbers','serial','render'])
 ap.add_argument('--reuse',action='store_true');args=ap.parse_args()
 out=args.out.resolve();out.mkdir(parents=True,exist_ok=True)
 prior={r['test']:r for r in json.loads((out/'results.json').read_text())} if args.reuse and (out/'results.json').exists() else {}
 jobs=args.only or ['control','keys','numbers','serial','render']
 def run(name):
  directory=out/name;directory.mkdir(exist_ok=True)
  extra=[]
  if name in ('control','keys','render'):
   original=ROOT/f'tests/tb_match_original_{name}.v'
   body=original.read_text()
   if name=='control':
    body=body.replace('match_control #','photo_match_control #').replace('sec,dur,cd,cue);',"sec,dur,cd,cue,1'b0,4'd0,10'd0);")
    sources=[HDL/'photo_match_control.v']
   elif name=='keys':
    body=body.replace('module tb_match_keys;','module tb_match_keys;wire[3:0] synchronized_n,pressed_key;')
    body=body.replace('match_keys #','photo_match_keys #').replace('key_scene,s,l);','key_scene,s,l,synchronized_n,pressed_key);')
    sources=[HDL/'photo_match_control.v']
   else:
    body=body.replace('match_render d(','photo_match_render d(')
    body=body.replace('integer file,index', '''wire[23:0] reference_rgb;wire reference_de,reference_vs;
match_render_ref reference(clk,rst,ft,de,vs,x,y,state,ta,tb,a,b,sec,cd,dur,reference_rgb,reference_de,reference_vs);
reg[23:0] ref_rgb_q;reg ref_de_q,ref_vs_q;
always @(posedge clk)begin ref_rgb_q<=reference_rgb;ref_de_q<=reference_de;ref_vs_q<=reference_vs;end
always @(negedge clk)
 if(!rst && (od!==ref_de_q || ov!==ref_vs_q || (od && rgb!==ref_rgb_q)))
  $fatal(1,"standalone render changed pixel at x=%d y=%d got=%h expected=%h",x,y,rgb,ref_rgb_q);
integer file,index''')
    body=body.replace('reg [2:0] dp=0,vp=0;', 'reg [3:0] dp=0,vp=0;')
    body=body.replace('dp[1:0]','dp[2:0]').replace('vp[1:0]','vp[2:0]')
    body=body.replace('od!==dp[2] || ov!==vp[2]','od!==dp[3] || ov!==vp[3]')
    body=body.replace('repeat(4)pixel','repeat(8)pixel')
    ref=directory/'reference_render.v';ref.write_text((ROOT/'tests/reference/match_single/match_render.v').read_text().replace('module match_render(','module match_render_ref(',1))
    sources=[HDL/'photo_match_render.v',HDL/'photo_match_numbers.v',HDL/'photo_match_font.v',HDL/'photo_match_text_query.v',HDL/'photo_match_columns.v',ref]
    shutil.copy2(ROOT/'tests/reference/match_single/match_font.hex',directory/'match_font.hex')
    shutil.copy2(HDL/'photo_match_font.hex',directory/'photo_match_font.hex')
    shutil.copy2(HDL/'photo_match_columns.hex',directory/'photo_match_columns.hex')
    extra=[ROOT/'tests/reference/match_single/match_render.v',ROOT/'tests/reference/match_single/match_text.vh',
           ROOT/'tests/reference/match_single/match_font.hex',HDL/'photo_match_text.vh',HDL/'photo_match_font.hex',
           directory/'match_font.hex',directory/'photo_match_font.hex',HDL/'photo_match_columns.hex',directory/'photo_match_columns.hex']
   bench=directory/(name+'.v');bench.write_text(body)
   evidence=[original]
   top='tb_match_'+name
  else:
   bench=ROOT/f'tests/tb_match_{name}.v';evidence=[];top='tb'
   sources=[HDL/'photo_match_numbers.v'] if name=='numbers' else [
    ROOT/'common/saixian_hmi_uart.v',HDL/'photo_match_serial.v',HDL/'photo_match_manager.v',HDL/'photo_match_control.v']
  paths=[bench,*sources];hashes={str(q):digest(q) for q in [Path(__file__),*evidence,*paths,*extra]}
  if args.reuse and prior.get(name,{}).get('passed') and prior[name].get('source_sha256')==hashes:
   print('REUSE '+name,flush=True);return prior[name]
  binary=directory/'run.vvp';log=directory/'run.log'
  build=subprocess.run([IV,'-g2012','-DMATCH_SIM','-I'+str(HDL),'-I'+str(ROOT/'tests/reference/match_single'),
     '-s',top,'-o',str(binary),*map(str,paths)],capture_output=True,text=True)
  with log.open('w',encoding='utf-8') as output:
   output.write(build.stdout+build.stderr);output.flush()
   result=subprocess.run([VVP,'-i',str(binary)],cwd=directory,stdout=output,stderr=subprocess.STDOUT,timeout=900) if build.returncode==0 else build
  text=log.read_text(encoding='utf-8');passed=result.returncode==0 and 'PASS' in text and 'FATAL' not in text
  assert all(digest(Path(q))==sha for q,sha in hashes.items()),'Inputs changed during test'
  record=dict(test=name,passed=passed,source_sha256=hashes,log=str(log),log_sha256=digest(log))
  print(name+': '+text[-3000:],flush=True)
  return record
 with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:records=list(pool.map(run,jobs))
 (out/'results.json').write_text(json.dumps(records,indent=2)+'\n')
 assert all(r['passed'] for r in records)

if __name__=='__main__':main()
