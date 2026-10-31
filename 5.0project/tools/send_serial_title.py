"""Encode the existing two OSD regions for J1 UART; GB2312, not UTF-8."""
from pathlib import Path
import argparse,re

def encode_line(kind,text,score=None):
    ranking=kind in tuple('rank'+str(i) for i in range(1,9))
    if kind not in ('title','ticker') and not ranking:raise ValueError('Unknown text region')
    if len(text)>(8 if ranking else 16):raise ValueError('At most 8 name characters or 16 title/ticker characters')
    if any(ord(c)<32 or ord(c)==127 for c in text):raise ValueError('Control characters are not text')
    data=text.encode('gb2312')
    if ranking:
        if ',' in text or not score or not re.fullmatch(r'[0-9]{2}\.[0-9]{2}',score):raise ValueError('Rank format: name without comma, score 00.00 through 99.99')
        return ('@R'+kind[-1]+':').encode()+data+b','+score.encode()+b'\r\n'
    return (b'@0:' if kind=='title' else b'@1:')+data+b'\r\n'

def main():
    p=argparse.ArgumentParser();p.add_argument('kind',choices=['title','ticker']+['rank'+str(i) for i in range(1,9)]);p.add_argument('text');p.add_argument('--score')
    p.add_argument('--out',type=Path);p.add_argument('--port');a=p.parse_args();data=encode_line(a.kind,a.text,a.score)
    if a.out:a.out.write_bytes(data)
    if a.port:
        import serial
        with serial.Serial(a.port,115200,timeout=1) as port:
            port.write(data);port.flush()
    print(data.hex(' '))
if __name__=='__main__':main()
