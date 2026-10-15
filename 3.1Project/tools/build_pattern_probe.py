from pathlib import Path
import json,shutil,xml.etree.ElementTree as ET,subprocess,hashlib,re,zlib,struct,time
ROOT=Path(__file__).resolve().parents[1]
base=ROOT/'projects/board_b';dest=ROOT/'projects/board_b_pattern'
dest.mkdir(parents=True,exist_ok=True)
for folder in ['src/user_source','src/td_project']:
    target=dest/folder;target.mkdir(parents=True,exist_ok=True)
    # Copy only source/config files, preserving the existing main build.
    for p in (base/folder).rglob('*'):
        if not p.is_file() or p.suffix.lower() not in ['.v','.vh','.adc','.sdc','.tcl','.al','.json']:continue
        q=target/p.relative_to(base/folder);q.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,q)
td=dest/'src/td_project';name='PHOTO_BOARD_B_PATTERN'
paths=json.loads((td/'sources.json').read_text())
paths=[p for p in paths if Path(p).name in ['sys_pll.v','builtin_link_pll.v','dual_still_reset_sync.v','photo_uart.v','photo_link.v','photo_control.v','photo_status.v']]
paths+=['../../../../common/top_photo_pattern_b.v']
assert {'sys_pll.v','builtin_link_pll.v','dual_still_reset_sync.v'}.issubset({Path(p).name for p in paths})
for p in paths:assert (td/p).is_file(),p
tree=ET.fromstring((td/'PHOTO_BOARD_B.al').read_text().replace('P&R','P&amp;R'))
tree.set('Path',td.as_posix());tree.find('Name').text=name
for tag in ['LABEL','MODULE']:tree.find('TOP_MODULE/'+tag).text='top_photo_pattern_b'
sources=tree.find('Source_Files/Verilog')
for e in list(sources):sources.remove(e)
for i,p in enumerate(paths,1):
    info=ET.SubElement(ET.SubElement(sources,'File',Path=p),'FileInfo')
    for key,value in [('UsedInSyn','true'),('UsedInP&R','true'),('BelongTo','design_1'),('CompileOrder',str(i))]:ET.SubElement(info,'Attr',Name=key,Val=value)
(td/f'{name}.al').write_text(ET.tostring(tree,encoding='unicode').replace('P&amp;R','P&R'))
(td/'sources.json').write_text(json.dumps(paths,indent=2))
t=(td/'build_board.tcl').read_text().replace('{PHOTO_BOARD_B}','{PHOTO_BOARD_B_PATTERN}').replace('{top_photo_b}','{top_photo_pattern_b}')
(td/'build_board.tcl').write_text(t)
# This source has no FIFO. Its inherited async FIFO reset exception has no
# endpoints; remove that command from the diagnostic's own constraint copy.
for p in (dest/'src/user_source/constraints_source').glob('*.sdc'):
    s=p.read_text();s='\n'.join(line for line in s.splitlines() if '*asy_w_rst*.sr' not in line)+'\n'
    p.write_text(s)
selected={ (td/p).resolve() for p in paths }
selected.update((dest/'src/user_source/constraints_source').glob('*'))
selected.update([td/f'{name}.al',td/'build_board.tcl'])
def hashes():return {p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(selected)}
saved=hashes();started=time.time()
out=ROOT/'delivery';out.mkdir(exist_ok=True)
(out/'pattern_source_snapshot.json').write_text(json.dumps(saved,indent=2))
with (td/'build.log').open('w') as log:
    result=subprocess.run(['C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe','build_board.tcl'],cwd=td,stdout=log,stderr=subprocess.STDOUT)
assert result.returncode==0,result.returncode
assert 'USR-8159 CRITICAL-WARNING' not in (td/'build.log').read_text(errors='replace'),'Constraint command failed'
assert hashes()==saved,'Sources changed during build'
timing=(td/f'{name}_pr.timing').read_text(errors='replace')
values={k:float(re.search(k+r':\s*([-\d.]+)ns',timing)[1]) for k in ['SWNS','STNS','HWNS','HTNS']}
assert values['SWNS']>=0 and values['HWNS']>=0 and values['STNS']==0 and values['HTNS']==0,values
bit=td/f'{name}.bit';assert bit.stat().st_mtime>=started
target=out/'PHOTO_BOARD_B_1280X720_J2_PATTERN_PROBE.bit';shutil.copy2(bit,target)
reference=zlib.crc32(b''.join(struct.pack('>H',((p*0x1237)^0x8291)&0xffff) for p in range(921600)))
report={'file':target.name,'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'expected_frame_crc':f'{reference:08X}',
        'pixels':921600,'timing_ns':values,'source_sha256':saved,'hardware_acceptance':'pending'}
(out/'pattern_manifest.json').write_text(json.dumps(report,indent=2))
for p in [td/'build.log',td/f'{name}_pr.timing',td/f'{name}_phy.area']:shutil.copy2(p,out/('pattern_'+p.name))
print(json.dumps({k:v for k,v in report.items() if k!='source_sha256'},indent=2),flush=True)
