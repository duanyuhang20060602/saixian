`timescale 1ns/1ps
// A refresh colliding with burst setup must not consume a FIFO word or an
// address. The memory drops commands while refreshing, as the IP contract
// requires the caller to suppress them. Inspect the completed destination
// frame, not only displayed underflow: a dropped write persists on screen.
module frame_refresh_case #(parameter HC=1,DISPLAY=1)(output reg done=0);
localparam [20:0] WORDS=HC ? 3840:2560;
reg mc=0,wc=0,pc=0,rst=1,rreq=0,wreq=0,run=0;
always #10 mc=~mc;
always #9 wc=~wc;
always #6.666667 pc=~pc;
reg [31:0] tick=0;
reg refreshing=0,refresh_pending=0;
reg [4:0] refresh_left=0;
wire rd,wr,ack,wack,rf,wf,empty,full;
wire [20:0] ra,wa;wire [31:0] data,wd;wire [3:0] dm;
reg [31:0] destination[0:WORDS-1];
reg [11:0] valid_pipe=0;
reg [31:0] data_pipe[0:11];
integer produced=0,popped=0,written=0,attempts=0,read_commands=0,corrupt=0,i;
reg pop_pending=0;reg [31:0] expected_read=0;
wire source_we=run && !full && produced<WORDS;
wire pop=DISPLAY && run && !empty && popped<WORDS;
function [31:0] pattern;input integer n;begin pattern=32'haf370000 ^ (n*32'h00012379);end endfunction
frame_read_write #(.WRITE_V_FLIP(0),.FRAME_WIDTH(640),.FRAME_HEIGHT(4),.BURST_SIZE(256)) dut(
 .rst(rst),.mem_clk(mc),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(refreshing),.Sdr_busy(1'b0),
 .App_rd_en(rd),.App_rd_addr(ra),.Sdr_rd_en(valid_pipe[11]),.Sdr_rd_dout(data_pipe[11]),
 .read_clk(pc),.read_req(rreq),.read_req_ack(ack),.read_finish(rf),
 .read_addr_0(21'd0),.read_addr_1(21'd8192),.read_addr_2(21'd0),.read_addr_3(21'd0),.read_addr_index(2'd0),.read_len(WORDS),
 .read_en(pop && tick[1:0]!=0),.read_data(data),.read_fifo_empty(empty),
 .slide_active(1'b0),.slide_old_index(2'd0),.slide_new_index(2'd1),.slide_offset(11'd0),.slide_right(1'b0),.transition_mode(3'd0),.buffer0_vga(1'b0),.buffer1_vga(1'b0),
 .App_wr_en(wr),.App_wr_addr(wa),.App_wr_din(wd),.App_wr_dm(dm),
 .write_clk(wc),.write_req(wreq),.write_req_ack(wack),.write_finish(wf),
 .write_addr_0(21'd0),.write_addr_1(21'd8192),.write_addr_2(21'd0),.write_addr_3(21'd0),.write_addr_index(2'd1),.write_len(WORDS),
 .write_vga(1'b0),.write_en(source_we),.write_data(pattern(produced)),.write_fifo_full(full));
always @(posedge wc)if(source_we)produced<=produced+1;
always @(posedge mc)begin
 if(rst)begin tick<=0;valid_pipe<=0;refreshing<=0;refresh_pending<=0;refresh_left<=0;end
 else begin
  tick<=tick+1;
  if(tick%211==0)refresh_pending<=1;
  // The controller grants a refresh only at an idle command boundary.
  // It can coincide with the client's FIFO-check -> burst-setup transition.
  if(refreshing)begin
   if(refresh_left==0)refreshing<=0;
   else refresh_left<=refresh_left-1'b1;
  end else if(refresh_pending && !rd && !wr)begin
   refreshing<=1;refresh_left<=19;refresh_pending<=0;
  end
  if(rd && wr)$fatal(1,"read/write commands overlap HC=%0d",HC);
  valid_pipe<={valid_pipe[10:0],rd && !refreshing};
  data_pipe[0]<=pattern(ra);
  for(i=1;i<12;i=i+1)data_pipe[i]<=data_pipe[i-1];
  if((rd || wr) && refreshing)attempts=attempts+1;
  if(rd)read_commands=read_commands+1;
  if(wr && !refreshing)begin
   if(wa<8192 || wa>=8192+WORDS)$fatal(1,"write outside destination");
   destination[wa-8192]<=wd;written=written+1;
  end
 end
end
always @(posedge pc)begin
 if(rst)pop_pending<=0;
 else begin
`ifndef EXPECT_REFRESH_FAILURE
  if(pop_pending && data!==pattern(popped-1))$fatal(1,"read word mismatch HC=%0d n=%0d",HC,popped-1);
`endif
  pop_pending<=pop && tick[1:0]!=0;
  if(pop && tick[1:0]!=0)popped=popped+1;
 end
end
initial begin
 for(i=0;i<WORDS;i=i+1)destination[i]=32'hffffffff;
 repeat(8)@(negedge mc);rst=0;wreq=1;rreq=DISPLAY;
 wait((!DISPLAY || ack) && wack);@(negedge mc);wreq=0;rreq=0;
 wait((!DISPLAY || !ack) && !wack);repeat(8)@(negedge mc);run=1;
 wait(wf);repeat(20)@(negedge mc);
 for(i=0;i<WORDS;i=i+1)if(destination[i]!==pattern(i))corrupt=corrupt+1;
`ifdef EXPECT_REFRESH_FAILURE
 if(attempts==0 || corrupt==0)$fatal(1,"baseline did not reproduce persistent corruption HC=%0d",HC);
 $display("PASS baseline reproduces persistent frame corruption RGB%0d display=%0d: %0d commands during refresh, %0d corrupt destination words",HC ? 888:565,DISPLAY,attempts,corrupt);done=1;
`else
 if(attempts!=0)$fatal(1,"refresh collision HC=%0d: %0d commands sent during refresh; written=%0d/%0d",HC,attempts,written,WORDS);
 if(written!=WORDS)$fatal(1,"missing destination words HC=%0d written=%0d",HC,written);
 for(i=0;i<WORDS;i=i+1)if(destination[i]!==pattern(i))$fatal(1,"persistent frame corruption HC=%0d word=%0d got=%h expected=%h",HC,i,destination[i],pattern(i));
 if(DISPLAY)wait(popped==WORDS);
 repeat(5)@(negedge pc);
 if(read_commands!=(DISPLAY ? WORDS:0))$fatal(1,"wrong read count");
 $display("PASS refresh-safe RGB%0d display=%0d: %0d destination words intact, %0d read words intact",HC ? 888:565,DISPLAY,WORDS,popped);done=1;
`endif
end
initial begin #3000000;$fatal(1,"refresh timeout HC=%0d producer=%0d writes=%0d reads=%0d",HC,produced,written,popped);end
endmodule
module tb_frame_refresh;
wire a,b,c,d;
frame_refresh_case #(.HC(0)) normal(a);frame_refresh_case #(.HC(1)) precise(b);
frame_refresh_case #(.HC(0),.DISPLAY(0)) boot_normal(c);
frame_refresh_case #(.HC(1),.DISPLAY(0)) boot_precise(d);
initial begin wait(a && b && c && d);$finish;end
endmodule
