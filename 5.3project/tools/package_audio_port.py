"""Package only the verified matching source, A/B bits, media and evidence."""
from pathlib import Path
import hashlib,json,zipfile
import release
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'delivery'
roles=['board_a','board_b'];selected=set()
bandwidth=json.loads((ROOT/'tests/results/rgb888_bandwidth_results.json').read_text())
assert len(bandwidth)==2 and all(t['passed'] for t in bandwidth)
for t in bandwidth:
 for n,h in t['source_sha256'].items():assert release.digest(ROOT/n)==h,'Bandwidth test source changed'
selected.update((ROOT/'tests/reference/rgb888_switch_before').glob('*.v'))
selected.add(ROOT/'tests/results/rgb888_bandwidth_results.json')
selected.update(ROOT/'tests/results'/(t['test']+'.log') for t in bandwidth)
selected.add(ROOT/'RGB888_SWITCH_FIX.md')
selected.add(ROOT/'BOOT_RECOVERY.md')
selected.add(ROOT/'KNOWN_ISSUES.md')
selected.add(OUT/'boot_path_restore.json')
recovery=json.loads((ROOT/'tests/results/boot_recovery_results.json').read_text())
assert recovery['passed']
for n,h in recovery['source_sha256'].items():assert release.digest(ROOT/n)==h,'Recovery test source changed'
selected.update(ROOT/'tests/results'/n for n in ['boot_recovery_results.json','tb_photo_receive_recovery.log'])
tests=json.loads((ROOT/'tests/results/audio_port_results.json').read_text())
award=json.loads((ROOT/'tests/results/award_v4_results.json').read_text())
assert len(tests)==6 and all(x['passed'] for x in tests)
assert len(award)>=3 and all(x['passed'] for x in award)
sync=json.loads((ROOT/'tests/results/boot_audio_sync_results.json').read_text())
assert sync['passed']
visual=json.loads((ROOT/'tests/results/visual_fx_results.json').read_text())
assert len(visual)==5 and all(v['passed'] for v in visual)
for v in visual:
 for n,h in v['source_sha256'].items():assert release.digest(ROOT/n)==h,'Visual test source changed'
for n,h in sync['source_sha256'].items():assert release.digest(ROOT/n)==h,'Startup test source changed'
manifests=[]
for role in roles:
 m=json.loads((OUT/(role+'_manifest.json')).read_text())
 assert m['source_sha256']==release.hashes(role),'Source changed after build'
 bit=OUT/m['file'];assert release.digest(bit)==m['sha256']
 assert m['timing_ns']['SWNS']>=0 and m['timing_ns']['HWNS']>=0
 manifests.append(m);selected.update(release.files(role))
 selected.update([bit,OUT/(role+'_manifest.json'),OUT/(role+'_build_sources.json')])
 for suffix in ['timing','area','log']:selected.update(p for p in OUT.glob(role+'_*.'+suffix) if not p.name.endswith('_attempt.log'))
 retry=OUT/(role+'_reseed.json')
 if retry.exists() and json.loads(retry.read_text()).get('mapped_source_sha256')==m['source_sha256']:selected.add(retry)
selected.update(ROOT/n for n in ['README.md','AUDIO_VISUAL_REPAIR.md','BOOT_AV_SYNC.md','TRANSPARENT_FX.md','baseline.json'])
selected.update((ROOT/'tools').glob('*.py'))
selected.update((ROOT/'tests').glob('*.v'));selected.update((ROOT/'tests').glob('*.hex'))
for test in tests+award+visual:selected.add(ROOT/'tests/results'/(test['test']+'.log'))
for name in ['audio_port_results.json','award_v4_results.json','repair_effect_reference.txt','repair_effect.txt','boot_preview.png']:
 selected.add(ROOT/'tests/results'/name)
for name in ['AWARD720.DLT','AWARD720_DLT.json','base_tagged_rgb565.bin']:
 selected.add(ROOT/'award_media'/name)
selected.add(ROOT/'tests/results/visual_fx_results.json')
selected.update(ROOT/'tests/results'/n for n in ['boot_audio_sync_results.json','tb_boot_audio_sync.log'])
manifest={'version':'V3.1 restore board-tested boot image path','visual_tests':visual,'bandwidth_tests':bandwidth,'recovery_test':recovery,'board_b_policy':'reuse byte-identical confirmed BOOT_AV_SYNC bit','startup_test':sync,'boards':manifests,'audio_tests':tests,'baseline_regressions':award,
          'hardware_acceptance':'User confirmed startup fixed; RGB888 switching artifacts remain unresolved'}
(OUT/'delivery_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
selected.add(OUT/'delivery_manifest.json')
selected.add(OUT/'audio_repair_menu_preview.png')
for role in roles:selected.add(ROOT/'src'/role/'td_project/sources.json')
archive=OUT/'DUAL_V3_1_BOOT_RECOVERY_SOURCE_AND_BITS.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
 for path in sorted(selected):
  assert path.is_file(),path
  z.write(path,'3.1Project/'+path.relative_to(ROOT).as_posix())
with zipfile.ZipFile(archive) as z:assert z.testzip() is None
print(archive.name,archive.stat().st_size,hashlib.sha256(archive.read_bytes()).hexdigest())
