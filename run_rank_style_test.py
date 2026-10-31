from pathlib import Path
import subprocess,os,json,hashlib
root=Path.cwd();out=root/'validation-rank-style';out.mkdir(exist_ok=True)
names=['tests/tb_rank_style.v','tests/before_battle.v','tests/rank_style_ram_model.v','tests/rank_style_update.hex','tests/rank_style_expected_score.hex','common/photo_rank_text.v','common/saixian_battle_result_fx_pipelined.v','common/rank_names.mif','common/rank_names.hex','common/rank_digits.mif','common/rank_digits.hex']
files=[root/'5.0project'/n for n in names];hashes={str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in files};iv=(root/'../.tools/msys2-sim/ucrt64/bin/iverilog.exe').resolve();env=dict(os.environ);env['PATH']=str(iv.parent)+os.pathsep+env['PATH']
rtl=[p for p in files if p.suffix=='.v'];binary=out/'full.vvp';p=subprocess.run([str(iv),'-g2012','-DVICTORY_SIM','-s','tb','-o',str(binary),*map(str,rtl)],env=env,capture_output=True,text=True);log=p.stdout+p.stderr
if p.returncode==0:p=subprocess.run([str(iv.with_name('vvp.exe')),str(binary),'+out='+str(out/'frame.hex')],cwd=root/'5.0project',env=env,capture_output=True,text=True,timeout=180);log+=p.stdout+p.stderr
(out/'full.log').write_text(log);passed=p.returncode==0 and 'PASS full-frame style' in log
assert hashes=={str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in files}
(out/'result.json').write_text(json.dumps({'passed':passed,'inputs_sha256':hashes},indent=2));print(log);assert passed
from PIL import Image
v=[int(x,16) for x in (out/'frame.hex').read_text().split()];im=Image.new('RGB',(1280,720));im.putdata([(x>>16,(x>>8)&255,x&255) for x in v]);im.save(out/'preview.png')
