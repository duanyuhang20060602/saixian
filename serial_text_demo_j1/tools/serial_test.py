"""Every 10s send an incrementing test line and report replies/heartbeats."""
import argparse,time
from serial_stream import Decoder
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--port',required=True);ap.add_argument('--slot',type=int,choices=range(4),default=0);ap.add_argument('--text',default='TEST');ap.add_argument('--interval',type=float,default=10);ap.add_argument('--count',type=int,default=0)
    a=ap.parse_args();assert 0<a.interval and len(a.text)+5<=16 and '^' not in a.text and '\r' not in a.text and '\n' not in a.text
    a.text.encode('gb2312')
    try:import serial
    except ImportError:raise SystemExit('Install: python -m pip install pyserial')
    with serial.Serial(a.port,115200,timeout=.1) as p:
        decoder=Decoder();next_send=time.monotonic();sent=0;pending=False;deadline=0
        print('J1 UART test. One text frame every 10s by default. Ctrl+C stops.',flush=True)
        while True:
            now=time.monotonic()
            if now>=next_send and (not a.count or sent<a.count):
                sent+=1;text=f'{a.text} {sent%10000:04d}';payload=f'@{a.slot}:'.encode()+text.encode('gb2312')+b'\r\n'
                p.write(payload);p.flush();pending=True;deadline=now+3;next_send=now+a.interval
                print(time.strftime('%H:%M:%S'),'TX',payload.hex(' ').upper(),text,flush=True)
            for kind,value in decoder.feed(p.read(max(1,p.in_waiting))):
                print(time.strftime('%H:%M:%S'),'RX',kind,value,flush=True)
                if kind=='reply' and value in 'KE':
                    pending=False
                    print('ACCEPTED' if value=='K' else 'REJECTED: check SD readiness / frame format',flush=True)
            if pending and time.monotonic()>=deadline:
                pending=False;print('No K/E in 3s: inspect J1 wiring and HDMI RX byte count.',flush=True)
            if a.count and sent>=a.count and not pending:break
if __name__=='__main__':
    try:main()
    except KeyboardInterrupt:print('Stopped')
