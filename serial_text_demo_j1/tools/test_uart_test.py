from pathlib import Path
import argparse,subprocess,sys,json
ROOT=Path(__file__).resolve().parents[1]
ap=argparse.ArgumentParser();ap.add_argument('--work',type=Path,required=True);a=ap.parse_args();a.work.mkdir(parents=True,exist_ok=True)
iv=Path('C:/iverilog/bin/iverilog.exe');binary=a.work/'test.vvp'
r=subprocess.run([str(iv),'-g2012','-s','tb','-o',str(binary),str(ROOT/'rtl/demo_uart_test.v'),str(ROOT/'tests/tb_uart_test.v')],capture_output=True,text=True);assert r.returncode==0,r.stderr
r=subprocess.run([str(iv.with_name('vvp.exe')),str(binary)],capture_output=True,text=True,timeout=30);print(r.stdout+r.stderr);assert r.returncode==0 and 'PASS' in r.stdout
(a.work/'heartbeat.log').write_text(r.stdout+r.stderr,encoding='utf-8')
sys.path.insert(0,str(ROOT/'tools'));from serial_stream import Decoder
for n in range(1,34):
 d=Decoder();events=[];data=b'UART RX=EEEE LAST=EE SD=R\r\nKE'
 for p in range(0,len(data),n):events+=d.feed(data[p:p+n])
 assert events==[('heartbeat','UART RX=EEEE LAST=EE SD=R'),('reply','K'),('reply','E')],events
(a.work/'result.json').write_text(json.dumps({'passed':True,'queued_acks':40,'fragmentation_cases':33,'heartbeat_period_clocks':750000000},indent=2))
print('PASS PC stream decoder: 33 chunk boundaries; heartbeat hex E never mistaken for error ACK')
