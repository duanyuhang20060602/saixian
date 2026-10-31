"""Run text publishing against real font bytes, UART control and fragmented FAT."""
from pathlib import Path
import argparse, hashlib, json, subprocess, importlib.util
ROOT=Path(__file__).resolve().parents[1]

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);ap.add_argument('--reuse',action='store_true');args=ap.parse_args()
 out=args.out.resolve();out.mkdir(parents=True,exist_ok=True)
 font=(ROOT/'sd_config/TF字库/FONTS.BIN').read_bytes()
 (out/'font.hex').write_text(''.join(f'{b:02x}\n' for b in font),encoding='ascii')
 source=(ROOT/'tests/tb_typed_text.v').read_text()
 start=source.index('// Deliver complete control packets')
 end=source.index('reg[7:0] file_bytes',start)
 uart='''wire a_tx,b_tx;
reg corrupt=1,drop=1;integer rejected=0,duplicates=0;
wire[159:0] sent_message=corrupt && am[159:152]==40 ? am^(160'd1<<64):am;
always @(posedge clk)begin
 if(as && am[159:152]==40 && corrupt)begin corrupt<=0;rejected<=rejected+1;end
 if(bs && bm[159:152]==41 && drop)begin drop<=0;duplicates<=duplicates+1;end
end
photo_cached_control_a #(.TYPED_TEXT(1),.CLK_HZ(921600),.TIMER_SCALE(64),.TITLE_SD(0),.AWARD_CONTROL(1),.BOOT_STATUS(1)) a(
 .clk(clk),.rst(rst),.uart_rx(b_tx),.uart_tx(a_tx),.hmi_session(a_session),
 .text_busy(busy),.text_pending(ap),.text_message(sent_message),.text_sent(as),.text_received(ar),.text_incoming(ai),
 .settings_mode(1'b0),.settings_state(19'd0),.award_toggle(1'b0),.relief_toggle(1'b0),.previous(1'b0),.next(1'b0),
 .active_slot(2'd0),.new_slot(2'd1),.transition_active(1'b0),.commit_toggle(1'b0),.rx_armed(1'b0),.rx_done(1'b0),.rx_fault(1'b0),.rx_crc(32'd0),.thumbnail_read_busy(1'b0),.thumbnail_read_slot(2'd0));
photo_typed_control_b #(.TYPED_TEXT(1),.CLK_HZ(921600),.TIMER_SCALE(64),.TITLE_SD(0),.AWARD_CONTROL(1),.BOOT_STATUS(1)) b(
 .clk(clk),.rst(rst),.uart_rx(a_tx),.uart_tx(b_tx),.hmi_session(b_session),
 .text_pending(bp && !(drop && bm[159:152]==41)),.text_message(bm),.text_sent(bs),.text_received(br),.text_incoming(bi),
 .title_ready(1'b0),.title_length(5'd0),.title_data(32'd0),.image_count(3'd0),.award_available(1'b0),.award_scan_complete(1'b1),.relief_available(1'b0),
 .media_ready(1'b0),.media_slot(2'd0),.media_error(4'd0),.media_source_width(16'd1280),.media_source_height(16'd720),.tx_done(1'b0),.tx_crc(32'd0));
// Suppress one ACK request while still exercising the actual UART scheduler.
always @(posedge clk)if(drop && bp && bm[159:152]==41)begin drop<=0;duplicates<=duplicates+1;end
'''
 # Outputs of control blocks drive the bridge; use each negotiated session.
 uart_source=source[:start]+uart+source[end:]
 uart_source=uart_source.replace('reg[31:0] session=1;', 'reg[31:0] session=1;wire[31:0] a_session,b_session;')
 uart_source=uart_source.replace('reg as=0,bs=0,ar=0,br=0;reg[159:0] ai=0,bi=0;', 'wire as,bs,ar,br;wire[159:0] ai,bi;')
 uart_source=uart_source.replace('frame_tick,busy,session,lv','frame_tick,busy,a_session,lv').replace('bridge_b(clk,rst,session,','bridge_b(clk,rst,b_session,')
 uart_source=uart_source.replace('mask,wa,session,fr,ff,text_tick);','mask,wa,b_session,fr,ff,text_tick);')
 # Keep the test carousel from rotating while the low-rate UART is in flight.
 uart_source=uart_source.replace('session=2;', "force a.session=32'd2;force b.session=32'd2;repeat(4)@(negedge clk);release a.session;release b.session;")
 # Complete font queries through the production FAT mapper, not virtual offsets.
 physical='''wire fat_valid,fat_finish,fat_read;wire[7:0] fat_data;wire[31:0] fat_sector;wire[3:0] fat_error;
reg pv=0,pe=0;reg[7:0] pd=0;
photo_font_fat #(.HZ(1000000),.ADDR_BITS(27)) fs(clk,rst,1'b1,req,addr,fat_valid,fat_data,fat_finish,fat_error,fat_read,fat_sector,pv,pd,pe);
reg[31:0] lbas[0:2047];reg[7:0] blocks[0:1048575];integer sector_count,j,match,ps=0,pp=0,pbase=0;
initial begin
 if(!$value$plusargs("sectors=%d",sector_count))$fatal;
 $readmemh("lbas.hex",lbas,0,sector_count-1);$readmemh("blocks.hex",blocks,0,sector_count*512-1);
end
always @(posedge clk)begin
 pv<=0;pe<=0;
 if(fat_read)begin
  if(ps!=0)$fatal(1,"overlap physical read");match=-1;for(j=0;j<sector_count;j=j+1)if(lbas[j]==fat_sector)match=j;
  if(match<0)$fatal(1,"unexpected physical LBA %d",fat_sector);pbase<=match*512;pp<=0;ps<=1;
 end
 if(ps==1)begin pv<=1;pd<=blocks[pbase+pp];if(pp==511)ps<=2;else pp<=pp+1;end
 if(ps==2)ps<=3;if(ps==3)begin pe<=1;ps<=0;end
 if(fat_error!=0)$fatal(1,"FAT font error %d",fat_error);
end
'''
 combined=uart_source.replace('req,addr,sv,sd,se,wp','req,addr,fat_valid,fat_data,fat_finish,wp')
 a=combined.index('reg[7:0] file_bytes');b=combined.index('task byte_send',a)
 combined=combined[:a]+'reg[7:0] file_bytes[0:287743];\n'+physical+combined[b:]
 combined=combined.replace('wire fat_valid,fat_finish,fat_read;wire[7:0] fat_data;wire[31:0] fat_sector;wire[3:0] fat_error;', '')
 combined=combined.replace('wire req,fr,ff;', 'wire fat_valid,fat_finish,fat_read;wire[7:0] fat_data;wire[31:0] fat_sector;wire[3:0] fat_error;wire req,fr,ff;')
 common=['common/photo_text_crc.v','common/photo_typed_text_a.v','common/photo_typed_text_b.v','common/photo_typed_control_b.v','common/audio_ui/saixian_font_rom.v','tests/title_font_ram_model.v']
 jobs=[('memory',source,common,[]),('uart',uart_source,common+['common/photo_cached_control_a.v','common/photo_control.v','common/photo_uart.v'],[])]
 spec=importlib.util.spec_from_file_location('fat_cases',ROOT/'tools/test_font_fat.py');fat=importlib.util.module_from_spec(spec);spec.loader.exec_module(fat)
 sectors=fat.make(True,2048,1,None)
 (out/'lbas.hex').write_text(''.join(f'{lba:08x}\n' for lba in sorted(sectors)),encoding='ascii')
 (out/'blocks.hex').write_text(''.join(f'{b:02x}\n' for lba in sorted(sectors) for b in sectors[lba]),encoding='ascii')
 jobs.append(('uart_fat',combined,common+['common/photo_cached_control_a.v','common/photo_control.v','common/photo_uart.v','common/photo_font_fat.v'],[f'+sectors={len(sectors)}']))
 prior={r['test']:r for r in json.loads((out/'results.json').read_text())} if args.reuse and (out/'results.json').exists() else {}
 results=[]
 for name,body,files,plusargs in jobs:
  tb=out/(name+'.v');tb.write_text(body,encoding='utf-8');binary=out/(name+'.vvp')
  paths=[tb]+[ROOT/f for f in files]
  hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
  if prior.get(name,{}).get('passed') and prior[name].get('source_sha256')==hashes:
   results.append(prior[name]);print('REUSE verified sources: '+name,flush=True);continue
  result=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-DTYPED_TEXT_SIM','-s','tb','-o',str(binary),*map(str,paths)],capture_output=True,text=True)
  log=result.stdout+result.stderr
  if result.returncode==0:
   result=subprocess.run(['C:/iverilog/bin/vvp.exe','-i',str(binary),*plusargs],cwd=out,capture_output=True,text=True,timeout=600);log+=result.stdout+result.stderr
  (out/(name+'.log')).write_text(log,encoding='utf-8');print(name+': '+log[-600:],flush=True)
  passed=result.returncode==0 and 'PASS typed input' in log and 'FATAL' not in log
  assert hashes=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},'RTL changed during test'
  results.append({'test':name,'passed':passed,'source_sha256':hashes})
  (out/'results.json').write_text(json.dumps(results,indent=2)+'\n',encoding='utf-8')
  if not passed:raise SystemExit('Failed '+name)
if __name__=='__main__':main()
