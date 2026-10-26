"""Check unequal title/ticker lengths, all glyphs, motion and default pixels."""
from pathlib import Path
import argparse,hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[1]
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);a=ap.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
 s=(ROOT/'tests/tb_sd_title_osd.v').read_text()
 s=s.replace('length=0;wire','length=0,ticker_length=0;wire').replace('#(.SHARED_TITLE(1))','#(.SHARED_TITLE(1),.INDEPENDENT_TEXT(1))')
 s=s.replace('.ticker_text_length(length)','.ticker_text_length(ticker_length)')
 s=s.replace('length=16;','length=16;ticker_length=6;')
 start=s.index('  sample(0,432,512-k*32);');end=s.index(' end\n // Both labels',start)
 s=s[:start]+s[end:]
 s=s.replace(' // Both labels', ''' for(k=0;k<6;k=k+1)begin
  sample(0,432,192-k*32);
  if(!dut.text_region || dut.glyph_id!=112+k || dut.font_col!=0 || dut.font_row!=0)$fatal(1,"independent ticker bank %d absent",k);
 end
 // Both labels''')
 s=s.replace('length=3;', 'length=3;ticker_length=16;')
 s=s.replace(' $display("PASS two full fallback', ''' for(k=0;k<16;k=k+1)begin
  sample(0,432,512-k*32);if(dut.glyph_id!=112+k)$fatal(1,"long ticker changed with short header");
 end
 $display("PASS independent 16/6 and 3/16 title/ticker lengths, all 32 font glyphs, shared phase, short header static, two full fallback''')
 (out/'osd.v').write_text(s,encoding='ascii')
 files=[out/'osd.v',ROOT/'common/audio_ui/saixian_osd_overlay.v',ROOT/'tests/reference/sd_title/saixian_osd_overlay.v'];iv=ROOT.parents[1]/'.tools/iverilog/bin/iverilog.exe';binary=out/'osd.vvp'
 r=subprocess.run([str(iv),'-g2012','-s','tb','-o',str(binary),*map(str,files)],cwd=out,capture_output=True,text=True);log=r.stdout+r.stderr
 if r.returncode==0:r=subprocess.run([str(iv.with_name('vvp.exe')),str(binary)],cwd=out,capture_output=True,text=True,timeout=600);log+=r.stdout+r.stderr
 (out/'osd.log').write_text(log,encoding='utf-8');print(log[-2500:]);passed=r.returncode==0 and 'PASS ' in log
 (out/'results.json').write_text(json.dumps({'passed':passed,'inputs_sha256':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}},indent=2),encoding='utf-8');assert passed
if __name__=='__main__':main()
