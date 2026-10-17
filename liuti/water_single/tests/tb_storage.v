`timescale 1ns/1ps
module tb;
reg sd=0,mem=0,pixel=0;always #10 sd=~sd;always #10 mem=~mem;always #6.667 pixel=~pixel;
reg rst=1,wreq=0,pv=0,rreq=0;reg[23:0] rgb=0;reg[1:0] slot=0;
wire packed_valid,small_valid,full,overflow,wack,wfinish,re,we,rack,done,empty;
wire[31:0] packed_data,small_data,wd,rd,timeouts;wire[20:0] wa,ra;wire[3:0] mask;
water_pack packer(.clk(sd),.rst(rst),.write_req(wreq),.pixel_valid(pv),.pixel(rgb),.full(full),
 .valid(packed_valid),.data(packed_data),.overflow(overflow),.small_valid(small_valid),.small_data(small_data));
reg[31:0] ram[0:131071];reg[13:0] vv=0;reg[20:0] aq[0:13];
integer reads=0,writes=0,received=0,read_case=0,write_case=0,k;
wire pop=!empty;
frame_read_write #(.FRAME_WIDTH(640),.FRAME_HEIGHT(64)) dut(
 .rst(rst),.mem_clk(mem),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),
 .App_rd_en(re),.App_rd_addr(ra),.Sdr_rd_en(vv[13]),.Sdr_rd_dout(ram[aq[13]]),
 .read_clk(pixel),.read_req(rreq),.read_req_ack(rack),.read_finish(done),
 .read_addr_0(21'd0),.read_addr_1(21'd65536),.read_addr_2(21'd0),.read_addr_3(21'd0),
 .read_addr_index(2'd0),.read_len(21'd30720),.read_en(pop),.read_data(rd),.read_fifo_empty(empty),
 .slide_active(read_case==1),.slide_old_index(2'd0),.slide_new_index(2'd1),.slide_offset(11'd320),
 .slide_right(1'b0),.transition_mode(4'd0),.buffer0_vga(1'b0),.buffer1_vga(1'b0),.force_effect_plane(1'b0),.water_cfg(77'd248),.read_timeouts(timeouts),
 .App_wr_en(we),.App_wr_addr(wa),.App_wr_din(wd),.App_wr_dm(mask),
 .write_clk(sd),.write_req(wreq),.write_req_ack(wack),.write_finish(wfinish),
 .write_addr_0(21'd0),.write_addr_1(21'd65536),.write_addr_2(21'd0),.write_addr_3(21'd0),
 .write_addr_index(slot),.write_len(21'd40960),.write_vga(1'b0),.write_en(packed_valid),.write_data(packed_data),
 .small_write_en(small_valid),.small_write_data(small_data),.write_fifo_full(full));
sdram_contract read_contract(mem,rst,re,ra);sdram_contract write_contract(mem,rst,we,wa);
function[15:0] pattern;input integer x,y,seed;reg[4:0] r,b;reg[5:0] g;
 begin r=x+y+seed*7;g=x*3+y*5+seed;b=x*7+y+seed*3;pattern={r,g,b};end
endfunction
function[15:0] avg;input[15:0] a,b;reg[5:0] r,bl;reg[6:0] g;
 begin r={1'b0,a[15:11]}+{1'b0,b[15:11]}+1;g={1'b0,a[10:5]}+{1'b0,b[10:5]}+1;bl={1'b0,a[4:0]}+{1'b0,b[4:0]}+1;avg={r[5:1],g[6:1],bl[5:1]};end
endfunction
function[15:0] smallpixel;input integer x,y,seed;reg[15:0] a,b,c;integer r,g,bl;
 begin a=pattern(x==0 ? 0:2*x-1,y,seed);b=pattern(2*x,y,seed);c=pattern(2*x+1,y,seed);
 r=((a>>11)+2*(b>>11)+(c>>11)+2)/4;g=(((a>>5)&63)+2*((b>>5)&63)+((c>>5)&63)+2)/4;bl=((a&31)+2*(b&31)+(c&31)+2)/4;
 smallpixel=(r<<11)|(g<<5)|bl;end endfunction
function[15:0] reconstructed;input integer x,y,seed;reg[15:0] a,b;
 begin a=smallpixel(x/2,y,seed);b=smallpixel(x==1279 ? 639:x/2+1,y,seed);reconstructed=x%2 ? avg(a,b):a;end
endfunction
function[31:0] expected;input integer n,seed;integer x,y;
 begin x=n%640;y=63-n/640;
 expected=seed==0 ? {pattern(2*x,y,seed),pattern(2*x+1,y,seed)}:{reconstructed(2*x,y,seed),reconstructed(2*x+1,y,seed)};end
endfunction
integer localaddr,yy,xx,seed;reg[31:0] want;
always @(posedge mem)begin
 vv<={vv[12:0],re};aq[0]<=ra;for(k=1;k<14;k=k+1)aq[k]<=aq[k-1];
 if(we&&re)$fatal(1,"SDRAM read/write overlap");
 if(we)begin
  seed=wa>=65536;localaddr=wa-seed*65536;
  if(localaddr<40960)begin yy=localaddr/640;xx=localaddr%640;want={pattern(2*xx,63-yy,seed),pattern(2*xx+1,63-yy,seed)};end
  else begin localaddr=localaddr-40960;yy=localaddr/320;xx=localaddr%320;want={smallpixel(2*xx,63-yy,seed),smallpixel(2*xx+1,63-yy,seed)};end
  if(yy>=64||wd!==want)$fatal(1,"dual-plane write address%0d data%h expected%h",wa,wd,want);
  ram[wa]<=wd;writes=writes+1;
 end
 if(re)reads=reads+1;
end
always @(posedge pixel)begin #1;
 if(!rst&&dut.read_buf.valid)begin
  if(rd!==expected(received,read_case))$fatal(1,"storage readback case%0d word%0d got%h expected%h",read_case,received,rd,expected(received,read_case));
  received=received+1;
 end
end
task write_image;input integer seed;integer n;reg[15:0] p;begin
 write_case=seed;slot=seed;@(negedge sd);wreq=1;wait(wack);@(negedge sd);wreq=0;
 repeat(16)@(negedge sd);
 for(n=0;n<81920;n=n+1)begin
  p=pattern(n%1280,n/1280,seed);rgb={p[15:11],3'd0,p[10:5],2'd0,p[4:0],3'd0};pv=1;
  @(negedge sd);pv=0;repeat(15)@(negedge sd);
 end
 wait(wfinish);repeat(10)@(negedge sd);
 if(overflow)$fatal(1,"write FIFO overflow");
end endtask
task read_image;begin
 received=0;@(negedge pixel);rreq=1;wait(rack);@(negedge pixel);rreq=0;
 wait(done);wait(received==30720);repeat(10)@(negedge pixel);
end endtask
initial begin
 repeat(8)@(negedge sd);rst=0;write_image(0);
 fork write_image(1);read_image;join
 read_case=1;read_image;
 if(timeouts||writes!=122880)$fatal(1,"storage counts/timeout");
 $display("PASS dual-plane storage: 122880 exact native/filtered writes, 61440 readback words, concurrent loading, vertical flip, aligned SDR bursts");$finish;
end
initial begin #70000000;$fatal(1,"storage timeout writes%0d reads%0d outputs%0d",writes,reads,received);end
endmodule
