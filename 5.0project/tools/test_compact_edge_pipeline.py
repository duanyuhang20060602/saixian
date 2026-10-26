"""Prove early coordinate queries preserve the complete original edge pipeline."""
from pathlib import Path
import argparse,re,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);ap.add_argument('--quick',action='store_true');a=ap.parse_args()
 out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
 fixture=(ROOT/'tests/tb_shared_menu_edge_pipeline.v').read_text()
 fixture=fixture.replace('reg tick=0,drive=0', 'reg[10:0]dx=0;reg[9:0]dy=0;\nalways @(posedge clk)if(rst)begin dx<=0;dy<=0;end else begin dx<=x;dy<=y;end\nreg tick=0,drive=0')
 fixture=fixture.replace('.SHARED_EDGE_WEIGHT(1),.VIDEO_DELAY', '.COMPACT_MENU(1),.SHARED_EDGE_WEIGHT(1),.VIDEO_DELAY')
 fixture=fixture.replace('.EXTERNAL_ENVELOPE(EXTERNAL),.SHARED_WEIGHT(1)', '.EARLY_WEIGHT(1),.EXTERNAL_ENVELOPE(EXTERNAL),.SHARED_WEIGHT(1)')
 fixture=fixture.replace('.shared_weight(weight),', '.weight_x(x),.weight_y(y),.shared_weight(weight),')
 fixture=fixture.replace('.x(x),.y(y)', '.x(dx),.y(dy)')
 fixture=fixture.replace('{rgb,ode,osof,oeol,level,menu}!=={old_rgb,old_de,old_sof,old_eol,old_level,old_menu}', '{rgb,ode,osof,oeol,level}!=={old_rgb,old_de,old_sof,old_eol,old_level}')
 fixture='\n'.join(l for l in fixture.splitlines() if '$display("glyph=' not in l)
 fixture=fixture.replace('if(check_ready)begin', '''if(check_ready)begin
  if(checks>30 && ((^rgb)===1'bx || (^old_rgb)===1'bx))$fatal(1,"unknown RGB cannot count as equal");
  if(checks>30 && expected_border_zero && weight!==8'd96)$fatal(1,"known nonzero border weight was not loaded");''')
 fixture=fixture.replace('reg tick=0,drive=0', 'reg expected_border_zero=0;\nreg tick=0,drive=0')
 fixture=fixture.replace('always @(posedge clk)begin #1;', 'always @(posedge clk)begin expected_border_zero=dy==0 && dx>10 && dx<1200; #1;')
 if a.quick:
  fixture=fixture.replace('yy<750','yy<50').replace('i<200000','i<20000').replace('921600','64000')
 fixture=fixture.replace('exact RGB/menu/sync/level checks','exact known RGB/sync/level checks')
 fixture=fixture.replace('PASS shared menu/edge pipeline', 'PASS compact-font / early-query edge pipeline')
 (out/'pipeline.v').write_text(fixture,encoding='ascii')
 runner=(ROOT/'tools/test_shared_menu_edge.py').read_text()
 runner=runner.replace("ROOT=Path(__file__).resolve().parents[1]",'ROOT=Path('+repr(str(ROOT))+')')
 runner=runner.replace("fixtures=[ROOT/", "fixtures=[ROOT/")
 runner=runner.replace("save('edge_weights.hex',decode(fixtures[4]));", "save('compact_font.hex',decode(ROOT/'common/photo_compact_menu_font.mif'),4);save('edge_weights.hex',decode(fixtures[4]));")
 runner=runner.replace("'localparam HEX_FILE=INIT_FILE==", "'localparam HEX_FILE=INIT_FILE==\"photo_compact_menu_font.mif\" ? \"compact_font.hex\":INIT_FILE==")
 runner=runner.replace("files=[ROOT/('tests/tb_shared_menu_edge_'+('pipeline' if pipeline else 'rom')+'.v')", "files=[out/'pipeline.v'")
 runner=runner.replace('C:/iverilog/bin/iverilog.exe',(ROOT.parents[1]/'.tools/iverilog/bin/iverilog.exe').as_posix()).replace('C:/iverilog/bin/vvp.exe',(ROOT.parents[1]/'.tools/iverilog/bin/vvp.exe').as_posix())
 runner=runner.replace("ROOT/'tests/reference/shared_rom/source.json',*fixtures", "ROOT/'tests/reference/shared_rom/source.json',ROOT/'common/photo_compact_menu_font.mif',*fixtures")
 (out/'runner.py').write_text(runner,encoding='utf-8')
 # The generated runner imports the original asset verifier without copying it.
 import os
 env=os.environ.copy();env['PYTHONPATH']=str(ROOT/'tools')
 r=subprocess.run([sys.executable,str(out/'runner.py'),'--out',str(out),'--only','pipeline_native','pipeline_pcm'],env=env)
 assert r.returncode==0
if __name__=='__main__':main()
