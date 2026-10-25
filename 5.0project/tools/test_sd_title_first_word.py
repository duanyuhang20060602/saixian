"""Check the RAM read/ready race with a distinctive nonzero first word."""
from pathlib import Path
import argparse,hashlib,json,struct,subprocess,time,zlib
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);ap.add_argument('--iverilog',type=Path,required=True);ap.add_argument('--config',type=Path,required=True);a=ap.parse_args()
 out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
 base=a.config.read_bytes();rows=bytearray(base[20:276]+base[532:788]);rows[:4]=bytes.fromhex('13579bdf')
 identity=zlib.crc32(bytes([16])+rows);records=bytearray()
 for part in range(2):
  fields=bytes([16,part,1,0])+struct.pack('>I',identity);payload=rows[part*256:(part+1)*256]
  records.extend((b'SXTTL001'+fields+struct.pack('>I',zlib.crc32(fields+payload))+payload).ljust(512,b'\0'))
 fixture=out/'first_word_records.hex';fixture.write_text(''.join(f'{v:02x}\n' for v in records))
 files=[ROOT/n for n in ['tests/tb_sd_title_first_word.v','common/photo_sd_title_store.v','common/photo_control.v','common/photo_uart.v']]
 inputs={str(p):sha(p) for p in files+[Path(__file__),fixture,a.config]};start=time.monotonic();binary=out/'first_word.vvp'
 r=subprocess.run([str(a.iverilog),'-g2012','-DTITLE_SIM','-s','tb','-o',str(binary),*map(str,files)],capture_output=True,text=True);log=r.stdout+r.stderr
 if r.returncode==0:
  r=subprocess.run([str(a.iverilog.with_name('vvp.exe')),str(binary)],cwd=out,capture_output=True,text=True,timeout=60);log+=r.stdout+r.stderr
 (out/'first_word.log').write_text(log)
 passed=r.returncode==0 and 'PASS ' in log and 'FATAL:' not in log and all(sha(Path(p))==v for p,v in inputs.items())
 (out/'results.json').write_text(json.dumps(dict(cases=[dict(test='first_word',passed=passed,seconds=round(time.monotonic()-start,2),inputs_sha256=inputs,log_sha256=sha(out/'first_word.log'))]),indent=2)+'\n')
 print(log[-2500:]);assert passed
if __name__=='__main__':main()
