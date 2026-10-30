"""UART sender: pip install pyserial, then --port COMx --slot 0 --text 中文ABC."""
import argparse,time
from serial_stream import Decoder
ap=argparse.ArgumentParser();ap.add_argument('--port',required=True);ap.add_argument('--slot',type=int,choices=range(4),default=0);ap.add_argument('--text',default='');a=ap.parse_args()
logical=a.text.replace('^^','X').replace('^','');assert len(logical)<=16,'Maximum 16 display characters'
payload=f'@{a.slot}:'.encode('ascii')+a.text.encode('gb2312')+b'\r\n'
try:import serial
except ImportError:raise SystemExit('Install pyserial first: python -m pip install pyserial')
with serial.Serial(a.port,115200,timeout=.2) as p:
 time.sleep(.1);p.reset_input_buffer();p.write(payload);p.flush();until=time.monotonic()+5
 decoder=Decoder();accepted=False;rejected=False
 while time.monotonic()<until:
  for kind,c in decoder.feed(p.read(1)):
   if kind=='reply' and c=='K':accepted=True
   if kind=='reply' and c=='E':rejected=True
  if accepted:print('Accepted; publishes on next vertical blank');break
  if rejected:raise SystemExit('Rejected: check font card ready, encoding, length and line prefix')
 else:raise SystemExit('No ACK: check J1 TX/RX/GND and 115200 baud; demo must finish SD initialization')
