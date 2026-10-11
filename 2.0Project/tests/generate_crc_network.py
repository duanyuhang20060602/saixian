from pathlib import Path
from collections import Counter
import re,random
h=Path(__file__).resolve().parents[1]/'src/user_source/hdl_source'
def reference(x):
    for _ in range(32):x=(x>>1)^0xedb88320 if x&1 else x>>1
    return x
rows=[set(i for i in range(32) if reference(1<<i)&(1<<bit)) for bit in range(32)]
nodes=[]
while True:
    pairs=Counter()
    for row in rows:
        ids=sorted(row)
        for k,a in enumerate(ids):
            for b in ids[k+1:]:pairs[a,b]+=1
    pair,count=pairs.most_common(1)[0]
    if count<2:break
    n=32+len(nodes);nodes.append(pair)
    for row in rows:
        if set(pair)<=row:row.difference_update(pair);row.add(n)
for _ in range(10000):
    value=random.getrandbits(32);bits=[(value>>i)&1 for i in range(32)]
    for a,b in nodes:bits.append(bits[a]^bits[b])
    result=sum((sum(bits[i] for i in row)%2)<<n for n,row in enumerate(rows))
    assert result==reference(value)
def var(i):return f'mix[{i}]' if i<32 else f'terms[{i-32}]'
body='function [31:0] crc_word;\n input [31:0] old,word;\n reg [31:0] mix;\n reg ['+str(len(nodes)-1)+':0] terms;\n begin\n  mix=old^word;\n'
for n,(a,b) in enumerate(nodes):body+=f'  terms[{n}]={var(a)}^{var(b)};\n'
for bit,row in enumerate(rows):body+=f'  crc_word[{bit}]='+('^'.join(var(i) for i in sorted(row)))+';\n'
body+=' end\nendfunction'
for name in ['delta_memory.v','delta_player.v','delta_decoder.v']:
    p=h/name;s=p.read_bytes().decode('utf-8');s,count=re.subn(r'function \[31:0\] crc_word;.*?endfunction',body,s,flags=re.S)
    assert count==1;p.write_bytes(s.encode('utf-8'))
print('Exact CRC32 shared-XOR network:',len(nodes)+sum(len(row)-1 for row in rows),'XORs; 10000 random words match reference.')
