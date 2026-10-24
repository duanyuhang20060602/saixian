`timescale 1ns/1ps
// Actual A wrapper, real asynchronous FIFOs and 75/50/100 MHz clocks.
// RGB565 display, background image writes and thumbnail reads compete.
module tb_thumbnail_bandwidth;
reg mc=0,pc=0,lc=0,rst=1,running=0;
always #10 mc=~mc;
always #6.666667 pc=~pc;
always #5 lc=~lc;
reg rreq=0,wreq=0,we=0,receiving=0;
wire rack,wack,finish,wfinish,full,empty,init_done;wire [31:0] data;
localparam COLOR=0,WORDS=460800;
wire [11:0] x;wire [10:0] y;wire raster_valid;
integer frames=0,misses=0,pops=0,writes=0,previews=0,checked_words=0;
reg previous_pop=0;
photo_raster_delay #(.DELAY(1)) raster(.clk(pc),.rst(rst || !running),.x(x),.y(y),.valid(raster_valid));
wire de=running && raster_valid && y<720 && x<1280;
wire need=de && (COLOR ? x%4!=3:!x[0]);
wire pop=need && !empty;
wire tq,td,tc;wire [1:0] ts;wire [12:0] ta;wire [15:0] tv;
wire visible;wire [23:0] rgb;
wire tick=running && raster_valid && x==0 && y==720;
photo_thumbnail_overlay #(.Y(528),.DELAY(1)) overlay(.clk(pc),.rst(rst),.frame_tick(tick),.enable(1'b1),.cache_valid(1'b1),.cache_slot(2'd1),.identity({1'b0,3'd1,2'd1}),.de(de),.x(x[11:0]),.y(y[10:0]),.request(tq),.slot(ts),.cancel(tc),.done(td),.data(tv),.address(ta),
 .visible(visible),.rgb_in(24'h112233),.rgb_out(rgb));
frame_store dut(.display_active(1'b1),.thumbnail_request(tq),.thumbnail_cancel(tc),.thumbnail_blank(!running || (raster_valid && y>=720)),.thumbnail_slot(ts),
 .thumbnail_address(ta),.thumbnail_done(td),.thumbnail_data(tv),
 .write_relief(1'b0),.write_award(1'b0),.read_award(1'b0),.light_enable(1'b0),.light_request(1'b0),.light_address(21'd0),
 .water_cfg(77'd0),.fluid_progress(9'd0),.write_fluid(1'b0),.write_slot(2'd1),.read_slot(2'd0),.new_slot(2'd1),
 .slide_active(1'b0),.slide_right(1'b0),.slide_offset(11'd0),.transition_mode(5'd0),
 .mem_clk(mc),.mem_clk_sft(mc),.rst(rst),.write_clk(lc),.write_req(wreq),.write_en(we),.write_data(32'h12345678),
 .write_ack(wack),.write_finish(wfinish),.write_full(full),
 .read_clk(pc),.read_req(rreq),.read_en(pop),.read_ack(rack),.read_finish(finish),.read_empty(empty),.read_data(data),.init_done(init_done));
always @(negedge lc)begin we=receiving && !full && writes<WORDS;if(we)writes=writes+1;end
always @(posedge pc)if(running)begin
 previous_pop<=pop;
 if(previous_pop)begin
  if(data!==(checked_words%WORDS))$fatal(1,"main word corrupted index=%d data=%h",checked_words,data);
  checked_words=checked_words+1;
 end
 if(need)begin if(empty)begin misses=misses+1;$display("underflow x=%d y=%d",x,y);end else pops=pops+1;end

 if(de && x>=1088 && x<1248 && y>=528 && y<618 && visible)begin
  if(rgb!==24'hff0000)$fatal(1,"wrapper preview corruption x=%d y=%d rgb=%h",x,y,rgb);
  previews=previews+1;
 end
 if(raster_valid && x==0 && y==0)frames=frames+1;
end
integer i;
initial begin
 repeat(10)@(negedge mc);rst=0;
 repeat(10)@(negedge mc);

 rreq=1;wreq=1;wait(rack && wack);@(negedge mc);rreq=0;wreq=0;wait(!rack && !wack);
 receiving=1;
`ifdef THUMBNAIL_DYNAMIC
 // Exercise the last rows under live scanout/receive traffic. The separate
 // full-raster blanking bench already checks construction of the entire
 // cache across real blanking windows. Preload three quarters here to
 // keep this real-wrapper/FIFO stress test bounded without shortening any
 // scanline or changing the 75/50/100 MHz clocks or SDRAM timing.
 wait(!empty);wait(dut.thumbnails.row==48 && dut.thumbnails.column==0);
 @(negedge pc);running=1;
 begin:continuous_scan
  for(i=0;i<16;i=i+1)begin
   wait(frames==i+1 && y==720 && x==0);@(negedge pc);
   if(misses || pops!=(i+1)*WORDS || checked_words!=(i+1)*WORDS)
    $fatal(1,"live build scanout frame=%d misses=%d pops=%d checked=%d",i,misses,pops,checked_words);
   if(previews==14400)disable continuous_scan;
   rreq=1;wait(rack);@(negedge mc);rreq=0;wait(!rack);
  end
 end
 running=0;
 if(previews!=14400 || !overlay.ready || dut.ram.preview_reads!=28224)
  $fatal(1,"live preview incomplete pixels=%d reads=%d",previews,dut.ram.preview_reads);
 if(dut.ram.overlapping_preview_reads<1000)$fatal(1,"no background receive overlap");
 $display("PASS live thumbnail tail generation: %0d complete 720p frames, %0d exact main words, 14400 complete preview pixels, zero underflow, %0d preview read commands while background receive active",i+1,checked_words,dut.ram.overlapping_preview_reads);
`else
 wait(overlay.ready);repeat(8)@(negedge pc);running=1;
 wait(frames==1 && y==720 && x==0);@(negedge pc);running=0;
 if(misses!=0 || pops!=WORDS || previews!=14400 || checked_words!=WORDS)$fatal(1,"scanout misses=%d pops=%d preview=%d checked=%d",misses,pops,previews,checked_words);
 if(writes<10000)$fatal(1,"background receive stopped");
 if(dut.ram.preview_reads!=28224)$fatal(1,"unexpected steady preview SDRAM traffic %d",dut.ram.preview_reads);
 $display("PASS concurrent SDRAM COLOR=%0d: %0d exact main words, 14400 preview pixels, zero underflow, no steady preview SDRAM traffic, background words=%0d",COLOR,WORDS,writes);
`endif
 $finish;
end
initial begin #300000000;$fatal(1,"bandwidth timeout");end
endmodule

// APUG read data leads its valid by one clock, as in the calibrated board IP.
module sdram(input Clk,Clk_sft,Rst,input App_wr_en,input [20:0] App_wr_addr,input [3:0] App_wr_dm,
 input [31:0] App_wr_din,input App_rd_en,input [20:0] App_rd_addr,
 output Sdr_init_done,output Sdr_init_ref_vld,Sdr_busy,Sdr_rd_en,output [31:0] Sdr_rd_dout);
integer preview_reads=0,overlapping_preview_reads=0;
reg [11:0] vp=0;reg [31:0] dp[0:10];
integer j,cycles=0;
wire refresh=(cycles%765)>=740 && (cycles%765)<760;
assign Sdr_init_done=!Rst;assign Sdr_init_ref_vld=refresh;assign Sdr_busy=1'b0;
assign Sdr_rd_en=vp[11];assign Sdr_rd_dout=dp[10];
always @(posedge Clk)begin
 cycles<=cycles+1;
 vp<={vp[10:0],App_rd_en};
 dp[0]<=App_rd_addr>=1048576 ? 32'hf800f800:{11'd0,App_rd_addr};
 if(App_rd_en && App_rd_addr>=1048576)preview_reads<=preview_reads+1;
 if(App_rd_en && App_rd_addr>=1048576 && tb_thumbnail_bandwidth.running &&
    tb_thumbnail_bandwidth.receiving && tb_thumbnail_bandwidth.writes<460800)
  overlapping_preview_reads<=overlapping_preview_reads+1;
 for(j=1;j<11;j=j+1)dp[j]<=dp[j-1];
 if(App_wr_en && App_rd_en)$fatal(1,"physical bus read/write collision");
 if(refresh && (App_wr_en || App_rd_en))$fatal(1,"command during refresh");
end
endmodule
