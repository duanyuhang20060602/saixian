from pathlib import Path
import importlib.util,wave,json
import numpy as np
from quality_model import model
ROOT=Path(__file__).resolve().parents[1]
original=ROOT/'project/src/user_source/hdl_source/python/1.wav'
spec=importlib.util.spec_from_file_location('old',ROOT/'baseline/legacy_pitch/tools/pitch_model.py')
old=importlib.util.module_from_spec(spec);spec.loader.exec_module(old)
with wave.open(str(original),'rb') as f:
    assert (f.getnchannels(),f.getsampwidth(),f.getframerate())==(2,3,48000)
    data=np.frombuffer(f.readframes(144000),dtype=np.uint8).astype(np.int64).reshape(-1,3)
v=data[:,0]|(data[:,1]<<8)|(data[:,2]<<16)
pcm=(((v^0x800000)-0x800000)>>8).reshape(-1,2)
OUT=ROOT/'试听/原工程素材';OUT.mkdir(exist_ok=True)
def save(name,signal):
    with wave.open(str(OUT/name),'wb') as f:
        f.setnchannels(2);f.setsampwidth(2);f.setframerate(48000);f.writeframes(signal.astype('<i2').tobytes())
save('输入.wav',pcm)
rows=[]
for mode in [1,2,3,4]:
    for label,func in [('旧版',old.model),('新版',model)]:
        y=func(pcm,np.full(len(pcm),mode));save(f'F{mode}_{label}.wav',y)
    rows.append(f'<tr><td>F{mode}</td><td><audio controls preload="none" src="试听/原工程素材/F{mode}_旧版.wav"></audio></td><td><audio controls preload="none" src="试听/原工程素材/F{mode}_新版.wav"></audio></td></tr>')
    print(f'PASS original WAV pair F{mode}',flush=True)
html='''<!doctype html><meta charset="utf-8"><title>原工程素材音质对比</title><style>body{font:17px system-ui;margin:40px auto;max-width:1000px;padding:20px;background:#142031;color:white}td,th{padding:14px;text-align:left}audio{width:340px}p{line-height:1.8}</style>
<h1>原工程已有 WAV：旧版 / 新版</h1><p>输入取自原工程 python/1.wav 的前三秒，48 kHz 立体声 24 bit 转 16 bit。未使用下载素材，未分别归一化响度。以下由定点软件模型生成，非实板录音；与当前 TF 卡中的歌曲是否相同，尚未确认。</p>
<p>F1 升4半音，F2 降5半音，F3 原声+7半音，F4 原声+八度。</p><audio controls src="试听/原工程素材/输入.wav"></audio>
<table><tr><th>模式</th><th>旧版</th><th>新版</th></tr>ROWS</table>'''.replace('ROWS',''.join(rows))
(ROOT/'原工程素材对比.html').write_text(html,encoding='utf-8')
(ROOT/'results/existing_audio.json').write_text(json.dumps({'source':str(original),'frames':len(pcm),'input_peak':int(abs(pcm).max()),'hardware_recording':False},indent=2))
print('PASS existing project audio comparison',flush=True)
