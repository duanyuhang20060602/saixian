"""Compare extracted, unmodified production diagnostic blocks cycle by cycle."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);a=ap.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
 files=[ROOT/'common/photo_cached_control_a.v',ROOT/'tests/reference/a_first_reason/photo_cached_control_a_before.v',Path(__file__)]
 ports='input clk,rst,next,award_toggle,relief_command,got,matching,background_transaction,settings_mode,settings_dirty,tx_busy,send,begin_fields_match_q,timeout45,rx_armed,timeout2,rx_fault,done_seen,end_seen,timeout5,input [15:0] state_flags,kind_match_q,input [159:0] incoming,input [31:0] received_crc,expected_crc,'
 wrappers=[]
 for i,p in enumerate(files[:2]):
  s=p.read_text();part=s[s.index('wire response_error='):s.index('assign debug_state=state;')]
  wrappers.append('module reason_'+str(i)+' #(parameter SETTINGS_LINK=1,CHECK_FRAME_CRC=1)('+ports+('output ' if i==0 else 'output reg ')+'[3:0] first_transfer_origin,first_transfer_error);\nlocalparam WAIT_BEGIN=4,ARM=5,RECEIVE=7;\n'+part+'endmodule\n')
 wrapper=out/'production_blocks.v';wrapper.write_text(''.join(wrappers))
 tb=out/'tb.v';tb.write_text('''`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;reg rst=1;
reg next=0,award_toggle=0,relief_command=0,got=0,matching=0,background_transaction=0,settings_mode=0,settings_dirty=0,tx_busy=0,send=0,begin_fields_match_q=0,timeout45=0,rx_armed=0,timeout2=0,rx_fault=0,done_seen=0,end_seen=0,timeout5=0;
reg [15:0] state_flags=0,kind_match_q=0;reg [159:0] incoming=0;reg [31:0] received_crc=0,expected_crc=0,rng=32'h1287bcd3;
wire [3:0] origin[0:3],error[0:3],ref_origin[0:3],ref_error[0:3];
`define PORTS .clk(clk),.rst(rst),.next(next),.award_toggle(award_toggle),.relief_command(relief_command),.got(got),.matching(matching),.background_transaction(background_transaction),.settings_mode(settings_mode),.settings_dirty(settings_dirty),.tx_busy(tx_busy),.send(send),.begin_fields_match_q(begin_fields_match_q),.timeout45(timeout45),.rx_armed(rx_armed),.timeout2(timeout2),.rx_fault(rx_fault),.done_seen(done_seen),.end_seen(end_seen),.timeout5(timeout5),.state_flags(state_flags),.kind_match_q(kind_match_q),.incoming(incoming),.received_crc(received_crc),.expected_crc(expected_crc)
genvar g;generate for(g=0;g<4;g=g+1)begin:configs
 reason_0 #(.SETTINGS_LINK(g%2),.CHECK_FRAME_CRC(g/2)) dut(`PORTS,.first_transfer_origin(origin[g]),.first_transfer_error(error[g]));
 reason_1 #(.SETTINGS_LINK(g%2),.CHECK_FRAME_CRC(g/2)) reference(`PORTS,.first_transfer_origin(ref_origin[g]),.first_transfer_error(ref_error[g]));
end endgenerate
integer i,j,checks=0;reg [5:0] coverage=0;
always @(posedge clk)begin #1;if(!rst)begin
 for(j=0;j<4;j=j+1)if({origin[j],error[j]}!=={ref_origin[j],ref_error[j]})$fatal(1,"diagnostic changed cycle %d config %d: %h/%h expected %h/%h",checks,j,origin[j],error[j],ref_origin[j],ref_error[j]);
 if(origin[3]==1)coverage[0]=1;if(origin[3]==4 && error[3]==1)coverage[1]=1;if(origin[3]==5)coverage[2]=1;
 if(origin[3]==2)coverage[3]=1;if(origin[3]==3)coverage[4]=1;if(origin[3]==4 && error[3]==5)coverage[5]=1;
 checks=checks+4;
end end
initial begin
 repeat(4)@(negedge clk);rst=0;
 for(i=0;i<1000000;i=i+1)begin
  @(negedge clk);rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
  {next,award_toggle,relief_command}=rng[2:0]==0 ? rng[5:3]:3'd0;
  {got,matching,background_transaction,settings_mode,settings_dirty,tx_busy,send,begin_fields_match_q,timeout45,rx_armed,timeout2,rx_fault,done_seen,end_seen,timeout5}=rng[20:6];
  state_flags=16'd1<<rng[24:21];kind_match_q=16'd1<<(rng[26:25]==0 ? 11:rng[26:25]==1 ? 4:rng[26:25]==2 ? 10:2);
  incoming[19:16]=rng[30:27];received_crc=rng[10:0];expected_crc=rng[31] ? rng[10:0]:32'd0;
  rst=(i%5000)==4999;
 end
 @(negedge clk);if(coverage!==6'b111111)$fatal(1,"missing reasons %b",coverage);
 $display("PASS first diagnostic: %0d same-cycle comparisons, all six reasons, four settings/CRC configurations, sticky values, clear/session/reset priority",checks);$finish;
end
endmodule
''')
 h={p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p):sha(p) for p in files+[wrapper,tb]};start=time.monotonic();exe=out/'reason.vvp';env=os.environ.copy();temp=out/'temp';temp.mkdir(exist_ok=True);env.update(TEMP=str(temp),TMP=str(temp),TMPDIR=str(temp))
 c=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-s','tb','-o',str(exe),str(wrapper),str(tb)],cwd=out,env=env,capture_output=True,text=True);log=c.stdout+c.stderr
 if not c.returncode:c=subprocess.run(['C:/iverilog/bin/vvp.exe',str(exe)],cwd=out,env=env,capture_output=True,text=True,timeout=120);log+=c.stdout+c.stderr
 lp=out/'first_reason.log';lp.write_text(log);passed=c.returncode==0 and 'PASS ' in log and 'FATAL' not in log and all(sha(ROOT/k if not Path(k).is_absolute() else Path(k))==v for k,v in h.items())
 (out/'results.json').write_text(json.dumps([dict(test='first_reason',passed=passed,inputs_sha256=h,log=str(lp),log_sha256=sha(lp),seconds=round(time.monotonic()-start,2))],indent=2));print(log,flush=True)
 if not passed:raise SystemExit(1)
if __name__=='__main__':main()
