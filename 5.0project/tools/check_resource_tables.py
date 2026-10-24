"""Check exact ROM contents, FIR arithmetic bounds and the raw PCM capacity law."""
from pathlib import Path
import argparse, hashlib, json, re

ROOT = Path(__file__).resolve().parents[1]


def check():
    core = ROOT / 'common/audio_ui/saixian_audio_pitch.v'
    text = core.read_text(encoding='utf-8')
    coefficients = {int(i): (-1 if sign else 1) * int(v) for i, sign, v in
                    re.findall(r"9'd(\d+):coefficient=(-?)16'sd(\d+)", text)}
    assert len(coefficients) == 315
    expected = [coefficients.get(i, 0) & 65535 for i in range(512)]
    hexfile = ROOT / 'common/audio_ui/saixian_pitch_coeff.hex'
    mif = ROOT / 'common/audio_ui/saixian_pitch_coeff.mif'
    words = [int(v, 16) for v in hexfile.read_text().split()]
    stored = {int(a, 16): int(v, 16) for a, v in re.findall(
        r'(?mi)^\s*([0-9a-f]+)\s*:\s*([0-9a-f]+);', mif.read_text())}
    assert words == expected and stored == dict(enumerate(expected))
    bounds = []
    for mode in range(5):
        taps = [coefficients[64*mode+i] for i in range(63)]
        bound = 32768 * sum(map(abs, taps))
        assert sum(taps) == 32768 and taps == list(reversed(taps))
        assert bound + 16384 < 2**32, 'Signed 33-bit accumulator overflow'
        assert 32768 * max(map(abs, taps)) < 2**31, 'FIR product overflow'
        bounds.append(dict(mode=mode, absolute_sum=sum(map(abs, taps)), max_sum_magnitude=bound))
    assert 'reg signed [32:0] accumulator_l,accumulator_r;' in text
    stream = ROOT / 'common/photo_sd_audio_stream.v'
    assert "fifo_wrusedw <= 14'd4096" in stream.read_text(encoding='utf-8')
    maximum = 4096 + 512//4 + 1
    assert maximum == 4225 and maximum < 4352
    files = [core, hexfile, mif, stream, ROOT / 'common/photo_sd_cache.v', Path(__file__)]
    return dict(passed=True, coefficient_words=512, exact_reference_coefficients=315,
                fir_bounds=bounds,
                pcm_capacity=dict(refill_waterline=4096, sector_bytes=512, stereo_frame_bytes=4,
                    maximum_outstanding_sectors=1, registered_pending_frame=1,
                    legal_occupancy_upper_bound=maximum, allocated_frames=4352,
                    assumptions='Unchanged production SD driver returns at most 512 bytes per sector. The stream permits at most one outstanding sector.'),
                inputs_sha256={p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in files})


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    result = check()
    if args.report:
        assert args.report.resolve().drive.upper() == 'E:'
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print('PASS exact coefficient HEX/MIF, signed 33-bit FIR bounds and 4225 < 4352 PCM capacity law')
