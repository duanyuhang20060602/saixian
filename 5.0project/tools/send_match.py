"""Encode match commands for existing J1 UART,1152008N1."""
from pathlib import Path
import argparse
OPS={'mode':('M',0,1),'home_team':('H',0,5),'away_team':('V',0,5),'duration':('T',0,3),'home_score':('A',0,999),'away_score':('B',0,999)}
BUTTONS={'start':0,'pause':1,'finish':2,'next':3,'home_plus':4,'home_minus':5,'away_plus':6,'away_minus':7}
def encode(action,value=None):
 if action in BUTTONS:
  if value is not None:raise ValueError('Button commands take no value')
  command='K';value=BUTTONS[action]
 else:
  command,low,high=OPS[action]
  if value is None or not low<=value<=high:raise ValueError(f'{action} requires {low}..{high}')
 return f'!{command}:{value}\r\n'.encode('ascii')
def main():
 p=argparse.ArgumentParser();p.add_argument('action',choices=[*OPS,*BUTTONS]);p.add_argument('value',type=int,nargs='?');p.add_argument('--out',type=Path);p.add_argument('--port');a=p.parse_args()
 try:data=encode(a.action,a.value)
 except ValueError as e:p.error(str(e))
 if a.out:a.out.write_bytes(data)
 if a.port:
  import serial
  with serial.Serial(a.port,115200,timeout=1) as port:port.write(data);port.flush()
 print(data.hex(' '))
if __name__=='__main__':main()
