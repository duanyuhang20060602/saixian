"""Verify the generated SD records, scan decoder, UART delivery and reused font RAM."""
from pathlib import Path
import argparse, hashlib, importlib.util, json, struct, subprocess, sys, time, zlib
ROOT=Path(__file__).resolve().parents[1]

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True)
    ap.add_argument('--iverilog',type=Path,required=True);args=ap.parse_args()
    out=args.out.resolve();out.mkdir(parents=True,exist_ok=True)
    spec=importlib.util.spec_from_file_location('title_tool',ROOT/'tools/configure_sd_title.py')
    tool=importlib.util.module_from_spec(spec);spec.loader.exec_module(tool)
    first,rows=tool.compile_title('一二三四五六七八九十甲乙丙丁戊己',Path('C:/Windows/Fonts/msyh.ttc'))
    second,_=tool.compile_title('100',Path('C:/Windows/Fonts/msyh.ttc'))
    assert len(first)==1024 and len(rows)==512
    for record in (first[:512],first[512:]):
        assert record[:8]==b'SXTTL001'
        assert zlib.crc32(record[8:16]+record[20:276])==struct.unpack('>I',record[16:20])[0]
    for text in ('','x'*17,'a\nb','a\0b'):
        try: tool.compile_title(text,Path('C:/Windows/Fonts/msyh.ttc'))
        except ValueError: pass
        else: raise AssertionError('invalid text accepted')
    target=out/'TITLE.BIN'
    tool.write_title_file(target,first);before=target.stat()
    tool.write_title_file(target,second);after=target.stat()
    assert target.read_bytes()==second and before.st_ino==after.st_ino and after.st_size==1024
    unrelated=out/'unrelated.bin';unrelated.write_bytes(b'keep me')
    try: tool.write_title_file(unrelated,first)
    except ValueError: pass
    else: raise AssertionError('Unrelated output overwritten')
    assert unrelated.read_bytes()==b'keep me'
    version=bytearray(first);version[10]=2;version[522]=2
    length=bytearray(first);length[8]=17;length[520]=17
    (out/'title_records.hex').write_text(''.join(f'{b:02x}\n' for b in first+second+version+length))
    jobs=[('store',['tests/tb_sd_title_store.v','common/photo_sd_title_store.v'],['-DTITLE_SIM']),
          ('protocol',['tests/tb_sd_title_protocol.v','tests/title_font_ram_model.v',
                       'common/photo_cached_control_a.v','common/photo_control.v','common/photo_uart.v','common/photo_sd_title_store.v','common/audio_ui/saixian_font_rom.v'],['-DTITLE_SIM'])]
    records=[]
    for name,names,flags in jobs:
        paths=[ROOT/n for n in names];binary=out/(name+'.vvp');start=time.monotonic()
        evidence=paths+[Path(__file__),ROOT/'tools/configure_sd_title.py',out/'title_records.hex']
        hashes={str(p):sha(p) for p in evidence}
        command=[str(args.iverilog),'-g2012',*flags,'-s','tb','-o',str(binary),*map(str,paths)]
        result=subprocess.run(command,cwd=out,capture_output=True,text=True);log=result.stdout+result.stderr
        if result.returncode==0:
            result=subprocess.run([str(args.iverilog.with_name('vvp.exe')),str(binary)],cwd=out,capture_output=True,text=True,timeout=900)
            log+=result.stdout+result.stderr
        (out/(name+'.log')).write_text(log)
        passed=result.returncode==0 and 'PASS ' in log and 'FATAL:' not in log and all(sha(Path(p))==v for p,v in hashes.items())
        evidence=paths+[Path(__file__),ROOT/'tools/configure_sd_title.py',out/'title_records.hex']
        records.append(dict(test=name,passed=passed,seconds=round(time.monotonic()-start,2),inputs_sha256=hashes,log_sha256=sha(out/(name+'.log'))))
        print(name+': '+log[-2500:],flush=True)
    (out/'results.json').write_text(json.dumps(dict(host_records_passed=True,cases=records),indent=2)+'\n')
    if not all(c['passed'] for c in records):sys.exit(1)

if __name__=='__main__': main()
