"""Compare the encoded menu pipeline to frozen RGB storage, including font IP."""
from pathlib import Path
import hashlib,json,os,re,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
OUT=Path('E:/Codex/Work/cooperate-ip-global/menu-tests')
VENDOR=Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/ip/depot/AXI_Ethernet_Lite_1.0/AXI_Ethernet_Lite/RTL/ram_infer.v')

def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    font=ROOT/'common/photo_menu_font.mif'
    # Honor the MIF's range fill before the later per-glyph overrides.
    statements=re.findall(r'(?mi)^\s*(?:\[([0-9a-f]+)\.\.([0-9a-f]+)\]|([0-9a-f]+))\s*:\s*([0-9a-f]+)\s*;',font.read_text(encoding='utf-8'))
    values={}
    for first,last,single,value in statements:
        for address in range(int(first or single,16),int(last or single,16)+1):values[address]=int(value,16)
    assert set(values)==set(range(2048)) and any(values.values())
    (OUT/'font.hex').write_text(''.join(f'{values[i]:04x}\n' for i in range(2048)),encoding='utf-8')
    (OUT/'ip_init_map.vh').write_text('localparam HEX_FILE=INIT_FILE=="photo_menu_font.mif" ? "'+
                                     (OUT/'font.hex').as_posix()+'" : "";\n',encoding='utf-8')
    sources=[ROOT/p for p in ['tests/tb_ip_menu.v','tests/reference/award_v5/photo_settings_overlay.v',
                             'common/photo_settings_overlay.v','common/photo_menu_font.v','tests/ip_vendor_ram_adapter.v']]
    evidence=sources+[font,Path(__file__)]
    hashes={p.relative_to(ROOT).as_posix():digest(p) for p in evidence}
    external={str(VENDOR):digest(VENDOR)}
    stimuli={p.name:digest(p) for p in [OUT/'font.hex',OUT/'ip_init_map.vh']}
    env=os.environ.copy();temp=Path('E:/Codex/Temp/cooperate-ip-global');temp.mkdir(parents=True,exist_ok=True)
    env.update(TEMP=str(temp),TMP=str(temp),TMPDIR=str(temp))
    start=time.monotonic();binary=OUT/'menu_palette.vvp'
    result=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-I',str(OUT),'-s','tb','-o',str(binary),
                           *map(str,sources+[VENDOR])],cwd=OUT,env=env,capture_output=True,text=True)
    log=result.stdout+result.stderr
    if not result.returncode:
        result=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=OUT,env=env,capture_output=True,text=True,timeout=600)
        log+=result.stdout+result.stderr
    (OUT/'menu_palette.log').write_text(log,encoding='utf-8')
    unchanged=all(digest(ROOT/p)==h for p,h in hashes.items()) and digest(VENDOR)==external[str(VENDOR)]
    passed=result.returncode==0 and 'PASS palette pipeline' in log and unchanged and not re.search(r'(?im)^(ERROR:|FATAL:)',log)
    record=dict(test='menu_palette',passed=passed,inputs_unchanged=unchanged,seconds=round(time.monotonic()-start,2),
                inputs_sha256=hashes,external_inputs_sha256=external,stimuli_sha256=stimuli,log_sha256=digest(OUT/'menu_palette.log'))
    (OUT/'results.json').write_text(json.dumps([record],indent=2)+'\n',encoding='utf-8')
    print(log[-1500:],flush=True)
    if not passed:raise SystemExit('Menu palette equivalence failed')

if __name__=='__main__':main()
