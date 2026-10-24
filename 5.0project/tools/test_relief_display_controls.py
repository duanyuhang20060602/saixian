# Prove the production display controls against the frozen original expressions.
from pathlib import Path
import argparse,hashlib,json,os,re,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);a=ap.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
 top=ROOT/'common/top_photo_a.v';ref=ROOT/'tests/reference/display_controls_before/top_photo_a.v';meta=ROOT/'tests/reference/display_controls_before/source.json'
 old=ref.read_text(encoding='utf-8');actual=top.read_text(encoding='utf-8');metadata=json.loads(meta.read_text(encoding='utf-8'));assert hashlib.sha256(old.encode()).hexdigest()==metadata['original_normalized_sha256']
 block=re.search(r'\n// begin DISPLAY_CONTROL_STAGE\n(.*?)// end DISPLAY_CONTROL_STAGE\n',actual,re.S);assert block
 declaration=re.search(r'// DISPLAY_CONTROL_REGISTERS\n(reg [^;]+;\n)',actual);assert declaration
 expected=old
 for source,destination in metadata['replacements']:
  assert expected.count(source)==1;expected=expected.replace(source,destination,1)
 assert actual.replace(block[0],'',1).replace(declaration[0],'',1)==expected,'Unexpected change to RGB/DE/coordinate paths or other top wiring'
 menu=re.search(r'\.rgb_in\((\w+) \? award_menu_rgb:range_rgb\)',old)[1]
 playback=re.search(r'wire \[23:0\] playback_rgb=(.*?) \? award_rgb:',old)[1]
 preview=re.search(r'photo_thumbnail_overlay.*?preview\(.*?\.enable\((.*?)\),\s*\.display_enable',old,re.S)[1]
 pointer=re.search(r'wire pointer_navigation_enable=(.*?);',old)[1]
 tb='''`timescale 1ns/1ps
module tb;
reg pixel_clk=0,rst_pixel=1;always #5 pixel_clk=~pixel_clk;
reg award_active=0,carousel_mode=0,settings_render_mode=0,display_valid=0,boot_active=0,settings_mode=0,result_busy=0,award_loading=0,pointer_enabled=0;reg[2:0]count=0;
wire pointer_navigation_enable='''+pointer+''';
'''+declaration[1]+block[1]+'''
reg[3:0] expected,held;integer checks=0,mask;
always @(posedge pixel_clk)begin
 expected=rst_pixel ? 4'd0:{'''+','.join([menu,playback,preview,pointer])+'''};
 #1;if({award_menu_select_q,award_display_select_q,preview_enable_q,pointer_nav_display_q}!==expected)$fatal(1,"display-gate temporal mismatch mask=%0d",mask);
 if(!rst_pixel)checks=checks+1;
end
initial begin
 repeat(3)@(negedge pixel_clk);rst_pixel=0;
 for(mask=0;mask<4096;mask=mask+1)begin
  @(negedge pixel_clk);held={award_menu_select_q,award_display_select_q,preview_enable_q,pointer_nav_display_q};
  {count,pointer_enabled,award_loading,result_busy,settings_mode,boot_active,display_valid,settings_render_mode,carousel_mode,award_active}=mask;
  #1;if({award_menu_select_q,award_display_select_q,preview_enable_q,pointer_nav_display_q}!==held)$fatal(1,"selector changed between clocks");
 end
 @(negedge pixel_clk);#2;rst_pixel=1;#1;if({award_menu_select_q,award_display_select_q,preview_enable_q,pointer_nav_display_q}!==0)$fatal(1,"async reset failed");
 #1;rst_pixel=0;repeat(3)@(negedge pixel_clk);
 if(checks<4096)$fatal(1,"incomplete truth-table coverage");
 $display("PASS four production video-selection registers versus original conditions: all 4096 scene/count combinations, one-clock settling, held outputs and async reset; other top wiring and RGB/DE/coordinates unchanged");$finish;
end
endmodule
'''
 fixture=out/'display_controls.v';fixture.write_text(tb,encoding='utf-8');files=[top,ref,meta,Path(__file__),fixture];hashes={p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p):sha(p) for p in files}
 temp=out/'temp';temp.mkdir(exist_ok=True);env=os.environ.copy();env.update(TEMP=str(temp),TMP=str(temp),TMPDIR=str(temp));started=time.monotonic();binary=out/'display.vvp'
 p=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-s','tb','-o',str(binary),str(fixture)],cwd=out,env=env,capture_output=True,text=True);log=p.stdout+p.stderr
 if p.returncode==0:
  p=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=out,env=env,capture_output=True,text=True,timeout=60);log+=p.stdout+p.stderr
 path=out/'display_controls.log';path.write_text(log,encoding='utf-8');unchanged=all(sha(Path(k) if Path(k).is_absolute() else ROOT/k)==h for k,h in hashes.items())
 passed=p.returncode==0 and 'PASS four production' in log and not re.search(r'(?im)^(ERROR:|FATAL:)',log) and unchanged
 record=dict(test='display_controls',passed=passed,inputs_sha256=hashes,inputs_unchanged=unchanged,seconds=round(time.monotonic()-started,2),log=str(path),log_sha256=sha(path),scope=metadata['scope']+' Original conditions compared exhaustively with the actual registered production block, delayed one clock.')
 (out/'results.json').write_text(json.dumps([record],indent=2)+'\n',encoding='utf-8');print(log,flush=True)
 if not passed:raise SystemExit('Display gates failed')
if __name__=='__main__':main()
