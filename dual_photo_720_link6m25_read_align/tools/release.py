from pathlib import Path
import json,hashlib,sys,re,shutil,zipfile,time,datetime
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'delivery';OUT.mkdir(parents=True,exist_ok=True)
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def files(role):
    td=ROOT/'projects'/role/'src/td_project'
    paths=json.loads((td/'sources.json').read_text(encoding='utf-8'))
    found={(td/p).resolve() for p in paths}
    found.update((td.parent/'user_source/constraints_source').glob('*'))
    found.update((td.parent/'user_source/hdl_source/include').glob('*.v'))
    found.update((td.parent/'user_source/hdl_source/IP').glob('*.tcl'))
    found.update([td/'build_board.tcl',td/f'PHOTO_{role.upper()}.al'])
    return sorted(p for p in found if p.is_file())
def hashes(role):return {p.relative_to(ROOT).as_posix():digest(p) for p in files(role)}
def snapshot(role):
    value={'started':time.time(),'source_sha256':hashes(role)}
    (OUT/f'{role}_build_sources.json').write_text(json.dumps(value,indent=2),encoding='utf-8')
def collect(role):
    saved=json.loads((OUT/f'{role}_build_sources.json').read_text(encoding='utf-8'))
    assert saved['source_sha256']==hashes(role),'Source changed during or after build'
    td=ROOT/'projects'/role/'src/td_project';name=f'PHOTO_{role.upper()}'
    bit=td/(name+'.bit');timing=td/(name+'_pr.timing');area=td/(name+'_phy.area')
    assert bit.stat().st_mtime>=saved['started'],'Stale bitstream'
    report=timing.read_text(encoding='utf-8',errors='replace')
    def metric(tag):
        m=re.search(tag+r':\s*([-\d.]+)ns',report);assert m,tag;return float(m[1])
    values={key:metric(key) for key in ['SWNS','STNS','HWNS','HTNS']}
    assert values['SWNS']>=0 and values['HWNS']>=0 and values['STNS']==0 and values['HTNS']==0,values
    resources={}
    text=area.read_text(encoding='utf-8',errors='replace')
    for key in ['lut','reg','bram9k','bram32k','dsp']:
        m=re.search(r'^\s*#'+key+r'\s+(\d+)',text,re.M);assert m,key;resources[key]=int(m[1])
    dest=OUT/(name+'_1280X720_J2_NOCRC_NOENHANCE_LINK6M25_A_READ_ALIGN.bit');shutil.copy2(bit,dest)
    for src in [timing,area,td/'build.log']:shutil.copy2(src,OUT/(role+'_'+src.name))
    result={'role':role,'file':dest.name,'sha256':digest(dest),'bytes':dest.stat().st_size,'timing_ns':values,
            'link_clock_hz':6250000,'enhancement_enabled':False,'sharpness_enabled':False,'frame_crc_enabled':False,'pixel_link':'c13937b high/low falling-edge launch, combinational ready',
            'sdram_read_data_delay_cycles':1 if role=='board_a' else 0,'resources':resources,'built_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'source_sha256':saved['source_sha256'],'hardware_acceptance':'720p interference fixed per user confirmation'}
    (OUT/f'{role}_manifest.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(role,values,resources)
def package():
    data=[json.loads((OUT/f'{r}_manifest.json').read_text(encoding='utf-8')) for r in ['board_a','board_b']]
    for value in data:assert value['source_sha256']==hashes(value['role']),'Sources differ from delivered build'
    (OUT/'delivery_manifest.json').write_text(json.dumps({'baselines':json.loads((ROOT/'baseline.json').read_text(encoding='utf-8')),'boards':data},indent=2),encoding='utf-8')
    selected=set()
    for role in ['board_a','board_b']:selected.update(files(role))
    selected.update(ROOT/name for name in ['README.md','VALIDATION.md','COMPARISON_720.md','SOURCE_COMPARISON.md','FLOW_REVIEW.md']);selected.update(ROOT.glob('*.json'));selected.update(ROOT.glob('*.ps1'));selected.update(ROOT.glob('*.svg'))
    selected.update((ROOT/'tools').glob('*.py'));selected.update((ROOT/'tests').glob('*.v'));selected.update((ROOT/'tests').glob('*.hex'))
    # The optional pattern test is shipped as a regression dependency only.
    selected.add(ROOT/'common/top_photo_pattern_b.v')
    selected.update((ROOT/'tests/results').glob('*.log'));selected.update((ROOT/'tests/results').glob('*.json'))
    selected.add(OUT/'delivery_manifest.json')
    for role in ['board_a','board_b']:
        selected.update([OUT/f'{role}_manifest.json',OUT/f'{role}_build_sources.json'])
        for suffix in ['timing','area','log']:selected.update(OUT.glob(f'{role}_*.{suffix}'))
    selected.update(OUT/value['file'] for value in data)
    for role in ['board_a','board_b']:selected.add(ROOT/'projects'/role/'src/td_project/sources.json')
    with zipfile.ZipFile(OUT/'DUAL_PHOTO_1280X720_J2_NOCRC_NOENHANCE_LINK6M25_A_READ_ALIGN_SOURCE_AND_BITS.zip','w',zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(selected):archive.write(path,path.relative_to(ROOT).as_posix())
    print('Packaged',OUT/'DUAL_PHOTO_1280X720_J2_NOCRC_NOENHANCE_LINK6M25_A_READ_ALIGN_SOURCE_AND_BITS.zip')
if __name__=='__main__':
    if sys.argv[1]=='snapshot':snapshot(sys.argv[2])
    elif sys.argv[1]=='collect':collect(sys.argv[2])
    elif sys.argv[1]=='package':package()
