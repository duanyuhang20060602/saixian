"""Publish an isolated routed photo candidate without overwriting stable releases."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import sys
import zipfile

root = Path(__file__).resolve().parents[1]
build = Path(sys.argv[1]).resolve()
td = build/'src/td_project'
work = Path('E:/Codex/Work/saixian_photo')
before = work/'before/src/user_source'
live = root/'src/user_source'
snapshot = build/'src/user_source'
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest().upper()
files = sorted(p for p in live.rglob('*') if p.is_file())
paths = {p.relative_to(live) for p in files}
assert paths == {p.relative_to(snapshot) for p in snapshot.rglob('*') if p.is_file()}
assert paths == {p.relative_to(before) for p in before.rglob('*') if p.is_file()}
for p in files:
    assert digest(p) == digest(snapshot/p.relative_to(live)), f'Build mismatch: {p}'
changed = [p.relative_to(live).as_posix() for p in files if digest(p) != digest(before/p.relative_to(live))]
assert changed == ['hdl_source/top_tf_hdmi_audio.v'], changed
old = (before/changed[0]).read_text(encoding='utf-8-sig')
expected = old.replace('saixian_adaptive_enhance u_enhance(', 'saixian_adaptive_enhance #(.PHOTO_SMOOTH(1)) u_enhance(')
expected = expected.replace('parameter integer WIDTH=1280, SPLIT_X=640', 'parameter integer WIDTH=1280, SPLIT_X=640, PHOTO_SMOOTH=0')
expected = expected.replace('    if(detail>=-3 && detail<=3) detail_term=0;', '''    if(PHOTO_SMOOTH && strength==1) begin
        // Range-gated neighbours have already rejected strong edges.
        // Blend halfway toward the centre-weighted mean. Symmetric rounding
        // avoids the negative-value bias of an arithmetic right shift.
        if(detail>0) detail_term=-((detail+1)>>>1);
        else detail_term=((-detail+1)>>>1);
    end else if(detail>=-3 && detail<=3) detail_term=0;''')
assert (live/changed[0]).read_text(encoding='utf-8-sig') == expected, 'Unexpected top-level change'
timing = (td/'HDMI1.4b_Transmitter_v2.0_pr.timing').read_text()
sw, st = map(float, re.search(r'SWNS:\s*([-\d.]+)ns,\s*STNS:\s*([-\d.]+)ns', timing).groups())
hw, ht = map(float, re.search(r'HWNS:\s*([-\d.]+)ns,\s*HTNS:\s*([-\d.]+)ns', timing).groups())
assert sw >= 0 and hw >= 0 and st == ht == 0, 'Timing violation'
area = (td/'HDMI1.4b_Transmitter_v2.0_phy.area').read_text()
resources = {k: int(re.search(r'^#'+k+r'\s+(\d+)\s+out of', area, re.M).group(1)) for k in ['lut','reg','bram','bram32k','dsp']}
assert resources['lut'] < 15252 and resources['bram'] <= 55 and resources['bram32k'] <= 11 and resources['dsp'] <= 11
protected = root/'src/td_project/SAIXIAN_2.0_LIGHT_EXAMPLES_20261003.bit'
assert digest(protected) == '90EFFA219A0B14F9A25E56BEB5C3870A658E66C74D606A588168D0F597F04876'
assert digest(root/'releases/HDMI1.4b_Transmitter_v2.0.bit') == '5644F44CD1EDA24525FE592C36EB808FA54BA8533B66E03430A5E1058B633CF4'
release = root/'releases/photo'
reports = release/'reports'
reports.mkdir(parents=True, exist_ok=True)
full_count = 0
for name, count in [('regression.log',52),('quality.log',1)]:
    data = (work/name).read_bytes()
    text = data.decode('utf-16' if data[:2] in (b'\xff\xfe', b'\xfe\xff') else 'utf-8-sig')
    passed = len(re.findall(r'^PASS\b',text,re.M))
    if name == 'regression.log':
        assert passed in (52,53), name
        assert passed == 52 or 'PASS photo synthetic blocks:' in text
        full_count = passed
    else:
        assert passed == count, name
    assert not re.search(r'FATAL|Simulation failed|Compile failed',text), name
    shutil.copy2(work/name, reports/name)
sim = work/'comparison/simulation.log'
assert len(re.findall(r'^PASS\b', sim.read_text(), re.M)) == 3
shutil.copy2(sim, reports/'image_simulation.log')
shutil.copy2(work/'comparison/comparison.png', reports/'comparison.png')
for name in ['HDMI1.4b_Transmitter_v2.0_pr.timing','HDMI1.4b_Transmitter_v2.0_phy.area','HDMI1.4b_Transmitter_v2.0_exception.timing']:
    shutil.copy2(td/name, reports/name)
shutil.copy2(build/'build.log', reports/'build.log')
bit = release/'HDMI1.4b_Transmitter_v2.0.bit'
shutil.copy2(td/bit.name, bit)
manifest = dict(date='2026-10-07', hardware_validation='pending',bit_sha256=digest(bit),
                previous_optimized_bit_sha256=digest(root/'releases'/bit.name),
                resources=resources, setup_wns_ns=sw, hold_wns_ns=hw, regression_passes=53,
                regression_runs={'full':full_count,'synthetic_quality':1 if full_count==52 else 0},changed_existing_files=changed,
                image_scaler_preserved=True, frame_storage_preserved=True, pipeline_latency_preserved=True,
                source_files=[{'path':p.relative_to(live).as_posix(),'sha256':digest(p)} for p in files])
feedback = reports/'board_feedback.json'
if feedback.exists():
    manifest['board_feedback'] = json.loads(feedback.read_text(encoding='utf-8'))
    manifest['image_quality_acceptance'] = manifest['board_feedback']['image_quality_acceptance']
(reports/'source_manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
allowed = {'.v','.vhd','.hex','.mif','.tcl','.sdc','.adc','.al','.md','.py','.ps1','.json','.txt'}
pack = [root/'README.md', root/'build_saixian.ps1'] + files
for folder in ['tests','doc','examples']:
    pack.extend(p for p in (root/folder).rglob('*') if p.is_file() and p.suffix.lower() in allowed)
pack.extend(root/'src/td_project'/name for name in ['HDMI1.4b_Transmitter_v2.0.al','build_saixian.tcl'])
pack.extend(p for p in reports.iterdir() if p.is_file())
pack.append(bit)
archive = release/'HDMI1.4b_Transmitter_v2.0.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
    for p in sorted(set(pack)):
        z.write(p,'2.0Project/'+p.relative_to(root).as_posix())
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    assert hashlib.sha256(z.read('2.0Project/'+bit.relative_to(root).as_posix())).hexdigest().upper() == digest(bit)
    for p in files:
        assert hashlib.sha256(z.read('2.0Project/'+p.relative_to(root).as_posix())).hexdigest().upper() == digest(p)
print('PASS photo candidate published:', resources, 'setup/hold',sw,hw,'sources',len(files),'bit',digest(bit))
print('Previous optimized release and protected default preserved. Hardware validation pending.')
