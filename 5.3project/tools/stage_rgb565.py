"""Publish the exact tested, timing-clean 5.2 pair. No Markdown or archives."""
from pathlib import Path
import argparse,datetime,hashlib,json,re,shutil
from build_v4_port import ROOT,inputs,LIMITS
from test_thumbnail import JOBS as THUMBNAIL
from test_resource_allocation import JOBS as RESOURCE
from test_rgb565 import JOBS as RGB565

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def write(p,value):Path(p).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--work',type=Path,required=True);ap.add_argument('--a-build',type=Path,required=True);ap.add_argument('--b-build',type=Path,required=True);a=ap.parse_args()
 work=a.work.resolve();baseline=ROOT.with_name('5.1project');saved=read(work/'preserved_5_1.json')
 assert all(sha(baseline/p)==h for p,h in saved.items()),'Preserved 5.1 changed'
 old=read(Path('E:/Codex/Work/resource-reallocation-20261022/preserved_5_0.json'))
 assert all(sha(Path(old['root'])/p)==h for p,h in old['files_sha256'].items()),'Preserved 5.0 changed'
 records=[];mslices={}
 for board,build in [('a',a.a_build),('b',a.b_build)]:
  r=read(build/f'builds/board_{board}/result.json');assert r['status']=='passed' and r['board']==board
  assert r['inputs_unchanged'] and r['toolchain_unchanged'] and r['inputs_sha256']==inputs('board_'+board),'Stale build'
  assert all(sha(p)==h for p,h in r['toolchain_sha256'].items())
  t=r['timing_ns'];assert t['SWNS']>=0 and t['HWNS']>=0 and t['STNS']==0 and t['HTNS']==0
  assert all(r['resources'][k]<=limit for k,limit in LIMITS.items())
  matches=re.findall(r'PHY-1001 : (\d+) mslices,',(build/f'builds/board_{board}/build.log').read_text(errors='replace'))
  assert matches and int(matches[-1])<=4900;mslices[board]=int(matches[-1])
  for kind in ('bit','area','timing'):assert sha(r[kind]['path'])==r[kind]['sha256']
  records.append(r)
 tests=[]
 groups=[('thumbnail-tests',set(THUMBNAIL)),('resource-tests',set(RESOURCE)),('rgb565-tests',set(RGB565)),
         ('uart-tests',{'tb_v4_uart_equivalence','tb_v4_audio_rate','tb_boot_audio_sync','tb_audio_transport_repair'}),
         ('fx-tests',{'effects','math','cache','scene','transition','controls','reader','fx_reader'}),('award-tests',{'reader','native_bus'})]
 for directory,required in groups:
  directory=work/directory;found={r['test']:r for r in read(directory/'results.json')};assert required<=set(found),str(directory)
  for name in sorted(required):
   r=found[name];assert r['passed'],name
   for p,h in r['inputs_sha256'].items():assert sha(Path(p) if Path(p).is_absolute() else ROOT/p)==h,'Stale test '+name+': '+p
   for p,h in r.get('external_inputs_sha256',{}).items():assert sha(p)==h
   for p,h in r.get('stimuli_sha256',{}).items():assert sha(directory/p)==h
   log=Path(r.get('log',directory/(name+'.log')));assert log.is_file()
   if r.get('log_sha256'):assert sha(log)==r['log_sha256']
   tests.append(dict(r,suite=directory.name,log=str(log),log_sha256=sha(log)))
 # Every active production source is fixed RGB565; 24-bit BMP and HDMI colour
 # arithmetic remain supported through conversion, not a second frame format.
 active={p for r in records for p in r['inputs_sha256'] if p.endswith('.v')}
 for p in active:
  assert not re.search(r'\b(?:high_color|requested_high_color|high_color_requested|color_mode_valid|RGB888_READ_ALIGN)\b',(ROOT/p).read_text(encoding='utf-8-sig')),p
 destination=ROOT/'releases/rgb565_20261022';destination.mkdir(parents=True,exist_ok=False)
 for r in records:
  board=r['board'];name='PHOTO_BOARD_'+board.upper()+'_5_2.bit';td=ROOT/f'src/board_{board}/td_project'
  for target in [destination/name,ROOT/'releases'/name,td/('PHOTO_BOARD_'+board.upper()+'.bit')]:shutil.copy2(r['bit']['path'],target)
  write(destination/f'board_{board}_build.json',r)
  for kind in ('area','timing'):
   p=Path(r[kind]['path']);shutil.copy2(p,destination/p.name);shutil.copy2(p,ROOT/'releases'/p.name)
  gate=Path(r['work_project'])/f'src/board_{board}/td_project'/('PHOTO_BOARD_'+board.upper()+'_gate.area');shutil.copy2(gate,destination/gate.name)
 logs=destination/'validation';logs.mkdir()
 for r in tests:
  target=logs/(r['suite']+'_'+r['test']+'.log');shutil.copy2(r['log'],target);r['saved_log']=target.relative_to(ROOT).as_posix()
 before={b:read(baseline/f'releases/resource_allocation_20261022/board_{b}_build.json')['resources'] for b in ('a','b')}
 changes={p.relative_to(ROOT).as_posix():{'before_sha256':saved.get(p.relative_to(ROOT).as_posix()),'after_sha256':sha(p)}
          for base in (ROOT/'common',ROOT/'src') for p in base.rglob('*') if p.is_file() and p.suffix in ('.v','.al','.json') and saved.get(p.relative_to(ROOT).as_posix())!=sha(p)}
 validation={'version':'5.2-rgb565-only-20261022','hardware_validation':'pending','requires_matched_pair':True,'pixel_storage_format':'RGB565',
  'preserved_baseline':{'root':str(baseline),'file_count':len(saved),'all_original_hashes_verified':True,'5_0_also_verified':True},
  'changes':{'removed':'RGB888 packing/unpacking, colour-mode commands and menu row, format switching/reset/CDC, high-colour cache restrictions, A legacy RGB888 framebuffer reader and read mux.',
             'memory':'B horizontal scaler line buffers store exact RGB565 words at 16 bits; expand after synchronous RAM before vertical interpolation. The existing 8192-frame hybrid PCM FIFO is unchanged from 5.1.',
             'preserved':'A HDMI/touch wiring, B preprocessing and AV2 envelope offload, 11 transitions, sparse dwell ripples, trophy spotlights and light tail, BMP24 decoding, audio and thumbnail preview.',
             'protocol':'Existing 19-bit settings field retains bit 18 reserved zero; unsupported format requests are rejected. Native frames and extended RGB565 auxiliary/award payload lengths are preserved.',
             'fifo':'A retains the 1024-word display FIFO because the water reader emits an atomic 640-word row and reserves 32 words; reducing to 512 would violate its admission contract.'},
  'resources_before':before,'resources_after':{r['board']:r['resources'] for r in records},
  'resource_deltas':{r['board']:{k:r['resources'][k]-before[r['board']][k] for k in r['resources']} for r in records},
  'mslices_after':mslices,'timing_ns':{r['board']:r['timing_ns'] for r in records},'rtl_changes':changes,'tests':tests,
  'removed_sources':['src/board_a/user_source/hdl_source/SD/frame_fifo_read.v']}
 validation['files_sha256']={p.relative_to(destination).as_posix():sha(p) for p in destination.rglob('*') if p.is_file()};write(destination/'validation.json',validation)
 (ROOT/'VERSION').write_text(validation['version']+'\nbaseline_version=5.1-resource-allocation-20261022\n',encoding='utf-8')
 manifest=read(ROOT/'package_manifest.json');manifest.update(version='5.2',saved_at=datetime.datetime.now().astimezone().isoformat(),source_commit=None,source_release=destination.relative_to(ROOT).as_posix(),release_tag=None,
  baseline_release='../5.1project',source_state='Local fixed-RGB565 specialization, exact source fingerprints and full A/B routed builds.',change_scope='RGB565-only image path; remove RGB888 legacy path/mode switching and narrow B scaler line RAM.',
  hardware_validation='pending',current_recorded_test_count=len(tests),pixel_storage_format='RGB565',
  release_files={f'releases/PHOTO_BOARD_{r["board"].upper()}_5_2.bit':r['bit']['sha256'] for r in records},
  release_builds=[{'board':r['board'],'resources':r['resources'],'timing_ns':r['timing_ns'],'bit_sha256':r['bit']['sha256'],'record':(destination/f'board_{r["board"]}_build.json').relative_to(ROOT).as_posix()} for r in records],
  package_checks={'local_compilation_performed':True,'both_boards_recompiled':True,'current_regressions':str(len(tests))+' passed; all input and saved-log fingerprints verified.','preserved_5_0_and_5_1':True,'canonical_bit_copies':'5.2 release files and TD programming files match the exact accepted records.','image_media':'Unchanged.','new_markdown_or_archives':False})
 manifest['source_files']=[item for item in manifest.get('source_files',[]) if (ROOT/item['saved']).is_file()]
 inventory={p.relative_to(ROOT).as_posix():sha(p) for p in sorted(ROOT.rglob('*')) if p.is_file() and p!=ROOT/'package_manifest.json'}
 assert not any(Path(p).suffix.lower() in ('.md','.zip') for p in inventory)
 manifest.update(file_count=len(inventory),files_sha256=inventory,saved_rtl_files=sum(1 for base in (ROOT/'common',ROOT/'src') for _ in base.rglob('*.v')))
 for item in manifest['source_files']:
  if item['saved'] in inventory:item['saved_sha256']=inventory[item['saved']]
 write(ROOT/'package_manifest.json',manifest)
 from verify_saved_project import verify
 verify(strict=True)
 print(json.dumps({'passed':True,'resources_before':before,'resources_after':validation['resources_after'],'mslices':mslices,'timing_ns':validation['timing_ns'],'regressions':len(tests),'release':str(destination)},indent=2))
if __name__=='__main__':main()
