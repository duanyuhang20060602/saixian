"""Exercise both SD banks through CRC, retransmitting UART and the real font RAM."""
from pathlib import Path
import argparse,hashlib,json,struct,subprocess,time,zlib
from configure_sd_title import compile_texts,compile_title,write_title_file
ROOT=Path(__file__).resolve().parents[1]
FONT=Path('C:/Windows/Fonts/msyh.ttc')
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);a=ap.parse_args()
    out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
    first,rows=compile_texts('独立标题甲乙丙丁戊己庚辛壬癸子丑','欢迎参加比赛',FONT)
    second,_=compile_texts('100','滚动文字十六个甲乙丙丁戊己庚辛壬',FONT)
    assert len(first)==2048 and len(rows)==1024
    assert first[8]==16 and first[1032]==6 and second[8]==3 and second[1032]==16
    for part in range(4):
        r=first[512*part:512*(part+1)]
        assert r[:8]==b'SXTTL002' and r[9]==part and r[10]==2
        assert zlib.crc32(r[8:16]+r[20:276])==struct.unpack('>I',r[16:20])[0]
    for title,ticker in [('', '正常'),('正常',''),('x'*17,'正常'),('正常','x'*17),('正常','a\nb')]:
        try:compile_texts(title,ticker,FONT)
        except ValueError:pass
        else:raise AssertionError('invalid independent text accepted')
    target=out/'TITLE2.BIN';write_title_file(target,first);before=target.stat();write_title_file(target,second)
    assert target.read_bytes()==second and target.stat().st_ino==before.st_ino and target.stat().st_size==2048
    old=out/'legacy.bin';old.write_bytes(compile_title('旧标题',FONT)[0])
    try:write_title_file(old,first)
    except ValueError:pass
    else:raise AssertionError('legacy allocation silently replaced')
    assert len(old.read_bytes())==1024
    version=bytearray(first);length=bytearray(first)
    for n in range(4):version[n*512+10]=3;length[n*512+8]=17
    (out/'title_records.hex').write_text(''.join(f'{b:02x}\n' for b in first+second+version+length),encoding='ascii')
    p=(ROOT/'tests/tb_sd_title_protocol.v').read_text()
    p=p.replace('config_records[0:4095]','config_records[0:8191]').replace('wire [6:0] word_index,title_address','wire [7:0] word_index,title_address')
    p=p.replace('photo_sd_title_store store','photo_sd_title_store #(.INDEPENDENT_TEXT(1)) store').replace('.TITLE_SD(1))','.TITLE_SD(1),.INDEPENDENT_TEXT(1))')
    p=p.replace('word_length,published_length;', 'word_length,published_length,published_ticker;').replace('.title_length(published_length)', '.ticker_length(published_ticker),.title_length(published_length)')
    p=p.replace('writes[6:0]','writes[7:0]').replace('i<1024','i<2048').replace('writes!=128','writes!=256').replace('i<256','i<512')
    p=p.replace('published_length!=16)', 'published_length!=16 || published_ticker!=6)')
    p=p.replace('wait(a.send && a.message[159:152]==34);drop_ack=1;', 'wait(a.send && a.message[159:152]==34 && a.message[119:112]==128);drop_ack=1;')
    p=p.replace('first_retries<2','first_retries<1').replace('a.incoming[119:112]==0','a.incoming[119:112]==128')
    p=p.replace('published_length!=0)$fatal(1,"restart', 'published_length!=0 || published_ticker!=6)$fatal(1,"restart')
    p=p.replace('#15000000','#30000000')
    # First-bank publication is blanking only, even while the second bank is being sent.
    p=p.replace('PASS SD CRC and single-RAM title store', 'PASS independent title/ticker, high-bit ACK retry, SD CRC and single-RAM text store')
    (out/'protocol.v').write_text(p)
    s=(ROOT/'tests/tb_sd_title_store.v').read_text()
    s=s.replace('records[0:4095]','records[0:8191]').replace('reg [6:0] address','reg [7:0] address')
    s=s.replace('photo_sd_title_store dut','photo_sd_title_store #(.INDEPENDENT_TEXT(1)) dut').replace('i<128','i<256')
    s=s.replace('if(!ready || length!=expected_length)', 'if(!ready)')
    s=s.replace('address=i;repeat(2)', 'address=i;#1;if(length!=(i<128 ? expected_length:(base==0 ? 6:16)))$fatal(1,"bank length mismatch");repeat(2)')
    start=s.index('initial begin');end=s.index('initial begin #',start)
    s=s[:start]+'''initial begin
 $readmemh("title_records.hex",records);reset;
 sector(0,0);sector(512,-1);sector(1024,-1);sector(1536,-1);if(ready)$fatal(1,"bad magic accepted");reset;
 sector(0,-1);sector(512,-1);sector(1024,-1);if(ready)$fatal(1,"three records became ready");
 sector(1536,27);if(ready)$fatal(1,"bad CRC accepted");sector(1536,-1);check(0,16);
 sector(4096,-1);check(0,16);
 reset;sector(0,-1);sector(2560,-1);sector(3072,-1);sector(3584,-1);if(ready)$fatal(1,"mixed identities accepted");sector(2048,-1);check(2048,3);
 reset;sector(1536,-1);sector(512,-1);sector(1024,-1);sector(0,-1);check(0,16);
 reset;sector(0,-1);sector(0,30);sector(512,-1);sector(1024,-1);sector(1536,-1);if(ready)$fatal(1,"bad replacement retained acceptance");sector(0,-1);check(0,16);
 reset;sector(4096,-1);sector(4608,-1);sector(5120,-1);sector(5632,-1);if(ready)$fatal(1,"invalid version accepted");
 sector(6144,-1);sector(6656,-1);sector(7168,-1);sector(7680,-1);if(ready)$fatal(1,"invalid length accepted");
 $display("PASS 4-sector independent text CRC, missing/corrupt/reordered/mixed records, all 512 rows and separate lengths");$finish;
end
''' + s[end:]
    (out/'store.v').write_text(s)
    iv=ROOT.parents[1]/'.tools/iverilog/bin/iverilog.exe'
    cases=[]
    for name,files in [('store',['common/photo_sd_title_store.v']),('protocol',['tests/title_font_ram_model.v','common/photo_cached_control_a.v','common/photo_control.v','common/photo_uart.v','common/photo_sd_title_store.v','common/audio_ui/saixian_font_rom.v'])]:
        paths=[out/(name+'.v')]+[ROOT/f for f in files];binary=out/(name+'.vvp');start=time.monotonic()
        r=subprocess.run([str(iv),'-g2012','-DTITLE_SIM','-s','tb','-o',str(binary),*map(str,paths)],cwd=out,capture_output=True,text=True)
        log=r.stdout+r.stderr
        if r.returncode==0:
            r=subprocess.run([str(iv.with_name('vvp.exe')),str(binary)],cwd=out,capture_output=True,text=True,timeout=900);log+=r.stdout+r.stderr
        (out/(name+'.log')).write_text(log,encoding='utf-8');print(name+': '+log[-2200:],flush=True)
        cases.append({'test':name,'passed':r.returncode==0 and 'PASS ' in log and 'FATAL' not in log,'seconds':time.monotonic()-start,'inputs_sha256':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}})
    (out/'results.json').write_text(json.dumps(cases,indent=2),encoding='utf-8')
    assert all(c['passed'] for c in cases)
if __name__=='__main__':main()
