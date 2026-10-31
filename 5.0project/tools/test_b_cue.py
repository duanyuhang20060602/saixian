"""Compare B one-hot cue control against the unchanged shared A implementation."""
from pathlib import Path
import argparse, hashlib, json, subprocess
ROOT = Path(__file__).resolve().parents[1]


def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', type=Path, required=True)
    out = ap.parse_args().out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    current = ROOT/'common/audio_ui/photo_audio_cue_b.v'
    reference = ROOT/'common/audio_ui/photo_audio_cue_samples.v'
    candidate = out/'cue_candidate.v'
    original = out/'cue_reference.v'
    candidate.write_text(current.read_text().replace('module photo_audio_cue_samples', 'module photo_audio_cue_candidate', 1))
    original.write_text(reference.read_text().replace('module photo_audio_cue_samples', 'module photo_audio_cue_reference', 1))
    files = [ROOT/'tests/tb_cue_equivalence.v', candidate, original]
    hashes = {str(p): digest(p) for p in [Path(__file__), current, reference, *files]}
    binary = out/'cue.vvp'
    build = subprocess.run(['C:/iverilog/bin/iverilog.exe', '-g2012', '-s', 'tb', '-o', str(binary), *map(str, files)],
                           capture_output=True, text=True)
    build.check_returncode()
    result = subprocess.run(['C:/iverilog/bin/vvp.exe', str(binary)], capture_output=True, text=True, timeout=180)
    log = out/'cue.log'
    log.write_text(result.stdout+result.stderr, encoding='utf-8')
    passed = result.returncode == 0 and 'PASS cue onehot cycle equivalence' in result.stdout
    assert all(digest(Path(p)) == sha for p, sha in hashes.items())
    record = {'test': 'b_cue_cycle_equivalence', 'passed': passed, 'source_sha256': hashes,
              'log': str(log), 'log_sha256': digest(log),
              'scope': 'Both PAGE_STYLES values, 11 page styles, 15 event codes, interruption, exact PCM and metadata every clock.'}
    (out/'results.json').write_text(json.dumps(record, indent=2)+'\n')
    print(result.stdout, flush=True)
    assert passed


if __name__ == '__main__':
    main()
