from pathlib import Path
import os,subprocess,json,time,argparse,hashlib
from PIL import Image,ImageOps,ImageDraw
ROOT=Path(__file__).resolve().parents[1];HDL=ROOT/'project/src/user_source/hdl_source'
OUT=ROOT/'results/tests';OUT.mkdir(parents=True,exist_ok=True)
BIN=Path('D:/qiansai/.tools/iverilog-portable/ucrt64/bin')
env=os.environ.copy();env['PATH']=str(BIN)+os.pathsep+env.get('PATH','')
env['TEMP']=env['TMP']=str(ROOT/'results/tmp');Path(env['TEMP']).mkdir(exist_ok=True)
(OUT/'match_font.hex').write_bytes((HDL/'match_font.hex').read_bytes())
for i in range(9):(OUT/f'trophy_{i}.hex').write_bytes((HDL/f'trophy_{i}.hex').read_bytes())
(OUT/'trophy_expected.hex').write_bytes((ROOT/'results/trophy_expected.hex').read_bytes())
parser=argparse.ArgumentParser();parser.add_argument('--only',nargs='*');args=parser.parse_args()
results=[]
for name,sources in [('control',['match_control.v']),('keys',['match_control.v']),('flow',['match_control.v','event_flow.v']),('trophy',['event_trophy_rom.v']),('render',['match_render.v','event_trophy_rom.v']),('axis',['match_render.v','event_trophy_rom.v','video_rgb_to_axis_640x480.v']),('cues',['saixian_audio_cue.v'])]:
 if args.only and name not in args.only:
  log=OUT/(name+'.txt');assert log.is_file() and 'PASS' in log.read_text() and 'FATAL' not in log.read_text(),name
  results.append({'test':name,'passed':True,'prior_run_log_sha256':hashlib.sha256(log.read_bytes()).hexdigest()});continue
 start=time.time();target=OUT/(name+'.vvp');target.unlink(missing_ok=True)
 top=('tb_event_'+name) if name in ['flow','trophy'] else 'tb_match_'+name
 cmd=[str(BIN/'iverilog.exe'),'-g2012','-DMATCH_SIM','-I',str(HDL),'-s',top,'-o',str(target),str(ROOT/f'tests/{top}.v'),*[str(HDL/p) for p in sources]]
 c=subprocess.run(cmd,cwd=OUT,env=env,capture_output=True,text=True)
 (OUT/(name+'_compile.txt')).write_text(c.stdout+c.stderr)
 if c.returncode!=0:raise RuntimeError(f'{name} compile {c.returncode}: {c.stderr}')
 r=subprocess.run([str(BIN/'vvp.exe'),str(target)],cwd=OUT,env=env,capture_output=True,text=True)
 (OUT/(name+'.txt')).write_text(r.stdout+r.stderr)
 if r.returncode!=0 or 'PASS' not in r.stdout:raise RuntimeError(r.stdout+r.stderr)
 print(r.stdout,flush=True);results.append({'test':name,'passed':True,'seconds':round(time.time()-start,2)})
for p in OUT.glob('*.ppm'):
 im=Image.open(p);assert im.size==(1280,720);im.save(OUT/(p.stem+'.png'))
scenes=['home','teams','schedule','no_result','setup','countdown','running','paused','winner_a','summary','last_result','tie']
sheet=Image.new('RGB',(1280,6*382),'#111827');draw=ImageDraw.Draw(sheet)
for i,name in enumerate(scenes):
 pos=((i%2)*640,(i//2)*382);sheet.paste(Image.open(OUT/(name+'.png')).resize((640,360)),pos)
 draw.text((pos[0]+8,pos[1]+363),name,fill='white')
sheet.save(ROOT/'results/rtl_preview.png')
(ROOT/'results/tests.json').write_text(json.dumps(results,indent=2))
print('PASS all tests and RTL preview',flush=True)
