"""Gate delivery on exact build provenance, timing and this revision's tests."""
from pathlib import Path
import hashlib,json
from release import ROOT,OUT,hashes,digest,package

required={
 'award_results.json':{'tb_award_render'},
 'dlt_reader_results.json':{'tb_dlt_reader'},
 'dlt_fault_results.json':{'tb_dlt_faults','tb_dlt_orientation'},
 'dlt_cache_results.json':{'tb_dlt_cache'},
 'award_regression.json':{'tb_award_headers','tb_bmp','tb_award_control','tb_award_fx','tb_award_fifo_link','tb_award_pixels'},
}
tests=[]
for name,names in required.items():
    report=json.loads((ROOT/'tests/results'/name).read_text())
    assert {v['test'] for v in report}==names,(name,report)
    assert all(v['passed'] for v in report),name
    for v in report:
        log=(ROOT/'tests/results'/(v['test']+'.log')).read_text()
        assert 'PASS' in log and 'FATAL' not in log,v
    tests.extend(report)
boards=[]
for role in ('board_a','board_b'):
    m=json.loads((OUT/(role+'_manifest.json')).read_text())
    assert m['source_sha256']==hashes(role),'Sources changed after build: '+role
    assert m['sha256']==digest(OUT/m['file']),'Bitstream digest mismatch'
    assert m['timing_ns']['SWNS']>=0 and m['timing_ns']['HWNS']>=0
    assert m['timing_ns']['STNS']==0 and m['timing_ns']['HTNS']==0
    boards.append({k:m[k] for k in ('role','file','sha256','bytes','timing_ns','resources')})
asset=json.loads((ROOT/'award_media/AWARD720_DLT.json').read_text())
assert asset['exact_single_board_plate']
assert digest(ROOT/'award_media/AWARD720.DLT')==asset['sha256']=='4adf1b6696401faa8e4c7f6d165b3a2d67ffdc49d4d933ac2781056f1b0e5c5b'
assert digest(ROOT/'award_media/base_tagged_rgb565.bin')==asset['tagged_plate_sha256']
evidence=[*ROOT.glob('tests/tb_award*.v'),*ROOT.glob('tests/tb_dlt*.v'),ROOT/'tools/test_dlt.py',ROOT/'tools/verify_dlt.py',ROOT/'tests/native_unused_bram.v',
          ROOT/'tests/tb_bmp.v',ROOT/'tools/test_award.py',ROOT/'tools/test_award_regression.py',
          ROOT/'tools/prepare_award.py',ROOT/'tools/finalize_award.py']
summary=dict(revision='AWARD_DLT_V2',
             dual_baseline_commit='df0fb4f541a76c117138b8fff94266c01255ae27',
             single_award_commit='65caa6223b1f4310089c38fb265f9655cb0009da',
             boards=boards,asset=asset,tests=tests,
             verification_source_sha256={p.relative_to(ROOT).as_posix():digest(p) for p in evidence},
             hardware_validation='pending',
             limits=['Memory application interfaces modeled in control tests; encrypted SDRAM/HDMI PHY require board validation',
                     'Native-size BMP tests assert interpolation RAM is never used; no interpolation verification claimed',
                     'Image-link CRC32 remains disabled as in baseline; UART CRC16 retained',
                     'At most six discovered BMP/DLT assets, continuous allocation required; SXDLT003 single plate only',
                     'RGB888 baseline brief photo-switch black field not declared fixed',
                     'Audio sector arbitration is simulated with modeled SD/audio endpoints; physical audio/image operation requires board validation'])
(OUT/'award_validation.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
package()
print(json.dumps(dict(boards=boards,tests_passed=len(tests),hardware_validation='pending'),indent=2))
