`timescale 1ns/1ps
module read_align_case #(parameter APPLY_ALIGN=1)(output reg done=0);
localparam STAGE=0;reg wc=0,mc=0,pc=0;always #5 wc=~wc;always #10 mc=~mc;always #6.666667 pc=~pc;
reg rst=1,ft=0,rreq=0,ren=0;wire wreq,we,wa,full,wfinish,local_done,ra,empty;
wire [31:0] source,data,md,wd;wire [20:0] raddr,waddr;wire mr,mw;wire [3:0] dm;
reg [31:0] memory[0:4095];reg [15:0] expected[0:921599];reg [9:0] rv=0;reg [31:0] rpipe[0:9];
wire [31:0] delayed_data,corrected_data;
photo_sdram_read_align aligner(.clk(mc),.rst(rst),.raw_data(rpipe[8]),.aligned_data(delayed_data));
assign corrected_data=APPLY_ALIGN ? delayed_data:rpipe[8];
function [31:0] word_ref;input integer k;begin word_ref=32'hA5000000 | k;end endfunction
function integer read_index;input integer k;begin read_index=(STAGE==4 || (STAGE==5 && k%4==3)) ? ((k+1)%4096):k;end endfunction
localparam FIRST_BAD=STAGE==4 ? 0:STAGE==5 ? 3:777;
integer writes=0,reads=0,i;reg pop=0;reg started=0;reg phase=0;
wire bad;wire [20:0] bad_address;wire [31:0] exp_word,actual_word;
reg corrupt=0;
photo_readback_monitor monitor(.clk(pc),.rst(rst),.req(rreq),.pop(ren && !empty),.data(data ^ (STAGE==3 && reads==777 ? 32'd1:32'd0)),.bad(bad),.address(bad_address),.expected(exp_word),.actual(actual_word));
wire wb,rb;wire [20:0] wa_bad,ra_bad;wire [31:0] wx,wy,rx,ry;wire wc_clear,rc_clear;
reg [31:0] wsample,rsample;
assign wc_clear=dut.write_fifo_aclr;assign rc_clear=dut.read_fifo_aclr;
always @(posedge mc)begin
 if(mw)wsample<=wd ^ (STAGE==1 && writes==777 ? 32'd1:32'd0);
 if(rv[9])rsample<=corrected_data;
end
photo_readback_monitor wm(.clk(mc),.rst(rst),.req(wc_clear),.pop(mw),.data(wsample),.bad(wb),.address(wa_bad),.expected(wx),.actual(wy));
photo_readback_monitor rm(.clk(mc),.rst(rst),.req(rc_clear),.pop(rv[9]),.data(rsample),.bad(rb),.address(ra_bad),.expected(rx),.actual(ry));
photo_local_frame_writer #(.GAP_CYCLES(1),.FRAME_WORDS(4096)) gen(.clk(wc),.rst(rst),.init_done(1'b1),.ack(wa),.full(full),.finish_toggle(ft),.req(wreq),.we(we),.data(source),.done(local_done));
frame_read_write #(.WRITE_V_FLIP(0),.FRAME_WIDTH(640),.FRAME_HEIGHT(720),.BURST_SIZE(256)) dut(
 .rst(rst),.mem_clk(mc),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),
 .App_rd_en(mr),.App_rd_addr(raddr),.Sdr_rd_en(rv[9]),.Sdr_rd_dout(corrected_data),
 .read_clk(pc),.read_req(rreq),.read_req_ack(ra),.read_finish(),.read_addr_0(21'd0),.read_addr_1(21'd0),.read_addr_2(21'd0),.read_addr_3(21'd0),.read_addr_index(2'd0),.read_len(21'd4096),.read_en(ren),.read_data(data),.read_fifo_empty(empty),
 .slide_active(1'b0),.slide_old_index(2'd0),.slide_new_index(2'd0),.slide_offset(11'd0),.slide_right(1'b0),.transition_mode(3'd0),.buffer0_vga(1'b0),.buffer1_vga(1'b0),
 .App_wr_en(mw),.App_wr_addr(waddr),.App_wr_din(wd),.App_wr_dm(dm),
 .write_clk(wc),.write_req(wreq),.write_req_ack(wa),.write_finish(wfinish),.write_addr_0(21'd0),.write_addr_1(21'd0),.write_addr_2(21'd0),.write_addr_3(21'd0),.write_addr_index(2'd0),.write_len(21'd4096),.write_vga(1'b0),.write_en(we && !full),.write_data(source),.write_fifo_full(full));
always @(posedge mc)begin
 if(rst)begin rv<=0;ft<=0;writes<=0;end
 else begin
  if(wfinish)ft<=~ft;
  rv<={rv[8:0],mr};rpipe[0]<=memory[(raddr%4096)] ^ (STAGE==2 && raddr==777 ? 32'd1:32'd0);
  for(i=9;i>0;i=i-1)rpipe[i]<=rpipe[i-1];
  if(mw && mr)$fatal(1,"simultaneous read/write");
  if(mw)begin
   if(waddr!==writes)$fatal(1,"write address mismatch");
   if(wd!==word_ref(writes))$fatal(1,"actual write FIFO word mismatch addr=%d data=%h",waddr,wd);
   memory[waddr]<=wd ^ (STAGE==1 && writes==777 ? 32'd1:32'd0);writes<=writes+1;
  end
 end
end
always @(negedge pc)begin
 if(!started)ren=0;
 else begin phase=~phase;ren=phase && reads<4096;end
end
always @(posedge pc)begin
 if(rst)begin pop<=0;reads<=0;end
 else begin
  pop<=ren && !empty;
  if(ren && empty && reads<4096)$fatal(1,"display rate read FIFO underflow word=%d",reads);
  if(pop)begin
   if(data!==(word_ref(APPLY_ALIGN ? reads:((reads+1)%4096)) ^ ((STAGE==1 || STAGE==2) && reads==777 ? 32'd1:32'd0)))$fatal(1,"actual read FIFO word mismatch index=%d got=%h",reads,data);
   reads<=reads+1;
  end
 end
end
initial begin

 repeat(10)@(negedge wc);rst=0;
 wait(gen.state==3);@(negedge wc);gen.yy=0;wm.yy=0;wm.index=0;
 wait(local_done);if(writes!=4096)$fatal(1,"write length");
 @(negedge pc);rreq=1;wait(ra);@(negedge pc);rreq=0;wait(!ra);
 monitor.yy=0;monitor.index=0;rm.yy=0;rm.index=0;
 wait(dut.wrusedw>=256);repeat(10)@(negedge pc);started=1;
 wait(reads==500);if(APPLY_ALIGN && bad)$fatal(1,"false compare failure");corrupt=1;
 wait(reads==4096);started=0;repeat(10)@(negedge pc);
 if(wb || rb!==!APPLY_ALIGN || bad!==!APPLY_ALIGN)$fatal(1,"alignment flags APPLY=%d wb=%b rb=%b bad=%b",APPLY_ALIGN,wb,rb,bad);
 if(!APPLY_ALIGN && (ra_bad!=0 || rx!=32'hA5000000 || ry!=32'hA5000001 || bad_address!=0 || exp_word!=32'hA5000000 || actual_word!=32'hA5000001))$fatal(1,"early-data baseline signature");
 $display("PASS early-data model APPLY_ALIGN=%d: 4096 words, 16 bursts, first/last word, FIFO wrap, 100/50/75MHz; baseline error at0=%h, aligned clean",APPLY_ALIGN,actual_word);done=1;
end
initial begin #2000000;$fatal(1,"actual FIFO timeout writes=%d reads=%d",writes,reads);end
endmodule


module tb_read_data_align;
wire a,b;
read_align_case #(.APPLY_ALIGN(0)) baseline(a);
read_align_case #(.APPLY_ALIGN(1)) aligned(b);
initial begin wait(a && b);$finish;end
endmodule
