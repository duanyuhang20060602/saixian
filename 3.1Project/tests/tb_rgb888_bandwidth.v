`timescale 1ns/1ps
// Real 75 MHz pixel / 50 MHz memory clocks, real asynchronous IP FIFOs.
// The SDRAM service model returns one word per cycle after 12 clocks.
// It deliberately gives the old arbiter an optimistic, stall-free memory.
module tb_rgb888_bandwidth;
reg mem_clk=0,pixel_clk=0,rst=1;
always #10 mem_clk=~mem_clk;
always #6.666667 pixel_clk=~pixel_clk;
reg read_req=0,write_req=0,write_en=0;wire ack,wack,finish,wfinish,empty,full,rd,wr;
`ifdef REFRESH_STRESS
reg refresh_active=0,refresh_pending=0;
reg [4:0] refresh_left=0;
integer refresh_tick=0,refreshes=0;
always @(posedge mem_clk)begin
 if(rst)begin refresh_active<=0;refresh_pending<=0;refresh_left<=0;refresh_tick<=0;refreshes<=0;end
 else begin
  refresh_tick<=refresh_tick+1;
  if(refresh_tick%765==0)refresh_pending<=1;
  if(refresh_active)begin
   if(refresh_left==0)refresh_active<=0;
   else refresh_left<=refresh_left-1'b1;
  end else if(refresh_pending && !rd && !wr)begin
   refresh_active<=1;refresh_left<=19;refresh_pending<=0;refreshes<=refreshes+1;
  end
  if(refresh_active && (rd || wr))$fatal(1,"SDRAM command sent during refresh");
 end
end
`else
wire refresh_active=1'b0;
`endif
wire [20:0] ra,wa;wire [31:0] pixels,wd;wire [3:0] dm;
reg [11:0] pipe_valid=0;reg [31:0] pipe_data[0:11];integer i;
always @(posedge mem_clk)begin
 if(rst)pipe_valid<=0;
 else begin pipe_valid<={pipe_valid[10:0],rd};pipe_data[0]<=ra;
 for(i=1;i<12;i=i+1)pipe_data[i]<=pipe_data[i-1];
 if(rd&&wr)$fatal(1,"Read/write commands overlap");
 end
end
integer x=0,y=720,frames=0,misses=0,pops=0,writes=0;reg running=0;
wire de=running && y<720 && x<1280;
wire need=de && x%4!=3;
wire pop=need && !empty;
always @(posedge pixel_clk)if(running)begin
 if(need)begin if(empty)misses=misses+1;else pops=pops+1;end
 if(x==1649)begin x=0;if(y==749)begin y=0;frames=frames+1;end else y=y+1;end else x=x+1;
end
frame_read_write dut(.high_color(1'b1),.rst(rst),.mem_clk(mem_clk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(refresh_active),.Sdr_busy(1'b0),
 .App_rd_en(rd),.App_rd_addr(ra),.Sdr_rd_en(pipe_valid[11]),.Sdr_rd_dout(pipe_data[11]),
 .read_clk(pixel_clk),.read_req(read_req),.read_req_ack(ack),.read_finish(finish),
 .read_addr_0(21'd0),.read_addr_1(21'd691200),.read_addr_2(21'd0),.read_addr_3(21'd0),.read_addr_index(2'd0),.read_len(21'd691200),
 .read_en(pop),.read_data(pixels),.read_fifo_empty(empty),
 .slide_active(1'b0),.slide_old_index(2'd0),.slide_new_index(2'd1),.slide_offset(11'd0),.slide_right(1'b1),.transition_mode(3'd0),.buffer0_vga(1'b0),.buffer1_vga(1'b0),
 .App_wr_en(wr),.App_wr_addr(wa),.App_wr_din(wd),.App_wr_dm(dm),
 .write_clk(mem_clk),.write_req(write_req),.write_req_ack(wack),.write_finish(wfinish),
 .write_addr_0(21'd0),.write_addr_1(21'd691200),.write_addr_2(21'd0),.write_addr_3(21'd0),.write_addr_index(2'd1),.write_len(21'd691200),
 .write_vga(1'b0),.write_en(write_en),.write_data(32'h12345678),.write_fifo_full(full));
integer tick=0;
always @(negedge mem_clk)begin
 tick=tick+1;
 // Model link backpressure: producer never overruns a full write FIFO.
 write_en=running && y<720 && writes<691200 && !full && tick%2==0;
 if(write_en)writes=writes+1;
end
initial begin
 repeat(8)@(negedge mem_clk);rst=0;repeat(8)@(negedge mem_clk);
 read_req=1;write_req=1;wait(ack&&wack);@(negedge mem_clk);read_req=0;write_req=0;wait(!ack&&!wack);
 @(negedge pixel_clk);running=1;
 wait(frames==1 && y==720 && x==0);@(negedge pixel_clk);running=0;
 $display("RGB888 concurrent prefetch: misses=%0d pops=%0d producer_words=%0d",misses,pops,writes);
`ifdef EXPECT_BASELINE_FAILURE
 if(misses==0)$fatal(1,"Baseline did not reproduce starvation");
 $display("PASS baseline reproduces display starvation");
`else
 if(misses!=0 || pops!=691200)$fatal(1,"Display FIFO starved during background prefetch");
 if(writes<10000)$fatal(1,"Prefetch made no progress");
 $display("PASS RGB888 display has zero underflow while prefetch makes progress");
`ifdef REFRESH_STRESS
 if(refreshes<100)$fatal(1,"Refresh stress was not exercised");
 $display("PASS %0d refresh windows with zero commands during refresh",refreshes);
`endif
`endif
 $finish;
end
initial begin #20000000;$fatal(1,"Bandwidth timeout");end
endmodule
