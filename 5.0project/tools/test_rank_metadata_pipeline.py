"""Check changing raster rows against independently addressed digit pixels."""
from pathlib import Path
import argparse,hashlib,json,shutil,subprocess
ROOT=Path(__file__).resolve().parents[1]
BENCH=r'''`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,finish=0,checking=0;always #5 clk=~clk;
reg[2:0] early=0,row=0,ri=0;reg[8:0] x=352,early_x=352;reg[3:0] fy=0;reg[15:0] tm=0;
wire[31:0] bits;
always @(posedge clk)begin row<=early;x<=early_x;end
saixian_sprint_runtime #(.EARLY_METADATA(1),.EARLY_COLUMNS(1)) d(.clk(clk),.rst(rst),.early_row_id(early),.early_x(early_x),.header(1'b0),.header_addr(10'd0),
 .row_id(row),.x(x),.font_y(fy),.bits(bits),.rank_begin(1'b0),.rank_finish(finish),.rank_failed(1'b0),
 .rank_index(ri),.rank_length(4'd8),.rank_time(tm),.word_valid(1'b0),.word_index(9'd0),.word_data(32'd0));
reg[15:0] font[0:2047];reg[31:0] g0=0,g1=0;reg[15:0] expected_mark,f;
integer digit,col,offset,part,i,j,checked=0;reg[31:0] prng=32'hac51024f;
function[15:0] stamp;input integer n;begin case(n)
 0:stamp=16'h0123;1:stamp=16'h1234;2:stamp=16'h2345;3:stamp=16'h3456;
 4:stamp=16'h4567;5:stamp=16'h5678;6:stamp=16'h6789;7:stamp=16'h7890;
endcase end endfunction
always @(posedge clk)begin
 expected_mark=stamp(row);
 if(x<384)begin digit=expected_mark[15:12];offset=x-352;end
 else if(x<416)begin digit=expected_mark[11:8];offset=x-384;end
 else if(x<480)begin digit=expected_mark[7:4];offset=x-448;end
 else begin digit=expected_mark[3:0];offset=x-480;end
 col=offset/2;f=font[1024+digit*16+fy];g0<={32{f[15-col]}};g1<=g0;
end
always @(negedge clk)if(checking)begin
 if(bits!==g1)$fatal(1,"row metadata/video pipeline mismatch got=%h expected=%h",bits,g1);
 checked=checked+1;
end
initial begin
 $readmemh("photo_rank_glyphs.hex",font);repeat(5)@(negedge clk);rst=0;
 for(i=0;i<8;i=i+1)begin ri=i;tm=stamp(i);finish=1;@(negedge clk);finish=0;@(negedge clk);end
 repeat(5)@(negedge clk);
 for(i=0;i<20000;i=i+1)begin
  prng={prng[30:0],prng[31]^prng[21]^prng[1]^prng[0]};early=prng[2:0];part=prng[4:3];fy=prng[8:5];
  case(part)0:early_x=352;1:early_x=384;2:early_x=448;3:early_x=480;endcase
  early_x=early_x+prng[13:9];@(negedge clk);if(i==4)checking=1;
 end
 checking=0;$display("PASS %0d changing-row digit pixels: early metadata lookup preserves the original two-clock video phase",checked);$finish;
end
initial begin #2000000;$fatal(1,"pipeline timeout");end
endmodule
'''
def main():
 p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True);a=p.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
 bench=out/'bench.v';bench.write_text(BENCH,encoding='ascii');source=ROOT/'common/saixian_battle_result_fx_pipelined.v'
 assets=[ROOT/'common'/f for f in ['photo_rank_header.hex','photo_rank_glyphs.hex','photo_rank_columns.hex']]
 for path in assets:shutil.copy2(path,out/path.name)
 hashes={str(path):hashlib.sha256(path.read_bytes()).hexdigest() for path in [Path(__file__),bench,source,*assets]}
 iv=Path('C:/iverilog/bin/iverilog.exe');binary=out/'run.vvp'
 r=subprocess.run([str(iv),'-g2012','-DRANK_SIM','-s','tb','-o',str(binary),str(bench),str(source)],capture_output=True,text=True);log=r.stdout+r.stderr
 if r.returncode==0:r=subprocess.run([str(iv.with_name('vvp.exe')),str(binary)],cwd=out,capture_output=True,text=True,timeout=60);log+=r.stdout+r.stderr
 (out/'run.log').write_text(log);print(log[-1800:],flush=True);passed=r.returncode==0 and 'PASS ' in log and 'FATAL' not in log
 record=dict(test='rank_metadata_pipeline',passed=passed,inputs_sha256=hashes,log=str(out/'run.log'),log_sha256=hashlib.sha256((out/'run.log').read_bytes()).hexdigest())
 (out/'results.json').write_text(json.dumps([record],indent=2)+'\n');assert passed
if __name__=='__main__':main()
