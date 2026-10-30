from pathlib import Path
import argparse,subprocess,json
ROOT=Path(__file__).resolve().parents[1]
ap=argparse.ArgumentParser();ap.add_argument('--work',type=Path,required=True);a=ap.parse_args();a.work.mkdir(parents=True,exist_ok=True)
data=(ROOT/'TF卡文件/FONTS.BIN').read_bytes();data=data.ljust(287744,b'\0')
(a.work/'font.hex').write_text(''.join(f'{b:02x}\n' for b in data),encoding='ascii')
iv=Path('C:/iverilog/bin/iverilog.exe');out=a.work/'test.vvp'
for native in (False,True):
 flags=['-g2012','-s','tb','-o',str(out)];sources=[str(ROOT/'rtl/demo_core.v'),str(ROOT/'rtl/demo_diagnostics.v'),str(ROOT/'tests/tb_demo.v')]
 if not native:flags+=['-DDEMO_BEHAVIORAL']
 else:
  (a.work/'ip_init_map.vh').write_text('localparam HEX_FILE="";\n',encoding='ascii');flags+=['-I'+str(a.work)]
  sources += [str(ROOT.parent/'5.0project/tests/ip_vendor_ram_adapter.v'),'C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/ip/depot/AXI_Ethernet_Lite_1.0/AXI_Ethernet_Lite/RTL/ram_infer.v']
 r=subprocess.run([str(iv),*flags,*sources],capture_output=True,text=True);assert r.returncode==0,r.stderr
 r=subprocess.run([str(iv.with_name('vvp.exe')),str(out)],cwd=a.work,capture_output=True,text=True,timeout=120)
 (a.work/('native.log' if native else 'test.log')).write_text(r.stdout+r.stderr,encoding='utf-8');print(r.stdout+r.stderr)
 assert r.returncode==0 and 'PASS ' in r.stdout
(a.work/'result.json').write_text(json.dumps({'passed':True,'real_uart':True,'independent_pixels':8192,'hardware_validation':'pending'},indent=2))
