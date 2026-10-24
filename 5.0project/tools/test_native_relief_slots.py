"""Check production frame-store CDC and SDRAM slot bounds; controller ports are shells."""
from pathlib import Path
import argparse,hashlib,json,os,re,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);a=ap.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
 env=os.environ.copy();env.update(TEMP=str(out),TMP=str(out),TMPDIR=str(out));hashes={};logs=[];started=time.monotonic()
 for board in 'ab':
  store=ROOT/f'src/board_{board}/user_source/hdl_source/frame_store.v';rw=store.parent/'SD/frame_read_write.v'
  sources=[rw,ROOT/'common/photo_award_memory.v',ROOT/'common/photo_thumbnail.v']
  allv=list(store.parent.rglob('*.v'));sdram=next(p for p in allv if re.search(r'\bmodule\s+sdram\b',p.read_text(encoding='utf-8',errors='replace')));sources.append(sdram)
  shells=[]
  for name in (['frame_read_write','photo_award_memory','photo_thumbnail_memory','sdram'] if board=='a' else ['frame_read_write','sdram']):
   src=next(p for p in sources if re.search(r'\bmodule\s+'+name+r'\b',p.read_text(encoding='utf-8',errors='replace')))
   raw=src.read_text(encoding='utf-8',errors='replace');raw=re.sub(r'/\*.*?\*/','',raw,flags=re.S);raw=re.sub(r'//[^\n]*','',raw)
   header=re.search(r'\bmodule\s+'+name+r'\b.*?\);',raw,re.S)[0];shells.append(header+'\nendmodule\n')
  shell=out/f'shells_{board}.v';shell.write_text('`define ADDR_WIDTH 21\n`define DM_WIDTH 4\n`define DATA_WIDTH 32\n'+'\n'.join(shells),encoding='utf-8')
  ports='.write_relief(wr),.write_award(wa),.read_award(ra),.write_slot(slot),.read_slot(slot),.mem_clk(clk),.rst(rst)'
  ports+=',.read_relief(rr)' if board=='b' else ',.write_fluid(fluid)'
  expectedread='rr ? 985088:ra ? 691200:460800' if board=='b' else '460800'
  expectedwrite='wr ? 985088:wa || fluid ? 691200:460800' if board=='a' else 'wr ? 985088:wa ? 691200:460800'
  tb='''`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,wr=0,rr=0,wa=0,ra=0,fluid=0;reg[1:0]slot=0;always #10 clk=~clk;
frame_store dut('''+ports+''');
integer m,i,rlen,wlen,checks=0;reg[20:0]old_len;
initial begin
 repeat(3)@(negedge clk);rst=0;
 for(m=0;m<32;m=m+1)begin
  @(negedge clk);old_len=dut.rw.write_len;{wr,rr,wa,ra,fluid}=m;
  @(posedge clk);#1;if(dut.rw.write_len!==old_len)$fatal(1,"mode bypassed first CDC stage");
  @(posedge clk);#1;wlen='''+expectedwrite+''';rlen='''+expectedread+''';
  if(dut.rw.write_len!==wlen || dut.rw.read_len!==rlen)$fatal(1,"length mismatch mask=%0d got=%d/%d expected=%d/%d",m,dut.rw.write_len,dut.rw.read_len,wlen,rlen);
  for(i=0;i<2;i=i+1)begin
   @(negedge clk);slot=i;repeat(3)@(posedge clk);#1;
   if(dut.rw.read_addr_0!==0 || dut.rw.write_addr_0!==0 || dut.rw.read_addr_1!==1048576 || dut.rw.write_addr_1!==1048576)$fatal(1,"slot map mismatch");
   if((i*1048576+wlen)>((i+1)*1048576) || (i*1048576+rlen)>2097152)$fatal(1,"SDRAM bounds exceeded");
   '''+('if(dut.light_base!==(i*1048576+460800))$fatal(1,"material tail base mismatch");' if board=='a' else '')+'''
   checks=checks+1;
  end
 end
 $display("PASS production frame-store native slot/length CDC: 32 mode masks, both 4MiB slots, 8MiB bounds, two-clock synchronization checks=%0d",checks);$finish;
end
endmodule
'''
  fixture=out/f'tb_{board}.v';fixture.write_text(tb,encoding='utf-8');evidence=[store,*sources,shell,fixture,Path(__file__)];hashes.update({p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p):sha(p) for p in evidence})
  binary=out/f'{board}.vvp';p=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-s','tb','-o',str(binary),str(store),str(shell),str(fixture)],cwd=out,env=env,capture_output=True,text=True);log=p.stdout+p.stderr
  if p.returncode==0:
   p=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=out,env=env,capture_output=True,text=True,timeout=60);log+=p.stdout+p.stderr
  print(board,log,flush=True);assert p.returncode==0 and 'PASS ' in log and not re.search(r'(?im)^(ERROR:|FATAL:)',log);logs.append(log)
 unchanged=all(sha(Path(k) if Path(k).is_absolute() else ROOT/k)==h for k,h in hashes.items());assert unchanged
 log=out/'native_slots.log';log.write_text('\n'.join(logs),encoding='utf-8');r=dict(test='native_slots',passed=True,inputs_unchanged=True,inputs_sha256=hashes,seconds=round(time.monotonic()-started,2),log=str(log),log_sha256=sha(log),scope='Production A/B frame_store RTL with original-width controller port shells. Checks length selection, two-stage mode CDC and slot bounds; not SDRAM electrical simulation. Full link and real frame-FIFO pressure are separate tests.')
 (out/'results.json').write_text(json.dumps([r],indent=2)+'\n',encoding='utf-8')
if __name__=='__main__':main()
