"""Send GB2312 text to the dual-board 5.0 J1 UART (screen TX disconnected)."""
import argparse,time
ap=argparse.ArgumentParser();ap.add_argument('--port',required=True);ap.add_argument('--slot',type=int,choices=range(4),default=0);ap.add_argument('--text',default='');a=ap.parse_args()
logical=a.text.replace('^^','X').replace('^','');assert len(logical)<=16,'Maximum 16 display characters'
payload=f'@{a.slot}:'.encode('ascii')+a.text.encode('gb2312')+b'\r\n'
try:import serial
except ImportError:raise SystemExit('Install pyserial first: python -m pip install pyserial')
with serial.Serial(a.port,115200,timeout=.2) as p:
 time.sleep(.1);p.write(payload);p.flush()
 print('Sent '+payload.hex(' ').upper())
 print('Check the HDMI photo-carousel ticker. This integrated version returns HMI commands, not demo K/E acknowledgements.')
