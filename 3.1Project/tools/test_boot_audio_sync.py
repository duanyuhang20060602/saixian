from pathlib import Path
import hashlib,json,subprocess,time
R=Path(__file__).resolve().parents[1];O=R/'tests/results';O.mkdir(exist_ok=True)
IV=Path('C:/Users/MR.HUSKY/Desktop/qian/.tools/iverilog/bin/iverilog.exe')
sources=['tests/tb_boot_audio_sync.v','common/photo_boot_screen.v','common/photo_audio_link.v','common/photo_audio_features.v','common/audio_ui/saixian_audio_repair.v','common/audio_ui/photo_audio_cue_samples.v']
start=time.monotonic();binary=O/'tb_boot_audio_sync.vvp'
subprocess.run([str(IV),'-g2012','-DVICTORY_SIM','-s','tb_boot_audio_sync','-o',str(binary),*sources],cwd=R,check=True)
with (O/'tb_boot_audio_sync.log').open('w') as f:r=subprocess.run([str(IV.with_name('vvp.exe')),str(binary)],cwd=R,stdout=f,stderr=subprocess.STDOUT,timeout=600)
text=(O/'tb_boot_audio_sync.log').read_text();print(text,flush=True)
passed=r.returncode==0 and 'PASS' in text and 'FATAL' not in text
result={'test':'tb_boot_audio_sync','passed':passed,'seconds':round(time.monotonic()-start,2),'source_sha256':{n:hashlib.sha256((R/n).read_bytes()).hexdigest() for n in sources}}
(O/'boot_audio_sync_results.json').write_text(json.dumps(result,indent=2)+'\n')
if not passed:raise SystemExit(1)
