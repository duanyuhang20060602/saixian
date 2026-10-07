"""Publish a routed/source-matched 2.0 candidate; preserve the default bit."""
from pathlib import Path
import sys,json,hashlib,re,shutil,zipfile
root=Path(__file__).resolve().parents[1]
build=Path(sys.argv[1]);td=build/'src/td_project'
digest=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper()
live=root/'src/user_source';snapshot=build/'src/user_source'
files=sorted(p for p in live.rglob('*') if p.is_file())
assert {p.relative_to(live) for p in files}=={p.relative_to(snapshot) for p in snapshot.rglob('*') if p.is_file()}
for p in files:assert digest(p)==digest(snapshot/p.relative_to(live)),f'Source mismatch {p}'
timing=(td/'HDMI1.4b_Transmitter_v2.0_pr.timing').read_text()
sw,st=map(float,re.search(r'SWNS:\s*([-\d.]+)ns,\s*STNS:\s*([-\d.]+)ns',timing).groups())
hw,ht=map(float,re.search(r'HWNS:\s*([-\d.]+)ns,\s*HTNS:\s*([-\d.]+)ns',timing).groups())
assert sw>=0 and hw>=0 and st==ht==0,'Timing violation'
area=(td/'HDMI1.4b_Transmitter_v2.0_phy.area').read_text()
resources={k:int(re.search(r'^#'+k+r'\s+(\d+)\s+out of',area,re.M).group(1)) for k in ['lut','reg','bram','bram32k','dsp']}
assert resources['lut']<15252 and resources['bram']<=55 and resources['bram32k']<=11 and resources['dsp']<=11
protected=root/'src/td_project/SAIXIAN_2.0_LIGHT_EXAMPLES_20261003.bit'
assert digest(protected)=='90EFFA219A0B14F9A25E56BEB5C3870A658E66C74D606A588168D0F597F04876'
baseline=Path('E:/Codex/Work/saixian_2_opt/baseline/src/user_source')
changed=[p.relative_to(baseline).as_posix() for p in baseline.rglob('*') if p.is_file() and digest(p)!=digest(live/p.relative_to(baseline))]
assert set(changed)=={'hdl_source/SD/bmp_read.v','hdl_source/SD/sd_card_bmp.v'}
old=(baseline/'hdl_source/SD/bmp_read.v').read_text();new=(live/'hdl_source/SD/bmp_read.v').read_text();marker='module saixian_load_scaler'
assert old[old.index(marker):]==new[new.index(marker):],'Image scaler changed'
reports=root/'releases/reports';reports.mkdir(parents=True,exist_ok=True)
bit=root/'releases/HDMI1.4b_Transmitter_v2.0.bit';shutil.copy2(td/'HDMI1.4b_Transmitter_v2.0.bit',bit)
for name in ['HDMI1.4b_Transmitter_v2.0_pr.timing','HDMI1.4b_Transmitter_v2.0_phy.area','HDMI1.4b_Transmitter_v2.0_exception.timing']:
    shutil.copy2(td/name,reports/name)
shutil.copy2(build/'build.log',reports/'build.log')
logroot=Path('E:/Codex/Work/saixian_2_opt')
for name,count in [('regression.log',47),('metadata.log',2)]:
    text=(logroot/name).read_text(encoding='utf-8-sig')
    assert len(re.findall(r'^PASS\b',text,re.M))==count,name
    assert not re.search(r'FATAL|Simulation failed|Compile failed',text)
    shutil.copy2(logroot/name,reports/name)
manifest={'date':'2026-10-07','hardware_validation':'pending','bit_sha256':digest(bit),
 'baseline_bit_sha256':digest(protected),'resources':resources,'setup_wns_ns':sw,'hold_wns_ns':hw,
 'regression_passes':49,'changed_existing_files':changed,'scaler_preserved':True,
 'source_files':[{'path':p.relative_to(live).as_posix(),'sha256':digest(p)} for p in files]}
(reports/'source_manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
allowed={'.v','.vhd','.hex','.mif','.tcl','.sdc','.adc','.al','.md','.py','.ps1','.json','.txt'}
pack_files=[root/'README.md',root/'build_saixian.ps1']
pack_files.extend(files)  # Include every hashed source/config/data snapshot file.
for folder in ['src/user_source','tests','doc','examples']:
    pack_files.extend(p for p in (root/folder).rglob('*') if p.is_file() and p.suffix.lower() in allowed)
pack_files.extend(root/'src/td_project'/n for n in ['HDMI1.4b_Transmitter_v2.0.al','build_saixian.tcl'])
pack_files.extend(p for p in reports.iterdir() if p.is_file());pack_files.append(bit)
archive=root/'releases/HDMI1.4b_Transmitter_v2.0.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
    for p in sorted(set(pack_files)):z.write(p,'2.0Project/'+p.relative_to(root).as_posix())
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    for p in files:
        archived=z.read('2.0Project/'+p.relative_to(root).as_posix())
        assert hashlib.sha256(archived).hexdigest().upper()==digest(p)
print('PASS published:',resources,'setup/hold',sw,hw,'sources',len(files),'bit',digest(bit),'default preserved')
