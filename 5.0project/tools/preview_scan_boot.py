"""Render three startup UI snapshots using the production boot renderer."""
from pathlib import Path
import argparse,json,subprocess
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);args=ap.parse_args()
 out=args.out.resolve();out.mkdir(parents=True,exist_ok=True)
 bench=r'''`timescale 1ns/1ps
module tb;
reg clk=0,rst=1;always #5 clk=~clk;reg[11:0] x=0;reg[10:0] y=0;wire[23:0] rgb;
photo_boot_screen #(.VIDEO_DELAY(26),.STAGED_LOADING(1),.COMPLETE_SCAN(1)) d(
 .clk(clk),.rst(rst),.frame_tick(1'b0),.x(x),.y(y),.memory_ready(1'b1),.catalog_ready(1'b0),.frame_ready(1'b1),
 .animation_ready(1'b1),.audio_ready(1'b1),.scan_ready(1'b0),.font_ready(1'b0),
 .photo_present(1'b1),.music_present(1'b1),.font_present(1'b1),.rgb(rgb),.active());
integer i,j,k,fd;reg[255:0] name;
initial begin
 repeat(5)@(negedge clk);rst=0;
 for(k=0;k<3;k=k+1)begin
  @(negedge clk);d.progress=80+160*k;d.phase=16;
  case(k)0:name="photo.ppm";1:name="music.ppm";2:name="font.ppm";endcase
  fd=$fopen(name,"wb");$fwrite(fd,"P6\n520 180\n255\n");
  for(i=0;i<93625;i=i+1)begin
   @(negedge clk);x=380+i%520;y=240+i/520;
   @(posedge clk);#1;
   if(i>=25)begin
    if((^rgb)===1'bx)$fatal(1,"unknown startup pixel");
    $fwrite(fd,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);
   end
  end
  $fclose(fd);
 end
 $display("PASS production startup renderer snapshots, 26-clock alignment, three stages, no unknown RGB");$finish;
end
endmodule
'''
 (out/'preview.v').write_text(bench,encoding='ascii');iv=ROOT.parents[1]/'.tools/iverilog/bin/iverilog.exe'
 binary=out/'preview.vvp'
 r=subprocess.run([str(iv),'-g2005','-s','tb','-o',str(binary),str(out/'preview.v'),str(ROOT/'common/photo_boot_screen.v')],capture_output=True,text=True,cwd=out);log=r.stdout+r.stderr
 if r.returncode==0:r=subprocess.run([str(iv.with_name('vvp.exe')),str(binary)],capture_output=True,text=True,cwd=out,timeout=300);log+=r.stdout+r.stderr
 (out/'preview.log').write_text(log,encoding='utf-8');print(log,flush=True);assert r.returncode==0 and 'PASS ' in log and 'FATAL' not in log
 combined=Image.new('RGB',(520,540))
 for k,name in enumerate(['photo','music','font']):
  image=Image.open(out/(name+'.ppm'));image.save(out/(name+'.png'));combined.paste(image,(0,k*180))
 combined.save(out/'startup-stages.png')
 (out/'preview.json').write_text(json.dumps({'passed':True,'scope':'Production renderer snapshots at progress 80/240/400; not a hardware capture or live storage measurement.','video_delay':26},indent=2),encoding='utf-8')
if __name__=='__main__':main()
