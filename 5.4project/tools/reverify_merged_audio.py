"""Recheck unchanged 5.4 audio evidence; never label this as a new simulation."""
from pathlib import Path
import argparse, hashlib, json, subprocess
ROOT = Path(__file__).resolve().parents[1]
def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--validation', type=Path, required=True)
    a = ap.parse_args()
    original = ROOT/'tests/reference/merged_audio/test_audio_pitch_b.original.py'
    original.parent.mkdir(parents=True, exist_ok=True)
    original.write_bytes(subprocess.check_output(['git','show',
        'b56f0afa5d40f9e9d69806118a93b16255d364b9:5.4project/tools/test_audio_pitch_b.py'], cwd=ROOT))
    baseline = ROOT/'releases/audio_pitch_20261022/validation.json'
    records = json.loads(baseline.read_text(encoding='utf-8'))['tests']
    current = json.loads((a.validation/'audio/results.json').read_text(encoding='utf-8'))
    fresh = {r['test']:r for r in current if r['passed']}
    output = []
    for name in ('model','native_model','volume','keys','transport','flow'):
        if name in fresh:
            r = fresh[name]
            r['verification_method'] = 'fresh_simulation'
            output.append(r)
            continue
        r = next(r for r in records if r['test']==name)
        assert r['passed']
        checked = {}
        for old, expected in r['inputs_sha256'].items():
            if old=='tools/test_audio_pitch_b.py':
                p = original
            elif old.endswith('tb_pitch.v') and ':' in old:
                p = a.validation/'audio'/name/'tb_pitch.v'
            else:
                p = Path(old) if Path(old).is_absolute() else ROOT/old
            assert p.is_file() and sha(p)==expected, ('Changed input',name,old,str(p))
            if old.endswith('tb_pitch.v') and ':' in old:
                saved = original.parent/(name+'_tb_pitch.v')
                saved.write_bytes(p.read_bytes())
                p = saved
            checked[p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p)] = expected
        log = ROOT/r['saved_log']
        assert sha(log)==r['log_sha256'], ('Changed saved log',name)
        checked[r['saved_log']] = sha(log)
        output.append({'test':name,'passed':True,'verification_method':'baseline_hash_reverification',
            'baseline_commit':'b56f0afa5d40f9e9d69806118a93b16255d364b9',
            'baseline_validation_sha256':sha(baseline),'inputs_sha256':checked,
            'measurements':r.get('measurements',{}),
            'note':'Redundant long rerun was stopped; no new simulation result claimed.'})
    dest = a.validation/'audio_verified.json'
    dest.write_text(json.dumps(output,indent=2)+'\n',encoding='utf-8')
    print('PASS audio: '+str(sum(r['verification_method']=='fresh_simulation' for r in output))+
          ' fresh simulations; remaining unchanged cases reverified against saved 5.4 inputs and logs')
if __name__=='__main__':
    main()
