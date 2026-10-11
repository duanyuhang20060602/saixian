`timescale 1ns/1ps
// Full-loop bus/decode throughput test at 50 MHz. Video demand follows the
// production 75 MHz raster (240 words in 320 memory clocks per scene line).
// FIFO contents and video RGB are checked separately by tb_pipeline.
module tb_budget;
reg clk=0;always #10 clk=~clk;
reg rst=1,pause=0;
reg [31:0] package_words[0:472575],ram[0:2097151],expected[0:115199];
string folder,path,expected_path;
integer uploaded=0,cycle=0,i,j,b,commits=0,h=0,v=0,video_words=0;
integer wr_beats=0;reg was_wr=0;reg [20:0] previous_wa;
integer last_presentation=0,mirror_start=0,max_prepare=0,preparation,paused_ticks=0;
reg pause_tested=0;integer pause_left=0;
wire rd,wr,rd_valid;wire [20:0] ra,wa;wire [31:0] wd,rd_data;
wire [3:0] mask;
wire up_pop,cache_ready,vreset,vpush,stream_start,stream_ack,stream_reset,cmd_push,cmd_pop;
wire [31:0] vdata,cmd_data,cmd_head,patch_data;wire [8:0] cmd_count;
reg [8:0] vcount=0;
wire cmd_empty,patch_valid,patch_ready,patch_drained,pub,pub_slot;
reg commit=0,frame=0,active=0,visible=0;
wire [20:0] stream_offset,stream_words,patch_addr;wire [3:0] bus_error,player_error;
wire [31:0] late;wire [5:0] source,descriptor;wire [4:0] player_state;
reg [9:0] pending=0;reg [31:0] response[0:9];
reg refreshing=0,refresh_pending=0;integer refresh_left=0,refresh_clock=0;
wire busy=rd || wr || |pending;
assign rd_valid=pending[9];assign rd_data=response[9];
wire consume=visible && v>=145 && v<625 && h>=440 && h<760 && h[1:0]!=3;
wire inhibit_refresh=refreshing || (refresh_pending && memory_bus.state==0 && !busy);
always @(posedge clk)begin
 if(rst)begin pending<=0;vcount<=0;end
 else begin
  cycle<=cycle+1;
  pending<={pending[8:0],rd};if(rd)response[0]<=ram[ra];
  for(i=1;i<10;i=i+1)response[i]<=response[i-1];
  if(wr)begin
   if(refreshing)$fatal(1,"write during refresh");
   if(visible && wa<230400 && (active ? wa>=115200 : wa<115200))
    $fatal(1,"write to visible frame buffer");
   if(!was_wr)begin if(wa[1:0]!=0)$fatal(1,"SDRAM write start not four-word aligned");wr_beats=1;end
   else begin if(wa!=previous_wa+1)$fatal(1,"SDRAM write jumped inside burst");wr_beats=wr_beats+1;end
   previous_wa<=wa;
   for(b=0;b<4;b=b+1)if(!mask[b])ram[wa][b*8+:8]<=wd[b*8+:8];
  end
  if(was_wr && !wr && wr_beats%4!=0)$fatal(1,"SDRAM write length not multiple of four");
  was_wr<=wr;
  if(rd && refreshing)$fatal(1,"read during refresh");
  if(up_pop)uploaded<=uploaded+1;
  if(vreset)vcount<=0;else vcount<=vcount+vpush-consume;
  if(consume)begin if(vcount==0)$fatal(1,"video demand underflow");video_words=video_words+1;end
  if(vpush && vcount>=511)$fatal(1,"video FIFO overflow");
  if(bus_error || player_error)$fatal(1,"pipeline error bus=%d player=%d",bus_error,player_error);
  refresh_clock<=refresh_clock+1;
  if(refresh_clock==760)begin refresh_pending<=1;refresh_clock<=0;end
  if(refresh_pending && memory_bus.state==0 && !busy)begin
   refreshing<=1;refresh_left<=8;refresh_pending<=0;
  end else if(refreshing)begin
   refresh_left<=refresh_left-1;
   if(refresh_left==1)refreshing<=0;
  end
  if(visible && player_state==7 && player.publish_toggle!=commit && mirror_start!=0)begin
   preparation=cycle-mirror_start;
   if(preparation>max_prepare)max_prepare=preparation;
   mirror_start=0;
  end
  if(commits==4 && !pause_tested && cycle-last_presentation==250000)begin
   pause<=1;pause_left=2500000;pause_tested=1;
  end
  if(pause)begin
   pause_left=pause_left-1;paused_ticks=paused_ticks+1;
   if(commits!=4)$fatal(1,"presentation changed while paused");
   if(pause_left==0)pause<=0;
  end
  if(h==1099)begin h<=0;if(v==749)v<=0;else v<=v+1;end else h<=h+1;
  if(h==0 && v==0)begin
   frame<=~frame;
   if(pub!=commit)begin
    active<=pub_slot;visible<=1;commit<=pub;
    expected_path=$sformatf("%s/frame%0d.hex",folder,commits%27);$readmemh(expected_path,expected);
    for(j=0;j<115200;j=j+1)if(ram[(pub_slot ? 115200 : 0)+j]!==expected[j])
     $fatal(1,"presented buffer mismatch frame=%d word=%d",commits%27,j);
    if(commits>0 && cycle-last_presentation-paused_ticks>2475100)
     $fatal(1,"missed presentation budget: %d ticks",cycle-last_presentation-paused_ticks);
    commits=commits+1;last_presentation=cycle;paused_ticks=0;mirror_start=cycle;
    $display("budget commit=%0d at_ms=%0.3f late=%0d",commits,$realtime/1000000.0,late);$fflush();
    if(commits==28)begin
     if(late!=0 || !pause_tested)$fatal(1,"late presentations or pause test absent");
     $display("PASS budget: all 27 frames and loop-back, original 40 ms scheduling, pause/resume, exact presented buffers, zero video demand underflows, words=%0d, max mirror/prepare=%0d ticks",video_words,max_prepare);
     $finish;
    end
   end
  end
 end
end
delta_memory #(.VERIFY_CACHE(1)) memory_bus(clk,rst,1'b1,inhibit_refresh,busy,rd,ra,rd_valid,rd_data,wr,wa,wd,
 uploaded==472576,21'd472576,uploaded==472576,uploaded==472576 ? 9'd0 : 9'd256,
 package_words[uploaded],up_pop,cache_ready,frame,visible,active,vreset,vpush,vdata,vcount,
 stream_start,stream_offset,stream_words,stream_ack,stream_reset,cmd_push,cmd_data,cmd_count,
 patch_valid,patch_addr,patch_data,patch_ready,bus_error,,package_words[9],,mask,patch_drained);
// Same-clock show-ahead FIFO model; the native FIFO is in tb_pipeline.
reg [31:0] command_ram[0:511];reg [8:0] write_ptr=0,read_ptr=0;
reg [9:0] count=0;
assign cmd_head=command_ram[read_ptr];assign cmd_empty=count==0;assign cmd_count=count[8:0];
always @(posedge clk)begin
 if(rst || stream_reset)begin write_ptr<=0;read_ptr<=0;count<=0;end
 else begin
  count<=count+cmd_push-cmd_pop;
  if(cmd_push)begin if(count==511)$fatal(1,"command FIFO overflow");command_ram[write_ptr]<=cmd_data;write_ptr<=write_ptr+1'b1;end
  if(cmd_pop)begin if(count==0)$fatal(1,"empty command pop");read_ptr<=read_ptr+1'b1;end
 end
end
delta_player #(.VERIFY_STREAM(1),.WAIT_PATCH_DRAIN(1)) player(clk,rst,cache_ready,21'd472576,6'd27,stream_start,stream_offset,stream_words,
 stream_ack,cmd_head,!cmd_empty,cmd_pop,patch_valid,patch_addr,patch_data,patch_ready,pub,pub_slot,commit,pause,
 player_error,late,source,descriptor,player_state,,patch_drained);
initial begin
 if(!$value$plusargs("package=%s",path) || !$value$plusargs("folder=%s",folder))$fatal;
 $readmemh(path,package_words);for(j=0;j<230400;j=j+1)ram[j]=0;
 repeat(5)@(negedge clk);rst=0;
end
initial begin #1800000000;$fatal(1,"budget timeout");end
endmodule
