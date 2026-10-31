"""Compare the original and retimed shading pipeline at every clock, without changing datapath RTL."""
from pathlib import Path
import argparse,hashlib,json,subprocess,time
ROOT=Path(__file__).resolve().parents[1];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 import os
 temp=Path("E:/Codex/Temp/saixian-resource-save-20261024");temp.mkdir(parents=True,exist_ok=True)
 os.environ.update(TEMP=str(temp),TMP=str(temp),TMPDIR=str(temp))
 ap=argparse.ArgumentParser();ap.add_argument('--baseline',type=Path,required=True);ap.add_argument('--out',type=Path,required=True);args=ap.parse_args()
 out=args.out.resolve();out.mkdir(parents=True,exist_ok=True);start=time.monotonic()
 previous=args.baseline/'common/photo_relief_player.v';current=ROOT/'common/photo_relief_player.v';before=previous.read_text(encoding='utf-8');after=current.read_text(encoding='utf-8')
 assert before[before.index('module photo_relief_product'):]==after[after.index('module photo_relief_product'):]
 wrapper='(input clk,rst,input[15:0] surface,base_color,input cup,input[15:0] bg2,input signed[5:0] light_x,light_y,output[23:0] rgb_out);\n'
 extract=lambda s:s[s.index('function [23:0] expand'):s.index('endmodule')]
 model=out/'pipeline_comparison.v';model.write_text('module shader_before'+wrapper+extract(before)+'endmodule\nmodule shader_after'+wrapper+extract(after)+'endmodule\n',encoding='utf-8')
 tb=ROOT/'tests/tb_relief_pipeline_equivalence.v';files=[tb,model,current]
 evidence=files+[Path(__file__),previous];hashes={p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p):sha(p) for p in evidence}
 binary=out/'pipeline.vvp';run=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-DRELIEF_SIM','-s','tb','-o',str(binary),*map(str,files)],cwd=out,capture_output=True,text=True);log=run.stdout+run.stderr
 if run.returncode==0:
  run=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=out,capture_output=True,text=True,timeout=300);log+=run.stdout+run.stderr
 path=out/'relief_pipeline_equivalence.log';path.write_text(log,encoding='utf-8');unchanged=all(sha(p)==hashes[p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p)] for p in evidence)
 passed=run.returncode==0 and 'PASS relief_pipeline_equivalence' in log and unchanged
 record=dict(test='relief_pipeline_equivalence',passed=passed,inputs_unchanged=unchanged,inputs_sha256=hashes,seconds=round(time.monotonic()-start,2),log=str(path),log_sha256=sha(path))
 (out/'results.json').write_text(json.dumps([record],indent=2)+'\n',encoding='utf-8');print(log,flush=True)
 if not passed:raise SystemExit(1)
if __name__=='__main__':main()
