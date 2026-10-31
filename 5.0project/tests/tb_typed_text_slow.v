`timescale 1ns/1ps
module tb;
reg slow_clk=0;always #11 slow_clk=~slow_clk;
reg clk=0,rst=1,bv=0;reg[7:0] bd=0;always #5 clk=~clk;
reg frame_tick=0;integer frame=0;
always @(negedge clk)begin frame=frame+1;frame_tick=frame%1000==0;end
wire capture,lv,lr,input_error,busy;wire[255:0] line;
photo_text_input_a #(.HZ(100000)) input_a(clk,rst,bv,bd,lr,capture,lv,line,input_error);
wire ap,bp;wire[159:0] am,bm;wire as,bs,ar,br;wire[159:0] ai,bi;
wire wv;wire[7:0] wi;wire[31:0] wd;wire[4:0] wl;wire[15:0] wm;
reg[31:0] session=1;wire[31:0] a_session,b_session;
photo_text_bridge_a #(.HZ(100000)) bridge_a(clk,rst,frame_tick,busy,a_session,lv,line,lr,ap,am,as,ar,ai,wv,wi,wd,wl,wm);
wire text_tick;photo_text_tick #(.HZ(100000)) tick_source(clk,rst,text_tick);
wire blv,blr;wire[255:0] bline;wire wp,wa;wire[7:0] gen,ix;wire[4:0] len;wire[31:0] data;wire[15:0] mask;
photo_text_bridge_b #(.HZ(100000)) bridge_b(clk,rst,b_session,br,bi,bp,bm,bs,blv,bline,blr,wp,gen,ix,len,data,mask,wa,text_tick);
wire fat_valid,fat_finish,fat_read;wire[7:0] fat_data;wire[31:0] fat_sector;wire[3:0] fat_error;wire req,fr,ff;wire[31:0] addr;reg sv=0,se=0;reg[7:0] sd=0;
photo_text_font_b #(.HZ(100000),.HOLD_CYCLES(1000000)) loader(clk,rst,blv,bline,blr,1'b1,4'd0,req,addr,fat_valid,fat_data,fat_finish,wp,gen,ix,len,data,mask,wa,b_session,fr,ff,text_tick);
wire[4:0] title_length,ticker_length;reg[6:0] glyph=0;reg[3:0] row=0;wire[15:0] bits;
saixian_font_rom #(.TYPED_TEXT(1),.TITLE_SD(1),.INDEPENDENT_TEXT(1)) font(.typed_mask(wm),.word_valid(wv),.word_index(wi),.word_data(wd),.word_length(wl),.rst(rst),.frame_tick(frame_tick),.title_length(title_length),.ticker_length(ticker_length),.clk(clk),.glyph_id(glyph),.row(row),.bits(bits));
wire a_tx,b_tx;
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
reg[7:0] file_bytes[0:287743];

reg pv=0,pe=0;reg[7:0] pd=0;
photo_font_file_b #(.SLOW_HZ(500000),.ADDR_BITS(27)) fs(clk,rst,slow_clk,rst,1'b1,req,addr,fat_valid,fat_data,fat_finish,fat_error,fat_read,fat_sector,pv,pd,pe);
reg[31:0] lbas[0:2047];reg[7:0] blocks[0:1048575];integer sector_count,j,match,ps=0,pp=0,pbase=0,gap=0;
initial begin
 if(!$value$plusargs("sectors=%d",sector_count))$fatal;
 $readmemh("lbas.hex",lbas,0,sector_count-1);$readmemh("blocks.hex",blocks,0,sector_count*512-1);
end
always @(posedge clk)begin
 pv<=0;pe<=0;
 if(fat_read)begin
  if(ps!=0)$fatal(1,"overlap physical read");match=-1;for(j=0;j<sector_count;j=j+1)if(lbas[j]==fat_sector)match=j;
  if(match<0)$fatal(1,"unexpected physical LBA %d",fat_sector);pbase<=match*512;pp<=0;ps<=1;gap<=0;
 end
 if(ps==1)begin if(gap!=0)gap<=gap-1;else begin gap<=15;pv<=1;pd<=blocks[pbase+pp];if(pp==511)begin pe<=1;ps<=0;end else pp<=pp+1;end end
 if(ps==2)ps<=3;if(ps==3)begin pe<=1;ps<=0;end
 if(fat_error!=0)$fatal(1,"FAT font error %d",fat_error);
end
task byte_send;input[7:0] b;begin @(negedge clk);bv=1;bd=b;@(negedge clk);bv=0;repeat(32)@(negedge clk);end endtask
task prefix;input[7:0] s;begin wait(!bridge_a.active && !lv && blr);byte_send("@");byte_send(s);byte_send(":");end endtask
task done;begin byte_send(13);byte_send(10);end endtask
always @(posedge clk)begin
 if(lv && lr)$display("input line slot=%d len=%d",line[255:254],line[253:249]);
 if(blv && blr)$display("B line slot=%d len=%d",bline[255:254],bline[253:249]);
 if(loader.committing && loader.commit_index==15)$display("commit slot=%d len=%d",loader.saved_line[255:254],loader.saved_line[253:249]);
 if(wv && (wi==128 || wi==255))$display("word gen=%d index=%d len=%d time=%t",bridge_a.generation,wi,wl,$time);
 if(input_error)$display("input error");
end
integer i,k,oldgen;reg[13:0] expected[0:15];reg[15:0] e;
task check;input integer n;input[15:0] m;begin
 wait(gen!=oldgen);wait(loader.state==6);wait(loader.state==2);repeat(1010)@(negedge clk);
 if(ticker_length!==n || font.flash_mask!==m)begin $display("gen=%d Agen=%d expected=%d selected=%d lengths=%d %d candidate=%d complete=%b",gen,bridge_a.generation,bridge_a.expected,loader.selected,loader.lengths[0],loader.lengths[1],font.candidate_ticker_length,font.complete);$fatal(1,"length/blink mismatch got %d mask %h expected %d %h",ticker_length,font.flash_mask,n,m);end
 for(k=0;k<256;k=k+1)begin
  if(k/16<n)e={file_bytes[512+expected[k/16]*32+(k%16)*2],file_bytes[513+expected[k/16]*32+(k%16)*2]};else e=0;
  if(font.u_font_bram.memory[1792+k]!==e)$fatal(1,"independent font byte mismatch row=%d got=%h expected=%h",k,font.u_font_bram.memory[1792+k],e);
 end
 glyph=37;row=5;repeat(3)@(negedge clk);if(bits!==16'ha55a)$fatal(1,"static font overwritten");
 $display("PASS selected line length=%0d mask=%h, all 256 glyph rows and original ROM",n,m);
end endtask
initial begin
 $readmemh("font.hex",file_bytes);repeat(5)@(negedge clk);rst=0;wait(fr);oldgen=gen;
 prefix("0");byte_send(8'hd6);byte_send(8'hd0);byte_send("^");byte_send(8'hb9);byte_send(8'hfa);byte_send("1");done;
 expected[0]=128+(8'hd6-161)*94+(8'hd0-161);expected[1]=128+(8'hb9-161)*94+(8'hfa-161);expected[2]=49;check(3,2);
 if(!rejected || !duplicates || ff || fs.fast_overflow || fs.slow_overflow)$fatal(1,"CRC/retry coverage or CDC error");
 $display("PASS slow FAT UART: Chinese glyphs, exact 256 rows, blink metadata, CRC rejection and dropped ACK retry");$finish;
end
initial begin #150000000;$fatal(1,"typed text timeout ap=%b bp=%b A=%d B=%d loader=%d",ap,bp,bridge_a.part,bridge_b.expected,loader.state);end
endmodule
