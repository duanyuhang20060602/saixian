"""Prove eRAM video latency against the frozen register implementation."""
from pathlib import Path
import concurrent.futures,hashlib,json,os,re,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
OUT=Path('E:/Codex/Work/cooperate-eram-delay/tests')
VENDOR=Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/ip/depot/AXI_Ethernet_Lite_1.0/AXI_Ethernet_Lite/RTL/ram_infer.v')
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    OUT.mkdir(parents=True,exist_ok=True)
    # Parameter/port adapter only. The independent read-before-write behavior
    # comes from Anlogic's supplied, unmodified plaintext ram_infer model.
    adapter=OUT/'vendor_eram_adapter.v'
    adapter.write_text('''module EG_LOGIC_BRAM #(
 parameter DATA_WIDTH_A=24,ADDR_WIDTH_A=4,DATA_DEPTH_A=16,
 DATA_WIDTH_B=24,ADDR_WIDTH_B=4,DATA_DEPTH_B=16,BYTE_ENABLE=0,
 MODE="DP",REGMODE_A="NOREG",REGMODE_B="NOREG",WRITEMODE_A="NORMAL",
 WRITEMODE_B="NORMAL",RESETMODE="SYNC",IMPLEMENT="9K")(
 input clka,rsta,cea,wea,ocea,bea,input [ADDR_WIDTH_A-1:0] addra,
 input [DATA_WIDTH_A-1:0] dia,output [DATA_WIDTH_A-1:0] doa,
 input clkb,rstb,ceb,web,oceb,beb,input [ADDR_WIDTH_B-1:0] addrb,
 input [DATA_WIDTH_B-1:0] dib,output [DATA_WIDTH_B-1:0] dob);
 ram_infer #(.MODE(MODE=="PDPW" ? "SDP":MODE),.USE_BYTE_WEA(0),.USE_BYTE_WEB(0),
 .DATAWIDTH_A(DATA_WIDTH_A),.ADDRWIDTH_A(ADDR_WIDTH_A),.DATADEPTH_A(DATA_DEPTH_A),
 .DATAWIDTH_B(DATA_WIDTH_B),.ADDRWIDTH_B(ADDR_WIDTH_B),.DATADEPTH_B(DATA_DEPTH_B),
 .REGMODE_A(REGMODE_A),.REGMODE_B(REGMODE_B),.RESETMODE_A(RESETMODE),.RESETMODE_B(RESETMODE),
 .WRITEMODE_A(WRITEMODE_A),.WRITEMODE_B(WRITEMODE_B)) model(
 .clka(clka),.rsta(rsta),.cea(cea),.ocea(ocea),.wea(wea),.dia(dia),.addra(addra),.doa(doa),
 .clkb(clkb),.rstb(rstb),.ceb(ceb),.oceb(oceb),.web(web),.dib(dib),.addrb(addrb),.dob(dob));
 endmodule
''',encoding='utf-8')
    common=[ROOT/p for p in ['tests/tb_eram_video_delay.v','tests/reference/award_v5/photo_display_pipe.v','common/photo_display_pipe.v']]
    evidence=common+[ROOT/'common/photo_award_render.v',Path(__file__)]
    env=os.environ.copy();temp=Path('E:/Codex/Temp/cooperate-eram-delay');temp.mkdir(parents=True,exist_ok=True)
    env.update(TEMP=str(temp),TMP=str(temp),TMPDIR=str(temp))
    def run(name):
        start=time.monotonic();files=list(common);flags=['-DERAM_SIM'] if name=='eram_contract' else []
        external={} if flags else {str(VENDOR):digest(VENDOR)}
        if not flags:files += [adapter,VENDOR]
        hashes={p.relative_to(ROOT).as_posix():digest(p) for p in evidence}
        binary=OUT/(name+'.vvp')
        result=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012',*flags,'-s','tb','-o',str(binary),*map(str,files)],cwd=OUT,env=env,capture_output=True,text=True)
        log=result.stdout+result.stderr
        if not result.returncode:
            result=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=OUT,env=env,capture_output=True,text=True,timeout=240);log+=result.stdout+result.stderr
        (OUT/(name+'.log')).write_text(log,encoding='utf-8')
        unchanged=all(digest(ROOT/p)==h for p,h in hashes.items()) and all(digest(Path(p))==h for p,h in external.items())
        passed=result.returncode==0 and 'PASS ' in log and unchanged and not re.search(r'(?im)^(ERROR:|FATAL:)',log)
        print(name+': '+log[-1600:],flush=True)
        return dict(test=name,passed=passed,inputs_unchanged=unchanged,seconds=round(time.monotonic()-start,2),
                    inputs_sha256=hashes,external_inputs_sha256=external,log_sha256=digest(OUT/(name+'.log')))
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(run,['eram_contract','eram_vendor_model']))
    (OUT/'results.json').write_text(json.dumps(results,indent=2)+'\n',encoding='utf-8')
    if not all(r['passed'] for r in results):raise SystemExit('eRAM latency proof failed')
if __name__=='__main__':main()
