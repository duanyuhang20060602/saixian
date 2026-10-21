from pathlib import Path
import subprocess,os
ROOT=Path(__file__).resolve().parents[1]
PROJECT=ROOT/'project';HDL=PROJECT/'src/user_source/hdl_source';OUT=ROOT/'results'
BIN=Path('D:/qiansai/.tools/iverilog-portable/ucrt64/bin')
os.environ['PATH']=str(BIN)+os.pathsep+os.environ.get('PATH','')
def run(top,sources,missing=False,defines=('VICTORY_SIM',)):
    exe=OUT/f'{top}.vvp';exe.unlink(missing_ok=True)
    args=[str(BIN/'iverilog.exe'),'-g2012','-s',top,'-o',str(exe),*[f'-D{x}' for x in defines],*[str(p) for p in sources]]
    if missing:args.insert(1,'-i')
    cp=subprocess.run(args,cwd=PROJECT,text=True,capture_output=True)
    (OUT/f'{top}_compile.log').write_text(cp.stdout+cp.stderr)
    assert 'error:' not in cp.stderr.lower() and exe.exists() and exe.stat().st_size>100,cp.stdout+cp.stderr
    if cp.returncode:print(f'NOTE {top}: Icarus teardown exit {cp.returncode}, executing fresh VVP',flush=True)
    log_path=OUT/f'{top}.log'
    with log_path.open('w',encoding='utf-8') as log:
        cp=subprocess.run([str(BIN/'vvp.exe'),str(exe)],cwd=PROJECT,text=True,stdout=log,stderr=subprocess.STDOUT,timeout=360)
    text=log_path.read_text(encoding='utf-8')
    assert cp.returncode==0 and 'PASS' in text and 'ERROR:' not in text,text
    print(text,flush=True)
