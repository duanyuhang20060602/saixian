"""Publish a fully checked 5.1 A/B pair without archives or Markdown files."""

# Fixed public-version policy: historical minor-version packaging is disabled.
if __name__ == "__main__":
    raise SystemExit("Historical versioned packager disabled. Use build_saixian.ps1 for the fixed 5.0 project.")

from pathlib import Path
import argparse,datetime,hashlib,json,re,shutil
from build_v4_port import ROOT,inputs,LIMITS
from test_thumbnail import JOBS as THUMBNAIL
from test_resource_allocation import JOBS as RESOURCE

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def write(p,value):Path(p).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--a-build',type=Path,required=True);ap.add_argument('--b-build',type=Path,required=True)
 ap.add_argument('--thumbnail-tests',type=Path,required=True);ap.add_argument('--resource-tests',type=Path,required=True);ap.add_argument('--uart-tests',type=Path,required=True)
 ap.add_argument('--baseline-record',type=Path,required=True);args=ap.parse_args()
 saved=read(args.baseline_record);baseline=Path(saved['root'])
 assert baseline==ROOT.with_name('5.0project')
 assert all(sha(baseline/p)==h for p,h in saved['files_sha256'].items()),'The preserved 5.0 snapshot changed'
 records=[];mslices={}
 for board,work in [('a',args.a_build),('b',args.b_build)]:
  r=read(work/f'builds/board_{board}/result.json')
  assert r['board']==board and r['status']=='passed' and r['inputs_unchanged'] and r['toolchain_unchanged'],board
  assert r['inputs_sha256']==inputs('board_'+board),'Stale build: '+board
  assert all(sha(p)==h for p,h in r['toolchain_sha256'].items()),'Changed toolchain'
  assert r['timing_ns']['SWNS']>=0 and r['timing_ns']['HWNS']>=0 and r['timing_ns']['STNS']==0 and r['timing_ns']['HTNS']==0
  assert all(r['resources'][k]<=v for k,v in LIMITS.items())
  matches=re.findall(r'PHY-1001 : (\d+) mslices,',(work/f'builds/board_{board}/build.log').read_text(errors='replace'))
  assert matches and int(matches[-1])<=4900;mslices[board]=int(matches[-1])
  for kind in ('bit','area','timing'):assert sha(r[kind]['path'])==r[kind]['sha256']
  records.append(r)
 tests=[]
 for directory,required in [(args.thumbnail_tests,set(THUMBNAIL)),(args.resource_tests,set(RESOURCE)),
                            (args.uart_tests,{'tb_v4_uart_equivalence','tb_v4_audio_rate','tb_boot_audio_sync','tb_audio_transport_repair'})]:
  found={r['test']:r for r in read(directory/'results.json')};assert required<=set(found)
  for name in sorted(required):
   r=found[name];assert r['passed'],name
   for p,h in r['inputs_sha256'].items():assert sha(Path(p) if Path(p).is_absolute() else ROOT/p)==h,'Stale test: '+name+' '+p
   log=Path(r.get('log',directory/(name+'.log')));assert log.is_file()
   if r.get('log_sha256'):assert sha(log)==r['log_sha256']
   tests.append(dict(r,log=str(log),log_sha256=sha(log)))
 destination=ROOT/'releases/resource_allocation_20261022';destination.mkdir(parents=True,exist_ok=False)
 artifacts={}
 for r in records:
  board=r['board'];name='PHOTO_BOARD_'+board.upper()+'_5_1.bit'
  for target in [destination/name,ROOT/'releases'/name,ROOT/f'src/board_{board}/td_project'/('PHOTO_BOARD_'+board.upper()+'.bit')]:shutil.copy2(r['bit']['path'],target)
  write(destination/f'board_{board}_build.json',r)
  for kind in ('area','timing'):
   p=Path(r[kind]['path']);shutil.copy2(p,destination/p.name);shutil.copy2(p,ROOT/'releases'/p.name)
  gate=Path(r['work_project'])/f'src/board_{board}/td_project'/('PHOTO_BOARD_'+board.upper()+'_gate.area')
  shutil.copy2(gate,destination/gate.name)
 logs=destination/'validation';logs.mkdir()
 for r in tests:
  target=logs/(r['test']+'.log');shutil.copy2(r['log'],target)
  r['saved_log']=target.relative_to(ROOT).as_posix()
 before={board:read(baseline/f'releases/thumbnail_20261022/board_{board}_build.json')['resources'] for board in ('a','b')}
 changes={p.relative_to(ROOT).as_posix():{'before_sha256':saved['files_sha256'].get(p.relative_to(ROOT).as_posix()),'after_sha256':sha(p)}
          for base in (ROOT/'common',ROOT/'src') for p in base.rglob('*') if p.is_file() and p.suffix in ('.v','.al') and
          saved['files_sha256'].get(p.relative_to(ROOT).as_posix())!=sha(p)}
 validation={'version':'5.1-resource-allocation-20261022','hardware_validation':'pending','requires_matched_pair':True,
  'preserved_baseline':{'root':str(baseline),'file_count':len(saved['files_sha256']),'all_original_hashes_verified':True},
  'changes':{'offload_to_b':'B computes the 19-bit attack/release music envelope from transmitted post-mix PCM; AV2 headers carry the eight-bit target within the existing 291-word CRC-protected metadata packet. A publishes only after the matching PCM playback position.',
             'receive_buffer':'A/B control UART consumers use payload only on the verified receive pulse; the duplicate published-payload register bank is removed.',
             'crc':'The original parallel CRC engines are retained; measured serial engines consumed more logic. External framing, CRC values and receive timing remain unchanged.',
             'metadata_buffer':'Metadata is written directly into an unpublished bank and becomes visible only after the complete header and CRC commit. The redundant intermediate metadata bank is removed.',
             'memory':'A: the 24-bit, 16-word neutral delay uses distributed RAM with the original 15-cycle video behavior. B: the full 8192-frame PCM FIFO maps to four RAM32K blocks plus fifteen RAM9K blocks, releasing four RAM32K blocks without reducing capacity.',
             'unchanged':'Existing media, 11 transitions, still-water ripples, award lights, audio repair, typed page sounds, menu and next-photo preview remain enabled.',
             'rejected_trial':'Prefix-ROM decimal conversion and serial UART CRC were functionally equivalent but increased synthesis resources; the original implementations were retained.'},
  'resources_before':before,'resources_after':{r['board']:r['resources'] for r in records},
  'resource_deltas':{r['board']:{k:r['resources'][k]-before[r['board']][k] for k in r['resources']} for r in records},
  'mslices_before':{'a':read(baseline/'releases/thumbnail_20261022/validation.json')['area']['board_a_mslices']},'mslices_after':mslices,
  'timing_ns':{r['board']:r['timing_ns'] for r in records},'rtl_changes':changes,'tests':tests}
 for p in destination.rglob('*'):
  if p.is_file():artifacts[p.relative_to(destination).as_posix()]=sha(p)
 validation['files_sha256']=artifacts;write(destination/'validation.json',validation)
 (ROOT/'VERSION').write_text(validation['version']+'\nbaseline_version=5.0-thumbnail-20261022\n',encoding='utf-8')
 manifest=read(ROOT/'package_manifest.json')
 manifest.update(saved_at=datetime.datetime.now().astimezone().isoformat(),source_commit=None,source_release=destination.relative_to(ROOT).as_posix(),release_tag=None,
  baseline_release='../5.0project',source_state='Local resource redistribution; both boards rebuilt from the exact recorded inputs.',
  change_scope='AV2 music-envelope offload to B; compact CRC-gated UART and metadata buffers; A distributed-RAM display delay and B hybrid PCM FIFO.',
  hardware_validation='pending',current_recorded_test_count=len(tests),
  release_files={f'releases/PHOTO_BOARD_{r["board"].upper()}_5_1.bit':r['bit']['sha256'] for r in records},
  release_builds=[{'board':r['board'],'resources':r['resources'],'timing_ns':r['timing_ns'],'bit_sha256':r['bit']['sha256'],
                   'record':(destination/f'board_{r["board"]}_build.json').relative_to(ROOT).as_posix()} for r in records],
  package_checks={'local_compilation_performed':True,'both_boards_recompiled':True,'current_regressions':str(len(tests))+' passed, with source fingerprints checked.',
                  'preserved_5_0':True,'canonical_bit_copies':'A/B 5.1 release and TD programming files match the accepted records.','image_media':'Unchanged.','new_markdown_or_archives':False})
 inventory={p.relative_to(ROOT).as_posix():sha(p) for p in sorted(ROOT.rglob('*')) if p.is_file() and p!=ROOT/'package_manifest.json'}
 assert not any(Path(p).suffix.lower() in ('.md','.zip') for p in inventory)
 manifest.update(file_count=len(inventory),files_sha256=inventory,saved_rtl_files=sum(1 for base in (ROOT/'common',ROOT/'src') for _ in base.rglob('*.v')))
 for item in manifest.get('source_files',[]):
  if item['saved'] in inventory:item['saved_sha256']=inventory[item['saved']]
 write(ROOT/'package_manifest.json',manifest)
 from verify_saved_project import verify
 verify(strict=True)
 print(json.dumps({'passed':True,'release':str(destination),'resources_before':before,'resources_after':validation['resources_after'],
                   'mslices_after':mslices,'timing_ns':validation['timing_ns'],'regressions':len(tests),'baseline_5_0_preserved':True},indent=2))
if __name__=='__main__':main()
