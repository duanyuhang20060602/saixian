"""Reproducible audio-port acceptance: real DSP vectors and both SPI clocks."""
from pathlib import Path
import argparse,json,math,re,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'tests/results';OUT.mkdir(exist_ok=True)
IV=Path('C:/Users/MR.HUSKY/Desktop/qian/.tools/iverilog/bin/iverilog.exe')
jobs={
 'tb_audio_repair_settings':['common/photo_unified_settings_controller.v'],
 'tb_audio_visual_real':['common/audio_ui/saixian_audio_visualizer.v'],
 'tb_audio_transport_repair':['common/photo_audio_link.v','common/photo_audio_features.v','common/audio_ui/saixian_audio_repair.v','common/audio_ui/photo_audio_cue_samples.v'],
 'tb_audio_repair_effect':['common/audio_ui/saixian_audio_repair.v'],
 'tb_audio_visual_primitive':['tests/tb_audio_visual_real.v','tests/av_bram_model.v','common/audio_ui/saixian_audio_visualizer.v'],
 'tb_audio_osd_port':['common/audio_ui/saixian_osd_overlay.v'],
}
p=argparse.ArgumentParser();p.add_argument('--only',nargs='+',choices=jobs);args=p.parse_args()
report=OUT/'audio_port_results.json'
results=json.loads(report.read_text()) if report.exists() else []
for name,sources in jobs.items():
 if args.only and name not in args.only:continue
 start=time.monotonic();binary=OUT/(name+'.vvp')
 if name=='tb_audio_visual_primitive':
  for rom in ['saixian_av_hann_half.hex','saixian_av_twiddle_serial.hex']:
   words=[int(w,16) for w in (ROOT/'common/audio_ui'/rom).read_text().split()]
   mif=(ROOT/'common/audio_ui'/(rom+'_0_0.mif')).read_text()
   actual={int(a,16):int(v,16) for a,v in re.findall(r'(?m)^\s*([0-9a-fA-F]+)\s*:\s*([0-9a-fA-F]+);',mif)}
   assert len(words)==512 and all(actual[i]==word for i,word in enumerate(words)),'ROM MIF/HEX mismatch'
 sim_flags=[] if name=='tb_audio_visual_primitive' else ['-DVICTORY_SIM']
 subprocess.run([str(IV),'-g2012',*sim_flags,'-s',name,'-o',str(binary),'tests/'+name+'.v',*sources],cwd=ROOT,check=True)
 with (OUT/(name+'.log')).open('w',encoding='utf-8') as log:
  r=subprocess.run([str(IV.with_name('vvp.exe')),str(binary)],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,timeout=900)
 text=(OUT/(name+'.log')).read_text();print(text,flush=True)
 passed=r.returncode==0 and 'PASS' in text and 'FATAL' not in text
 result=dict(test=name,passed=passed,seconds=round(time.monotonic()-start,2))
 if passed and name=='tb_audio_repair_effect':
  samples=[tuple(map(int,s.split())) for s in (OUT/'repair_effect.txt').read_text().splitlines()]
  assert len(samples)==8192
  reference=OUT/'repair_effect_reference.txt'
  assert reference.exists(),'Original single-board output vectors are required'
  original=[tuple(map(int,s.split())) for s in reference.read_text().splitlines()]
  assert samples==original,'Pipelined repair differs from original single-board output'
  def rms(lo,hi,ch):return math.sqrt(sum(s[ch]**2 for s in samples[lo:hi])/(hi-lo))
  dry_l,dry_r=rms(512,1024,1),rms(512,1024,2)
  wet_l,wet_r=rms(2560,3072,1),rms(2560,3072,2)
  gain_1k=20*math.log10(wet_l/dry_l);gain_8k=20*math.log10(max(wet_r,1)/dry_r)
  impulse_peak=max(abs(s[1]) for s in samples[3550:3750])
  dc_tail=max(abs(sum(s[ch] for s in samples[-256:])/256) for ch in [1,2])
  assert -1<gain_1k<1,(gain_1k,'passband')
  assert gain_8k < -35,(gain_8k,'stopband')
  assert impulse_peak<3000,(impulse_peak,'declick')
  assert dc_tail<1800,(dc_tail,'DC suppression')
  result['measurements']={'bit_exact_original_samples':len(samples),'gain_1k_db':round(gain_1k,2),'gain_8k_db':round(gain_8k,2),'isolated_click_output_peak':impulse_peak,'dc_tail_absolute':round(dc_tail,1)}
  print(result['measurements'],flush=True)
 if report.exists():results=json.loads(report.read_text())
 results=[v for v in results if v['test']!=name]+[result]
 report.write_text(json.dumps(results,indent=2)+'\n')
 if not passed:raise SystemExit(1)
