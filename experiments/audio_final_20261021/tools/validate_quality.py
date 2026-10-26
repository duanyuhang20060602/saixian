from pathlib import Path
import json,wave,numpy as np
ROOT=Path(__file__).resolve().parents[1]
p=ROOT/'results/quality_metrics.json';s=json.loads(p.read_text())
# The old integer output rounds this heavily suppressed tone to silence.
# State the measurement floor explicitly instead of reporting an arbitrary ratio to zero.
s['measurement_floor_rms_lsb']=1.0
s['old_12khz_below_1lsb']=s['old_12khz_downshift_rms']<1
s['downshift_12khz_gain_change_db']=float(20*np.log10(s['new_12khz_downshift_rms']/max(s['old_12khz_downshift_rms'],1.0)))
p.write_text(json.dumps(s,indent=2))
for row in s['measurements']:
    assert row['matched_resets']>0
    if row['input_hz']==440:assert row['old_rms_ripple_db']>5 and row['new_rms_ripple_db']<.1,row
assert s['downshift_12khz_gain_change_db']>30
q=np.load(ROOT/'results/fir_q15.npy');filters=[]
for mode,ratio in [(1,82570/65536),(3,98193/65536),(4,2)]:
    f=np.linspace(24000/ratio,24000,4096)
    h=np.exp(-2j*np.pi*f[:,None]*np.arange(63)[None,:]/48000)@(q[mode]/32768)
    stop=float(20*np.log10(np.max(abs(h))))
    assert stop<(-40 if mode==4 else -60),(mode,stop)
    assert int(q[mode].sum())==32768
    filters.append({'mode':mode,'first_alias_input_hz':float(f[0]),'worst_stopband_db':stop})
(ROOT/'results/filter_validation.json').write_text(json.dumps(filters,indent=2))
listening=[]
for f in (ROOT/'试听').rglob('*.wav'):
    with wave.open(str(f),'rb') as w:
        assert w.getframerate()==48000 and w.getnchannels()==2 and w.getsampwidth()==2
        assert w.getnframes()==144000
        x=np.frombuffer(w.readframes(w.getnframes()),dtype='<i2')
        assert np.max(abs(x.astype(np.int32)))>100
        listening.append({'file':f.relative_to(ROOT).as_posix(),'peak':int(np.max(abs(x.astype(np.int32)))),
                          'fullscale_samples':int(np.count_nonzero((x==32767)|(x==-32768)))})
(ROOT/'results/listening_file_stats.json').write_text(json.dumps(listening,indent=2,ensure_ascii=False),encoding='utf-8')
print('PASS 440 Hz amplitude modulation thresholds, 12 kHz downshift bandwidth, FIR alias stopbands, all listening WAV formats/counts/non-silence')
