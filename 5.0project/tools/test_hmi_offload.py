"""Compare preserved HMI commands, B timer cycles and real SPI/PCM recovery.

Reference RTL is the pre-optimization 2026-10-27 no-center-title snapshot,
renamed only to allow simultaneous elaboration. It is never synthesized.
"""
from pathlib import Path
import argparse,concurrent.futures,hashlib,json,os,subprocess
ROOT=Path(__file__).resolve().parents[1]

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--out',type=Path,required=True)
    ap.add_argument('--iverilog',type=Path,required=True)
    args=ap.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=True)
    iv=args.iverilog.resolve();env=dict(os.environ);env['PATH']=str(iv.parent)+os.pathsep+env['PATH']
    jobs={
        'hmi_bytes':('tb_hmi_byte_stream',['tests/tb_hmi_byte_stream.v','common/photo_processing.v','tests/reference/hmi_formatter_before.v'],[]),
        'hmi_recovery':('tb_hmi_relay_recovery',['tests/tb_hmi_relay_recovery.v','common/photo_hmi_remote.v'],[]),
        'hmi_spi':('tb_hmi_remote_spi',['tests/tb_hmi_remote_spi.v','common/photo_hmi_remote.v','common/photo_audio_link.v','common/photo_audio_spi_b_offload.v','common/photo_processing.v'],['VICTORY_SIM']),
        'deadlines':('tb_b_deadlines',['tests/tb_b_deadlines.v','common/photo_control.v','common/photo_uart.v','tests/reference/photo_control_before.v'],[]),
    }
    def run(item):
        name,(top,names,defines)=item;paths=[ROOT/n for n in names];binary=out/(name+'.vvp')
        hashes={n:hashlib.sha256(p.read_bytes()).hexdigest() for n,p in zip(names,paths)}
        r=subprocess.run([str(iv),'-g2012',*['-D'+d for d in defines],'-s',top,'-o',str(binary),*map(str,paths)],cwd=ROOT,env=env,capture_output=True,text=True)
        log=r.stdout+r.stderr
        if r.returncode==0:
            r=subprocess.run([str(iv.with_name('vvp.exe')),str(binary)],cwd=ROOT,env=env,capture_output=True,text=True,timeout=600);log+=r.stdout+r.stderr
        (out/(name+'.log')).write_text(log,encoding='utf-8')
        passed=r.returncode==0 and 'PASS' in log and 'FATAL' not in log
        assert hashes=={n:hashlib.sha256(p.read_bytes()).hexdigest() for n,p in zip(names,paths)},'Inputs changed during simulation'
        print(name+': '+log[-1200:],flush=True)
        return {'test':name,'passed':passed,'inputs_sha256':hashes}
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:results=list(pool.map(run,jobs.items()))
    (out/'results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
    assert all(r['passed'] for r in results)

if __name__=='__main__':main()
