`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,bv=0;reg[7:0] bd=0;always #5 clk=~clk;
reg frame_tick=0;integer frame=0;
always @(negedge clk)begin frame=frame+1;frame_tick=frame%1000==0;end
wire capture,lv,lr,input_error,busy;wire[255:0] line;
photo_text_input_a #(.HZ(100000)) input_a(clk,rst,bv,bd,lr,capture,lv,line,input_error);
wire ap,bp;wire[159:0] am,bm;reg as=0,bs=0,ar=0,br=0;reg[159:0] ai=0,bi=0;
wire wv;wire[7:0] wi;wire[31:0] wd;wire[4:0] wl;wire[15:0] wm;
reg[31:0] session=1;
photo_text_bridge_a #(.HZ(100000)) bridge_a(clk,rst,frame_tick,busy,session,lv,line,lr,ap,am,as,ar,ai,wv,wi,wd,wl,wm);
wire text_tick;photo_text_tick #(.HZ(100000)) tick_source(clk,rst,text_tick);
wire blv,blr;wire[255:0] bline;wire wp,wa;wire[7:0] gen,ix;wire[4:0] len;wire[31:0] data;wire[15:0] mask;
photo_text_bridge_b #(.HZ(100000)) bridge_b(clk,rst,session,br,bi,bp,bm,bs,blv,bline,blr,wp,gen,ix,len,data,mask,wa,text_tick);
wire req,fr,ff;wire[31:0] addr;reg sv=0,se=0;reg[7:0] sd=0;
photo_text_font_b #(.HZ(100000),.HOLD_CYCLES(1000000)) loader(clk,rst,blv,bline,blr,1'b1,4'd0,req,addr,sv,sd,se,wp,gen,ix,len,data,mask,wa,session,fr,ff,text_tick);
wire[4:0] title_length,ticker_length;reg[6:0] glyph=0;reg[3:0] row=0;wire[15:0] bits;
saixian_font_rom #(.TYPED_TEXT(1),.TITLE_SD(1),.INDEPENDENT_TEXT(1)) font(.typed_mask(wm),.word_valid(wv),.word_index(wi),.word_data(wd),.word_length(wl),.rst(rst),.frame_tick(frame_tick),.title_length(title_length),.ticker_length(ticker_length),.clk(clk),.glyph_id(glyph),.row(row),.bits(bits));
// Deliver complete control packets only after payload and CRC have settled.
integer ac=0,bc=0;reg corrupt=1,drop=1;integer rejected=0,duplicates=0;
always @(posedge clk)begin
 as<=0;bs<=0;ar<=0;br<=0;
 if(!rst)begin
  if(ac==0 && ap && !as)begin ai<=ai;bi<=am;as<=1;ac<=12;if(corrupt && am[159:152]==40)begin bi<=am^(160'd1<<64);corrupt<=0;rejected<=rejected+1;end end
  else if(ac!=0)begin ac<=ac-1;if(ac==1)br<=1;end
  if(bc==0 && bp && !bs)begin ai<=bm;bs<=1;bc<=12;end
  else if(bc!=0)begin bc<=bc-1;if(bc==1)begin
   if(drop && ai[159:152]==41)begin drop<=0;duplicates<=duplicates+1;end else ar<=1;
  end end
 end
end
reg[7:0] file_bytes[0:287743];integer ss=0,pos=0,base=0;
always @(posedge clk)begin
 sv<=0;se<=0;
 if(req)begin if(ss!=0)$fatal(1,"overlap font file read");base<=(addr-2209)*512;pos<=0;ss<=1;end
 if(ss==1)begin sv<=1;sd<=file_bytes[base+pos];if(pos==511)ss<=2;else pos<=pos+1;end
 if(ss==2)ss<=3;if(ss==3)begin se<=1;ss<=0;end
end
// Respect the parser's documented byte processing interval; the physical
// 115200-baud receiver leaves far more than these 32 clocks per byte.
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
 oldgen=gen;$display("before 16 gen=%d selected=%d",gen,loader.selected);prefix("1");for(i=0;i<16;i=i+1)begin byte_send("A"+i);expected[i]="A"+i;end done;check(16,0);
 oldgen=gen;prefix("1");byte_send("Z");done;expected[0]="Z";check(1,0);
 oldgen=gen;prefix("1");done;expected[0]=128+(8'hd6-161)*94+(8'hd0-161);expected[1]=128+(8'hb9-161)*94+(8'hfa-161);expected[2]=49;check(3,2);
 oldgen=gen;prefix("0");done;check(0,0);
 oldgen=gen;prefix("2");byte_send("P");done;expected[0]="P";check(1,0);
 oldgen=gen;prefix("3");byte_send("^");byte_send("Q");done;expected[0]="Q";check(1,1);
 // Check the actual read-port bitmap in both phases of a blinking glyph.
 glyph=112;row=7;wait(!font.flash_phase[5]);repeat(3)@(negedge clk);
 if(bits!==font.u_font_bram.memory[1792+7])$fatal(1,"blink on did not read glyph");
 wait(font.flash_phase[5]);repeat(3)@(negedge clk);if(bits!==0)$fatal(1,"blink off not transparent");
 oldgen=gen;session=2;expected[0]="Q";check(1,1);
 // Natural carousel timing must select the next nonempty slot, skipping 0/1.
 oldgen=gen;expected[0]="P";check(1,0);
 if(!rejected || !duplicates || ff)$fatal(1,"CRC/retry coverage missing");
 // Missing font data rejects the new text without locking A's transaction.
 force loader.fs_error=4'd1;repeat(4)@(negedge clk);
 prefix("0");byte_send("X");done;wait(!bridge_a.active && !lv);
 if(!loader.fault || wp || ticker_length!=1)$fatal(1,"font fault locked input or replaced displayed glyphs");
 $display("PASS typed input, 4-part CRC rejection, dropped ACK retry, 16-character replacement/delete, empty-slot skipping and blink metadata");$finish;
end
initial begin #150000000;$fatal(1,"typed text timeout ap=%b bp=%b A=%d B=%d loader=%d",ap,bp,bridge_a.part,bridge_b.expected,loader.state);end
endmodule
