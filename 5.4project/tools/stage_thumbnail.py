"""Save a verified thumbnail A firmware with the unchanged matching B release."""
from pathlib import Path
import argparse,datetime,hashlib,json,re,shutil,sys
from build_v4_port import ROOT,inputs
from test_thumbnail import JOBS

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def write(p,obj):Path(p).write_text(json.dumps(obj,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--a-build',type=Path,required=True)
    ap.add_argument('--tests',nargs='+',type=Path,required=True)
    ap.add_argument('--destination',type=Path,default=ROOT/'releases/thumbnail_20261022')
    args=ap.parse_args()
    a=read(args.a_build/'builds/board_a/result.json')
    b=read(ROOT/'releases/v5.0-fx-page-audio-20261021/board_b_build.json')
    records=[]
    for role,r in [('board_a',a),('board_b',b)]:
        assert r['status']=='passed' and r['inputs_unchanged'] and r['toolchain_unchanged'],role
        assert r['inputs_sha256']==inputs(role),'Stale firmware inputs: '+role
        assert r['timing_ns']['SWNS']>=0 and r['timing_ns']['HWNS']>=0
        assert r['timing_ns']['STNS']==0 and r['timing_ns']['HTNS']==0
        records.append(r)
    assert all(sha(p)==h for p,h in a['toolchain_sha256'].items())
    build_log=(args.a_build/'builds/board_a/build.log').read_text(encoding='utf-8',errors='replace')
    slices=re.findall(r'PHY-1001 : (\d+) mslices,',build_log)
    assert slices and int(slices[-1])<=4900
    tests={}
    for directory in args.tests:
        for r in read(directory/'results.json'):
            if r['test'] in JOBS:tests[r['test']]=r
    assert set(tests)==set(JOBS),'Missing regressions: '+str(set(JOBS)-set(tests))
    for name,r in tests.items():
        assert r['passed'],name
        for path,h in r['inputs_sha256'].items():
            p=Path(path) if Path(path).is_absolute() else ROOT/path
            assert sha(p)==h,'Stale regression input: '+name+' '+path
        assert sha(r['log'])==r['log_sha256'],name
    bit_a=Path(a['bit']['path']);bit_b=ROOT/'releases/PHOTO_BOARD_B_5_0.bit'
    assert sha(bit_a)==a['bit']['sha256'] and sha(bit_b)==b['bit']['sha256']
    out=args.destination.resolve();assert out.is_relative_to(ROOT/'releases')
    out.mkdir(parents=True,exist_ok=False)
    artifacts={}
    for role,r,source,name in [('a',a,bit_a,'PHOTO_BOARD_A_5_0_THUMBNAIL.bit'),
                                ('b',b,bit_b,'PHOTO_BOARD_B_5_0_FX_PAGE_AUDIO.bit')]:
        shutil.copy2(source,out/name);artifacts[name]=sha(out/name)
        write(out/f'board_{role}_build.json',r)
    for kind in ('area','timing'):
        p=Path(a[kind]['path']);assert sha(p)==a[kind]['sha256']
        shutil.copy2(p,out/p.name);shutil.copy2(p,ROOT/'releases'/p.name)
        artifacts[p.name]=sha(out/p.name)
    logs=out/'validation';logs.mkdir()
    for name,r in tests.items():
        target=logs/(name+'.log');shutil.copy2(r['log'],target)
        artifacts[target.relative_to(out).as_posix()]=sha(target)
    validation={'version':'5.0-thumbnail-20261022','baseline_commit':'c8041ec71b557f459c273afce12d3fbb33a3b549',
        'hardware_validation':'pending','board_a_rebuilt':True,'board_b_rebuilt':False,
        'board_b_note':'Unchanged FX_PAGE_AUDIO firmware; its complete input hash map still matches the local B project.',
        'thumbnail':{'stored_pixels':[64,36],'display_pixels':[160,90],'pixel_format':'RGB565',
                     'sample_step':[20,20],'storage':'Whole preview in eRAM: 2048 + 256 pixels; no SDRAM allocation.',
                     'generation':'Read-only sampling of the accepted next-photo slot, during vertical blanking with display FIFO reserve.',
                     'hold_sdram_reads':0,
                     'placement':{'x':1088,'y':528},'click_next':True,
                     'quality_note':'Nearest-neighbor 2.5x display; no additional main-video latency.'},
        'optimizations':{'award_sprite_coordinates':'Narrowed arithmetic and registered centers split geometry across the existing five-clock shader pipeline.',
                         'thumbnail_address':'One source-address accumulator replaces separate row/pixel counters; aligned burst lanes use concatenation.',
                         'music_edge_weights':'One native RAM9K lookup replaces the combinational ROM in the original one-clock stage.',
                         'settings_menu':'Geometry and selected-row decoding precede text selection; an output tap is removed to preserve total video latency.'},
        'area':{'board_a_mslices':int(slices[-1]),'board_a_resources':a['resources'],'board_b_resources':b['resources']},
        'timing_ns':{'a':a['timing_ns'],'b':b['timing_ns']},'tests':list(tests.values()),'files_sha256':artifacts}
    write(out/'validation.json',validation)
    # Synchronize every normal programming entry point after all checks pass.
    shutil.copy2(bit_a,ROOT/'releases/PHOTO_BOARD_A_5_0.bit')
    shutil.copy2(bit_a,ROOT/'src/board_a/td_project/PHOTO_BOARD_A.bit')
    assert sha(ROOT/'src/board_b/td_project/PHOTO_BOARD_B.bit')==b['bit']['sha256']
    (ROOT/'VERSION').write_text('5.0-thumbnail-20261022\nbaseline_commit=c8041ec71b557f459c273afce12d3fbb33a3b549\n',encoding='utf-8')
    prior=read(ROOT/'package_manifest.json')
    record=dict(prior)
    record.update(saved_at=datetime.datetime.now().astimezone().isoformat(),source_commit=None,
        baseline_commit=validation['baseline_commit'],source_state='Local next-photo-thumbnail implementation; exact build input SHA256 values are in the release records.',
        source_release=out.relative_to(ROOT).as_posix(),baseline_release=prior.get('source_release'),
        release_tag=None,change_scope='Next-photo preview with guarded SDRAM sampling and static eRAM cache; equivalent award sprite arithmetic, native eRAM music edge lookup and retimed settings menu. B-board RTL, media and audio protocol are unchanged.',
        saved_rtl_files=sum(1 for base in (ROOT/'common',ROOT/'src') for _ in base.rglob('*.v')),
        hardware_validation='pending',current_recorded_test_count=len(tests),
        release_files={'releases/PHOTO_BOARD_A_5_0.bit':a['bit']['sha256'],'releases/PHOTO_BOARD_B_5_0.bit':b['bit']['sha256']},
        release_builds=[{'board':r['board'],'resources':r['resources'],'timing_ns':r['timing_ns'],
                         'bit_sha256':r['bit']['sha256'],'record':(out/f'board_{r["board"]}_build.json').relative_to(ROOT).as_posix()} for r in records],
        package_checks={'local_compilation_performed':True,'board_b_recompiled':False,
            'current_regressions':str(len(tests))+' passed; source and log fingerprints checked.',
            'canonical_bit_copies':'A and B TD/release programming files match the accepted records.',
            'image_media':'Unchanged AWARD720.DLT and existing TF assets.',
            'new_markdown_or_archives':False})
    inventory={p.relative_to(ROOT).as_posix():sha(p) for p in sorted(ROOT.rglob('*')) if p.is_file() and p!=ROOT/'package_manifest.json'}
    assert not any(Path(p).suffix.lower() in ('.md','.zip') for p in inventory)
    record.update(file_count=len(inventory),files_sha256=inventory)
    for item in record.get('source_files',[]):
        if item['saved'] in inventory:item['saved_sha256']=inventory[item['saved']]
    write(ROOT/'package_manifest.json',record)
    from verify_saved_project import verify
    verify(strict=True)
    print(json.dumps({'passed':True,'release':str(out),'mslices':int(slices[-1]),'resources':a['resources'],
                      'timing_ns':a['timing_ns'],'tests':len(tests),'bits':record['release_files']},indent=2))

if __name__=='__main__':main()
