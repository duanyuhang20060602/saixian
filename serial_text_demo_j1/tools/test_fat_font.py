from pathlib import Path
import argparse,struct,subprocess,json,random
ROOT=Path(__file__).resolve().parents[1]
FONT=(ROOT/'TF卡文件/FONTS.BIN').read_bytes()
def make(fat32=False,partition=2048,spc=8,broken=None):
    sectors={};reserved=32 if fat32 else 1;nfats=2;spf=600 if fat32 else 64;roots=0 if fat32 else 512
    root_sectors=(roots+15)//16;root_start=partition+reserved+nfats*spf;data_start=root_start+root_sectors
    clusters=70000 if fat32 else 12000;total=reserved+nfats*spf+root_sectors+clusters*spc
    boot=bytearray(512);boot[:3]=b'\xeb\x3c\x90';boot[3:11]=b'MSDOS5.0';struct.pack_into('<HBHBH',boot,11,512,spc,reserved,nfats,roots)
    struct.pack_into('<I',boot,32,total);struct.pack_into('<H',boot,22,0 if fat32 else spf)
    if fat32:struct.pack_into('<IHHI',boot,36,spf,0x81,0,5)
    boot[510:]=b'\x55\xaa';sectors[partition]=boot
    if partition:
        m=bytearray(512);entry=446+(32 if broken=='partition2' else 0);m[entry+4]=0x0c if fat32 else 0x06;struct.pack_into('<II',m,entry+8,partition,total);m[510:]=b'\x55\xaa';sectors[0]=m
    n=(len(FONT)+spc*512-1)//(spc*512)
    pool=[127,128,255,256]+list(range(2000,2600));random.Random(42).shuffle(pool)
    chain=[300]+pool[:n-1]
    # Keep well-known FAT-sector boundary entries in the chain too.
    chain=[70000 if broken=='high_cluster' else 300,127,128,255,256]+[x for x in pool if x not in (127,128,255,256)];chain=chain[:n]
    fat={}
    for i,c in enumerate(chain):fat[c]=chain[i+1] if i+1<n else (0x0fffffff if fat32 else 0xffff)
    if fat32:fat.update({5:17,17:0x0fffffff})
    if broken=='chain':fat[chain[0]]=1
    active=1 if fat32 else 0
    for c,value in fat.items():
        width=4 if fat32 else 2;lba=partition+reserved+active*spf+(c*width)//512;offset=c*width%512
        block=sectors.setdefault(lba,bytearray(512));struct.pack_into('<I' if fat32 else '<H',block,offset,value)
    root0=data_start+(5-2)*spc if fat32 else root_start
    root1=data_start+(17-2)*spc if fat32 else root_start+1
    # Skip deleted and LFN entries, then cross a root sector/cluster boundary.
    erased=bytearray(512)
    for i in range(16):erased[i*32]=0xe5
    for s in range(spc if fat32 else 1):sectors[root0+s]=bytearray(erased)
    directory=bytearray(512);directory[:11]=b'FONTS   BIN';directory[11]=0x0f
    entry=32;directory[entry:entry+11]=b'FONTS   BIN';directory[entry+11]=0x20
    struct.pack_into('<H',directory,entry+26,chain[0]&65535);struct.pack_into('<H',directory,entry+20,chain[0]>>16);struct.pack_into('<I',directory,entry+28,len(FONT))
    if broken=='missing':directory[entry:entry+11]=b'OTHER   BIN'
    sectors[root1]=directory
    for index in range((len(FONT)+511)//512):
        cluster=chain[index//spc];lba=data_start+(cluster-2)*spc+index%spc
        sectors[lba]=bytearray(FONT[index*512:(index+1)*512].ljust(512,b'\0'))
    if broken=='exfat':boot[3:11]=b'EXFAT   ';boot[11:17]=bytes(6)
    if broken=='sector_size':struct.pack_into('<H',boot,11,1024)
    # Read-only tests use a sparse model; unallocated FAT0 is deliberately absent.
    return sectors
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--work',required=True,type=Path);a=ap.parse_args();a.work.mkdir(parents=True,exist_ok=True)
    iv=Path('C:/iverilog/bin/iverilog.exe');binary=a.work/'fat.vvp'
    r=subprocess.run([str(iv),'-g2012','-s','tb','-o',str(binary),str(ROOT/'rtl/demo_fat_font.v'),str(ROOT/'tests/tb_fat_font.v')],capture_output=True,text=True);assert r.returncode==0,r.stderr
    cases=[('fat16_mbr',False,2048,8,None,0),('fat16_superfloppy',False,0,1,None,0),('fat32_active_fat1',True,2048,1,None,0),('fat32_superfloppy',True,0,8,None,0),('missing',False,2048,8,'missing',3),('bad_chain',False,2048,8,'chain',4),('exfat',True,2048,1,'exfat',2),('wrong_sector_size',False,2048,8,'sector_size',2)]
    cases += [('fat32_high_cluster',True,2048,1,'high_cluster',0),('third_primary_partition',False,4096,8,'partition2',0)]
    results=[]
    for name,f32,part,spc,broken,err in cases:
        out=a.work/name;out.mkdir(exist_ok=True);sectors=make(f32,part,spc,broken)
        (out/'lbas.hex').write_text(''.join(f'{lba:08x}\n' for lba in sorted(sectors)),encoding='ascii')
        (out/'blocks.hex').write_text(''.join(f'{b:02x}\n' for lba in sorted(sectors) for b in sectors[lba]),encoding='ascii')
        reqs=[0,1,20,100,len(FONT)//512-1,12,19,0]
        if broken=='chain':reqs=[spc]
        (out/'requests.hex').write_text(''.join(f'{v:08x}\n' for v in reqs),encoding='ascii')
        (out/'expected.hex').write_text(''.join(f'{b:02x}\n' for v in reqs for b in FONT[v*512:(v+1)*512]),encoding='ascii')
        r=subprocess.run([str(iv.with_name('vvp.exe')),str(binary),f'+sectors={len(sectors)}',f'+requests={len(reqs)}',f'+error={err}'],cwd=out,capture_output=True,text=True,timeout=120)
        (out/'test.log').write_text(r.stdout+r.stderr,encoding='utf-8');print(name,r.stdout[-450:],flush=True)
        assert r.returncode==0 and 'PASS' in r.stdout,(name,r.stdout,r.stderr)
        results.append({'test':name,'passed':True,'bytes_compared':0 if err else len(reqs)*512})
    (a.work/'results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
if __name__=='__main__':main()
