from pathlib import Path
import importlib.util,json,wave,time
import numpy as np
from quality_model import model,RATIOS
ROOT=Path(__file__).resolve().parents[1]
old_path=ROOT/'baseline/legacy_pitch/tools/pitch_model.py'
spec=importlib.util.spec_from_file_location('legacy_pitch',old_path)
old=importlib.util.module_from_spec(spec);spec.loader.exec_module(old)
OUT=ROOT/'试听';OUT.mkdir(exist_ok=True)

def wav(path,pcm):
    with wave.open(str(path),'wb') as f:
        f.setnchannels(2);f.setsampwidth(2);f.setframerate(48000)
        f.writeframes(np.clip(pcm,-32768,32767).astype('<i2').tobytes())

def envelope(y,target):
    # RMS measured over about eight cycles; independent of overlap/grain boundaries.
    size=int(round(8*48000/target));size=max(32,size)
    blocks=y[:len(y)//size*size].reshape(-1,size)
    rms=np.sqrt(np.mean(blocks.astype(float)**2,axis=1))
    return float(20*np.log10(max(rms.max(),1)/max(rms.min(),1)))

stats={'hardware_recording':False,'measurements':[]}
for freq in [110,440,997]:
    n=np.arange(48000);s=np.rint(14000*np.sin(2*np.pi*freq*n/48000)).astype(np.int64)
    source=np.column_stack([s,s])
    for mode in [1,2,4]:
        diag={};new=model(source,np.full(len(s),mode),diagnostics=diag)
        legacy=old.model(source,np.full(len(s),mode))
        # For harmony, remove the known delayed dry half before measuring the wet voice.
        wet_new=new[:,0].copy();wet_old=legacy[:,0].copy()
        if mode>=3:
            wet_new[1183:]=2*wet_new[1183:]-s[:-1183]
            wet_old[1119:]=2*wet_old[1119:]-s[:-1119]
        target=freq*RATIOS[mode]/65536
        row={'input_hz':freq,'mode':mode,'target_hz':target,
             'old_rms_ripple_db':envelope(wet_old[12000:],target),
             'new_rms_ripple_db':envelope(wet_new[12000:],target),
             'matched_resets':len(diag['alignment_updates'])}
        stats['measurements'].append(row);print(json.dumps(row),flush=True)

# Real bandwidth test: a 12 kHz input shifted down should still be audible at ~9 kHz.
n=np.arange(24000);source=np.tile(np.rint(14000*np.sin(2*np.pi*12000*n/48000)).astype(np.int64)[:,None],(1,2))
for name,func in [('old',old.model),('new',model)]:
    y=func(source,np.full(len(source),2))[6000:,0]
    stats[name+'_12khz_downshift_rms']=float(np.sqrt(np.mean(y.astype(float)**2)))
stats['old_12khz_below_1lsb']=stats['old_12khz_downshift_rms']<1
stats['downshift_12khz_gain_change_db']=20*np.log10(stats['new_12khz_downshift_rms']/max(stats['old_12khz_downshift_rms'],1.0))
stats['measurement_floor_rms_lsb']=1.0
for row in stats['measurements']:
    if row['input_hz']==440:
        assert row['old_rms_ripple_db']>5 and row['new_rms_ripple_db']<.1,row
    assert row['matched_resets']>0,row
assert stats['downshift_12khz_gain_change_db']>30,stats

# Richer, identical deterministic input: bass, bright harmonic tones, stereo and attacks.
fs=48000;n=np.arange(fs*3);t=n/fs
notes=np.array([220,261.625565,293.664768,349.228231,329.627557,261.625565])
freq=notes[np.minimum((t/.5).astype(int),5)];phase=2*np.pi*np.cumsum(freq)/fs
env=np.minimum(1,np.minimum((t%.5)/.005,(.5-t%.5)/.03))
left=sum(.8**(k-1)*np.sin(k*phase)/k for k in range(1,25))*env
right=sum(.8**(k-1)*np.sin(k*phase+.15*k)/k for k in range(1,25))*env
click=(np.exp(-(t%.25)*220)*np.sin(2*np.pi*6800*t))
source=np.rint(np.column_stack([left+.20*click,right+.15*click])*11000).astype(np.int64)
wav(OUT/'输入_明亮乐句.wav',source)
names=['原声','升4半音','降5半音','原声加7半音','原声加八度']
for mode,name in enumerate(names):
    for label,func in [('旧版',old.model),('新版',model)]:
        y=func(source,np.full(len(source),mode))
        wav(OUT/f'{mode}_{label}_{name}.wav',y)
    print(f'PASS same-input listening pair: {name}',flush=True)
(ROOT/'results/quality_metrics.json').write_text(json.dumps(stats,indent=2),encoding='utf-8')
rows=''.join(f'<tr><td>{i} {name}</td><td><audio controls preload="none" src="试听/{i}_旧版_{name}.wav"></audio></td><td><audio controls preload="none" src="试听/{i}_新版_{name}.wav"></audio></td></tr>' for i,name in enumerate(names))
html='''<!doctype html><meta charset="utf-8"><title>赛显音质优化对比</title>
<style>body{max-width:1050px;margin:40px auto;padding:20px;background:#142031;color:#eee;font:17px system-ui}p{line-height:1.8}td,th{padding:14px;text-align:left;border-bottom:1px solid #456}audio{width:340px}small{color:#ccc}</style>
<h1>同一素材：旧版 / 优化版</h1><p>48 kHz 立体声软件定点模型生成，非实板录音。两个版本使用完全相同的输入，未单独做响度归一化；F0 可检查素材本身。启动缓冲和固定延迟略有不同。</p>
<p>新版：按倍率滤波、四点三次插值、短平滑拼接、静音读头波形匹配。复杂混音和低音仍可能有颗粒感，最终请用自己的 TF 音乐上板试听。</p>
<table><tr><th>模式</th><th>旧版</th><th>新版</th></tr>ROWS</table>
<p>KEY2 短按切换 F0–F4，长按恢复原声。SW0 和 KEY3 沿用上一版。</p>'''.replace('ROWS',rows)
(ROOT/'音质优化对比.html').write_text(html,encoding='utf-8')
print('PASS listening pairs and independent envelope / bandwidth measurements',flush=True)
