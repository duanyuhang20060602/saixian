from pathlib import Path
import argparse,hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[1]
a=argparse.ArgumentParser();a.add_argument('--out',type=Path,required=True);args=a.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=True)
original=ROOT/'tests/tb_resource_metadata.v';s=original.read_text();s=s.replace('reg clk=0,rst=1;', 'reg clk=0,rst=1,owner_change=0,stream_change=0;')
s=s.replace('photo_av_metadata_a #(.EDGE_METADATA(1)) a(',"wire cache_reset;photo_visual_reset reset_stage(.clk(clk),.rst(rst),.stream_reset(stream_change),.owner_change(owner_change),.reset(cache_reset));\nphoto_av_metadata_a #(.EDGE_METADATA(1)) a(")
s=s.replace('a(.clk(clk),.rst(rst),','a(.clk(clk),.rst(cache_reset),')
idx=s.index(' $display("PASS B envelope:')
s=s[:idx]+''' // A scene change during a partial packet must clear all published state.
 wait(available);@(negedge clk);begin_packet=1;@(negedge clk);begin_packet=0;
 word(0,{16'h4132,8'd90,8'd3});owner_change=1;
 repeat(3)@(negedge clk);owner_change=0;
 if(target!=0 || fft_valid || wave_valid)$fatal(1,"scene reset retained old visual state");
 commit=1;finish=1;@(negedge clk);commit=0;finish=0;frame();
 if(target!=0 || fft_valid || wave_valid)$fatal(1,"partial scene-change packet was published");
 packet({16'h4132,8'd78,8'd3},play_position,1);frame();
 if(target!=78 || !fft_valid || !wave_valid)$fatal(1,"fresh scene metadata did not recover");
 stream_change=1;repeat(3)@(negedge clk);stream_change=0;frame();
 if(target!=0 || fft_valid || wave_valid)$fatal(1,"stream reset retained old visual state");
 packet({16'h4132,8'd79,8'd3},play_position,1);frame();
 if(target!=79 || !fft_valid || !wave_valid)$fatal(1,"fresh stream metadata did not recover");
 $display("PASS registered visual reset:18k stereo samples, CRC/truncated headers, sample eligibility, 520 generations, scene reset during packet, stream reset and fresh publication");$finish;
end
initial begin #20000000;$fatal(1,"metadata timeout");end
endmodule
'''
bench=out/'bench.v';bench.write_text(s)
files=[bench,ROOT/'common/match/photo_visual_reset.v',ROOT/'common/photo_av_metadata.v',ROOT/'common/photo_av_receiver.v',ROOT/'common/audio_ui/saixian_audio_visualizer.v',ROOT/'tests/av_bram_model.v']
top=ROOT/'common/top_photo_a.v';assert '.rst(visual_cache_reset)' in top.read_text() and 'photo_visual_reset visual_reset(' in top.read_text()
hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path(__file__),original,top,*files,*list((ROOT/'common/audio_ui').glob('saixian_av_*.hex'))]};binary=out/'run.vvp';iv=Path('C:/iverilog/bin/iverilog.exe')
r=subprocess.run([str(iv),'-g2012','-s','tb_resource_metadata','-o',str(binary),*map(str,files)],capture_output=True,text=True);log=r.stdout+r.stderr
if r.returncode==0:r=subprocess.run([str(iv.with_name('vvp.exe')),str(binary)],cwd=ROOT,capture_output=True,text=True,timeout=60);log+=r.stdout+r.stderr
(out/'run.log').write_text(log);print(log[-1900:],flush=True);passed=r.returncode==0 and 'PASS ' in log and 'FATAL' not in log
record=dict(test='av_stream_reset',passed=passed,inputs_sha256=hashes,log=str(out/'run.log'),log_sha256=hashlib.sha256((out/'run.log').read_bytes()).hexdigest())
(out/'results.json').write_text(json.dumps([record],indent=2)+'\n');assert passed
