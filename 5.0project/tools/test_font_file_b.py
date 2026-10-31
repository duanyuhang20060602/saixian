"""Verify the slow FAT domain against real fragmented font sectors."""
from pathlib import Path
import argparse, hashlib, importlib.util, json, subprocess

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    spec = importlib.util.spec_from_file_location('font_cases', ROOT/'tools/test_font_fat.py')
    model = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(model)
    font = (ROOT/'sd_config/TF字库/FONTS.BIN').read_bytes()
    sectors = model.make(True, 2048, 1, None)
    (out/'lbas.hex').write_text(''.join(f'{n:08x}\n' for n in sorted(sectors)))
    (out/'blocks.hex').write_text(''.join(f'{b:02x}\n' for n in sorted(sectors) for b in sectors[n]))
    requests = [0, 1, 20, 0]
    (out/'requests.hex').write_text(''.join(f'{n:08x}\n' for n in requests))
    (out/'expected.hex').write_text(''.join(f'{b:02x}\n' for n in requests for b in font[n*512:(n+1)*512]))
    text = (ROOT/'tests/tb_font_fat.v').read_text()
    text = text.replace('module tb;', 'module tb #(parameter SLOW_HALF=10,SAME_END=0);\nreg slow_clk=0;always #(SLOW_HALF) slow_clk=~slow_clk;')
    original = "photo_font_fat #(.HZ(1000000),.ADDR_BITS(27)) dut(clk,rst,1'b1,request,address,valid,data,finish,error,read,sector,bv,b,ended);"
    replacement = "photo_font_file_b #(.SLOW_HZ(500000),.ADDR_BITS(27)) dut(clk,rst,slow_clk,rst,1'b1,request,address,valid,data,finish,error,read,sector,bv,b,ended);"
    assert original in text
    text = text.replace(original, replacement)
    text = text.replace('integer st=0,', 'integer gap=0;integer st=0,')
    text = text.replace('base<=matched*512;pos<=0;st<=1;', 'base<=matched*512;pos<=0;gap<=0;st<=1;')
    original = 'if(st==1)begin bv<=1;b<=blocks[base+pos];if(pos==511)st<=2;else pos<=pos+1;end'
    replacement = 'if(st==1)begin if(gap!=0)gap<=gap-1;else begin gap<=15;bv<=1;b<=blocks[base+pos];if(pos==511)begin if(SAME_END)begin ended<=1;st<=0;end else st<=2;end else pos<=pos+1;end end'
    assert original in text
    text = text.replace(original, replacement)
    text = text.replace('bv<=0;ended<=0;', 'bv<=0;ended<=0;if(!rst && error!=0)$fatal(1,"slow FAT adapter overflow/error %d",error);')
    bench = out/'slow.v'
    bench.write_text(text)
    sources = [bench, ROOT/'common/photo_font_file_b.v', ROOT/'common/photo_font_fat.v']
    evidence = [Path(__file__), ROOT/'tests/tb_font_fat.v', ROOT/'tools/test_font_fat.py', ROOT/'sd_config/TF字库/FONTS.BIN',
                *sources, *[out/n for n in ('lbas.hex', 'blocks.hex', 'requests.hex', 'expected.hex')]]
    hashes = {str(p): digest(p) for p in evidence}
    results = []
    for half, same in [(10, 0), (11, 1)]:
        name = f'slow_{half}_end_{same}'
        binary = out/(name+'.vvp')
        build = subprocess.run(['C:/iverilog/bin/iverilog.exe', '-g2012', '-s', 'tb', '-P', f'tb.SLOW_HALF={half}',
                                '-P', f'tb.SAME_END={same}', '-o', str(binary), *map(str, sources)], capture_output=True, text=True)
        (out/(name+'_compile.log')).write_text(build.stdout+build.stderr, encoding='utf-8')
        build.check_returncode()
        run = subprocess.run(['C:/iverilog/bin/vvp.exe', str(binary), f'+sectors={len(sectors)}',
                              f'+requests={len(requests)}', '+error=0'], cwd=out, capture_output=True, text=True, timeout=600)
        log = out/(name+'.log')
        log.write_text(run.stdout+run.stderr, encoding='utf-8')
        passed = run.returncode == 0 and 'PASS' in run.stdout and 'FATAL' not in run.stdout
        assert all(digest(Path(p)) == sha for p, sha in hashes.items())
        results.append({'test': name, 'passed': passed, 'source_sha256': hashes,
                        'log': str(log), 'log_sha256': digest(log), 'bytes_compared': len(requests)*512})
        (out/'results.json').write_text(json.dumps(results, indent=2)+'\n', encoding='utf-8')
        print(name+': '+run.stdout, flush=True)
        assert passed


if __name__ == '__main__':
    main()
