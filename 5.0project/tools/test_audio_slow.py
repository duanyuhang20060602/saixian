"""Verify 50MHz audio compute, exact FIFO/SPI ordering and the 48kHz deadline."""
from pathlib import Path
import argparse, concurrent.futures, hashlib, json, os, re, subprocess
import test_audio_pitch_b as suite
ROOT = Path(__file__).resolve().parents[1]


def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, required=True)
    out = parser.parse_args().out.resolve()
    out.mkdir(parents=True, exist_ok=True)

    def run(name):
        original = ROOT/f'tests/tb_pitch_{name}.v'
        body = original.read_text()
        body = body.replace('module tb;', 'module tb;integer fast_cycles=0,service_started=0,max_service=0;reg slow_clk=0;always #10 slow_clk=~slow_clk;')
        match = re.search(r'photo_audio_pitch_b\s+(\w+)\(', body)
        assert match
        instance = match[1]
        body = body[:match.start()]+body[match.start():].replace(match[0],
            f'photo_audio_pitch_b #(.SLOW_COMPUTE(1)) {instance}(.compute_clk(slow_clk),', 1)
        clock = 'cb' if name == 'transport' else 'clk'
        monitor = f'''
always @(posedge {clock})begin
 fast_cycles=fast_cycles+1;
 if({instance}.raw_read)service_started=fast_cycles;
 if(!rst && {instance}.pitch_valid && {instance}.state==3)begin
  if(fast_cycles-service_started>2083)$fatal(1,"50MHz compute cannot sustain 48kHz: %d fast clocks",fast_cycles-service_started);
  if(fast_cycles-service_started>max_service)max_service=fast_cycles-service_started;
 end
end
'''
        body = body.replace('endmodule', monitor+'\nendmodule', 1)
        body = body.replace('$finish;', '$display("SLOW_COMPUTE_MAX=%0d",max_service);$finish;')
        bench = out/(name+'.v')
        bench.write_text(body, encoding='utf-8')
        files = [bench, *[ROOT/(p.replace('audio_ui/photo_audio_cue_samples.v', 'audio_ui/photo_audio_cue_b.v'))
                         for p in suite.COMMON], ROOT/'common/photo_font_file_b.v']
        hashes = {str(p): digest(p) for p in [Path(__file__), original, *files]}
        binary = out/(name+'.vvp')
        build = subprocess.run(['C:/iverilog/bin/iverilog.exe', '-g2012', '-DVICTORY_SIM', '-s', 'tb',
                                '-o', str(binary), *map(str, files)], cwd=ROOT, capture_output=True, text=True)
        log_text = build.stdout+build.stderr
        passed = False
        if build.returncode == 0:
            result = subprocess.run(['C:/iverilog/bin/vvp.exe', str(binary)], cwd=ROOT,
                                    capture_output=True, text=True, timeout=900)
            log_text += result.stdout+result.stderr
            passed = result.returncode == 0 and 'PASS ' in log_text and 'SLOW_COMPUTE_MAX=' in log_text and 'FATAL' not in log_text
        log = out/(name+'.log')
        log.write_text(log_text, encoding='utf-8')
        assert all(digest(Path(p)) == h for p, h in hashes.items())
        measured = re.search(r'SLOW_COMPUTE_MAX=(\d+)', log_text)
        record = {'test': 'slow_audio_'+name, 'passed': passed, 'source_sha256': hashes,
                  'log': str(log), 'log_sha256': digest(log),
                  'max_service_100mhz_clocks': int(measured[1]) if measured else None,
                  'deadline_100mhz_clocks': 2083}
        print(name+': '+log_text[-2500:], flush=True)
        return record

    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        records = list(pool.map(run, ['flow', 'transport']))
    (out/'results.json').write_text(json.dumps(records, indent=2)+'\n', encoding='utf-8')
    assert all(r['passed'] for r in records)


if __name__ == '__main__':
    main()
