"""Verify the production parameter ROM and existing inverse/cache native RAM."""
from pathlib import Path
import argparse,json,hashlib,re,subprocess
import test_resource_next
ROOT=Path(__file__).resolve().parents[1]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);a=ap.parse_args();out=a.out;out.mkdir(parents=True,exist_ok=True)
 records=[test_resource_next.run_unit('native_geometry_memory',out)]
 (out/'ip_init_map.vh').write_text('localparam HEX_FILE=INIT_FILE=="water_color_noise.mif" ? "common/fluid/water_color_noise.hex":"";\n',encoding='ascii')
 f=ROOT/'common/fluid';hx=f/'water_color_noise.hex';mif=f/'water_color_noise.mif';values=[int(v,16) for v in hx.read_text().split()];stored={int(i,16):int(v,16) for i,v in re.findall(r'(?mi)^([0-9a-f]+)\s*:\s*([0-9a-f]+);',mif.read_text())};assert len(values)==len(stored)==1024 and all(stored[i]==v for i,v in enumerate(values))
 vendor=test_resource_next.VENDOR;files=[ROOT/'tests/fx11_water/tb_color_noise_memory.v',f/'water_priority_map.v',ROOT/'tests/ip_vendor_ram_adapter.v',vendor]
 binary=out/'noise.vvp';r=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2005','-I'+str(out),'-s','tb','-o',str(binary),*map(str,files)],cwd=ROOT,capture_output=True,text=True);log=r.stdout+r.stderr
 if r.returncode==0:
  r=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=ROOT,capture_output=True,text=True,timeout=120);log+=r.stdout+r.stderr
 p=out/'color_noise_memory.log';p.write_text(log,encoding='utf-8');print(log[-1500:],flush=True)
 inputs=files+[hx,mif,Path(__file__),out/'ip_init_map.vh'];hashes={p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p):sha(p) for p in inputs}
 records.append(dict(test='color_noise_memory',passed=r.returncode==0 and 'PASS ' in log and not re.search(r'(?m)^(ERROR:|FATAL:)',log),inputs_sha256=hashes,log=str(p),log_sha256=sha(p)))
 (out/'results.json').write_text(json.dumps(records,indent=2)+'\n');assert all(r['passed'] for r in records)
if __name__=='__main__':main()
