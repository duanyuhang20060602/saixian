`timescale 1ns/1ps
// Uses the production player, bus arbiter, video raster and vendor FIFOs.
// Ten-cycle SDRAM model; checks APUG011 four-word writes and byte masks.
// real board validation of that controller and HDMI PHY is still required.
module tb_pipeline;
reg clk=0,vclk=0;always #10 clk=~clk;always #6.666667 vclk=~vclk;
reg rst=1,pause=0;
reg [31:0] package_words[0:363391],ram[0:2097151],expected[0:460799];
string folder,path,expected_path;
integer uploaded=0,cycle=0,i,b,commits=0,pixels=0,presentation_cycle,last_presentation=0,max_commits=999;
integer wr_beats=0;reg was_wr=0;reg [20:0] previous_wa;
integer mirror_start=0,max_prepare=0,preparation;
wire rd,wr,rd_valid;wire [20:0] ra,wa;wire [31:0] wd,rd_data;
wire [3:0] mask;
wire up_pop,cache_ready,vreset,vpush,stream_start,stream_ack,stream_reset,cmd_push,cmd_pop;
wire [31:0] vdata,vhead,cmd_data,cmd_head,patch_data;wire [8:0] vcount,cmd_count;
wire vempty,vfull,cmd_empty,patch_valid,patch_ready,patch_drained,pub,pub_slot,commit,frame,active,visible,underflow;
wire [20:0] stream_offset,stream_words,patch_addr;wire [3:0] bus_error,player_error;
wire [31:0] late;wire [5:0] source,descriptor;wire [4:0] player_state;
wire pop;wire [23:0] rgb;wire de,vs;
reg [2:0] fs=0,cs=0;reg am=0,as=0,dm=0,ds=0;
reg [9:0] pending=0;reg [31:0] response[0:9];
reg refreshing=0,refresh_pending=0;integer refresh_left=0,refresh_clock=0;
wire busy=rd || wr || |pending;
assign rd_valid=pending[9];assign rd_data=response[9];
always @(posedge clk)begin
 if(rst)begin pending<=0;fs<=0;cs<=0;am<=0;as<=0;dm<=0;ds<=0;end
 else begin
  cycle<=cycle+1;fs<={fs[1:0],frame};cs<={cs[1:0],commit};
  am<=active;as<=am;dm<=visible;ds<=dm;
  pending<={pending[8:0],rd};response[0]<=ram[ra];
  for(i=1;i<10;i=i+1)response[i]<=response[i-1];
  if(wr)begin
   if(refreshing)$fatal(1,"write during refresh");
   if(visible && wa<921600 && (active ? wa>=460800 : wa<460800))
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
  if(vpush && vfull)$fatal(1,"video FIFO overflow");
  if(bus_error || player_error || underflow)$fatal(1,"pipeline error bus=%d player=%d underflow=%d",bus_error,player_error,underflow);
  refresh_clock<=refresh_clock+1;
  if(refresh_clock==760)begin refresh_pending<=1;refresh_clock<=0;end
  if(refresh_pending && memory_bus.state==0 && !busy)begin
   refreshing<=1;refresh_left<=8;refresh_pending<=0;
  end else if(refreshing)begin
   refresh_left<=refresh_left-1;
   if(refresh_left==1)refreshing<=0;
  end
  if(visible && player_state==7 && player.publish_toggle!=cs[2] && mirror_start!=0)begin
   preparation=cycle-mirror_start;
   if(preparation>max_prepare)max_prepare=preparation;
   mirror_start=0;
  end
 end
end
// Prevent launching a transaction on the same cycle refresh starts.
wire inhibit_refresh=refreshing || (refresh_pending && memory_bus.state==0 && !busy);
delta_memory #(.VERIFY_CACHE(1),.FRAME_WORDS(460800)) memory_bus(clk,rst,1'b1,inhibit_refresh,busy,rd,ra,rd_valid,rd_data,wr,wa,wd,
 uploaded==363392,21'd363392,uploaded==363392,uploaded==363392 ? 9'd0 : 9'd256,
 package_words[uploaded],up_pop,cache_ready,fs[2],ds,as,vreset,vpush,vdata,vcount,
 stream_start,stream_offset,stream_words,stream_ack,stream_reset,cmd_push,cmd_data,cmd_count,
 patch_valid,patch_addr,patch_data,patch_ready,bus_error,,32'hC165A3F0,,mask,patch_drained);
wfifo_32_32_512 command_fifo(.rst(rst|stream_reset),.clkw(clk),.clkr(clk),.we(cmd_push),.di(cmd_data),
 .re(cmd_pop),.dout(cmd_head),.full_flag(),.empty_flag(cmd_empty),.rdusedw(cmd_count),.wrusedw(),.valid(),.afull(),.aempty());
rfifo_32_32_512 #(.SHOW_AHEAD_EN(1'b1)) video_fifo(.rst(rst|vreset),.clkw(clk),.clkr(vclk),
 .we(vpush),.di(vdata),.re(pop),.dout(vhead),.full_flag(vfull),.empty_flag(vempty),
 .wrusedw(vcount),.rdusedw(),.valid(),.afull(),.aempty());
delta_player #(.FRAME_WORDS(460800),.VERIFY_STREAM(1),.WAIT_PATCH_DRAIN(1)) player(clk,rst,cache_ready,21'd363392,6'd1,stream_start,stream_offset,stream_words,
 stream_ack,cmd_head,!cmd_empty,cmd_pop,patch_valid,patch_addr,patch_data,patch_ready,pub,pub_slot,cs[2],pause,
 player_error,late,source,descriptor,player_state,,patch_drained);
delta_video #(.SCENE_WIDTH(1280),.SCENE_HEIGHT(720)) video(vclk,rst,pub,pub_slot,vhead,vempty,pop,rgb,de,vs,commit,frame,active,visible,underflow,1'b0);
reg last_commit=0;integer reference=0,j,x,y,old_h,old_v;reg [15:0] pixel;reg [23:0] want;
always @(posedge vclk)begin
 old_h=video.h;old_v=video.v;
 if(!rst && visible && old_h>=260 && old_h<1540 && old_v>=25 && old_v<745)begin
  x=old_h-260;y=old_v-25;
  pixel=x[0] ? expected[(y*1280+x)/2][31:16] : expected[(y*1280+x)/2][15:0];
  want={pixel[15:11],pixel[15:13],pixel[10:5],pixel[10:9],pixel[4:0],pixel[4:2]};
  #1;if(rgb!==want)$fatal(1,"RGB mismatch native frame=%d x=%d y=%d got=%h want=%h",reference,x,y,rgb,want);
  pixels=pixels+1;
  if(pixels==2764800)begin
   if(late!=0)$fatal(1,"preparation late");
   $display("PASS pipeline: three complete 1280x720 presentations, 2764800 exact pixels, native FIFOs, full cache CRC and strict masked four-word writes; zero underflows");$finish;
  end
 end else if(!rst)begin #1;if(rgb!==0)$fatal(1,"black border mismatch");end
end
always @(negedge vclk)if(!rst && commit!=last_commit)begin
 last_commit=commit;reference=0;
 expected_path=$sformatf("%s/frame%0d.hex",folder,reference);$readmemh(expected_path,expected);
 for(j=0;j<460800;j=j+1)if(ram[(active ? 460800 : 0)+j]!==expected[j])
  $fatal(1,"presented buffer mismatch frame=%d word=%d",reference,j);
 commits=commits+1;presentation_cycle=cycle;
 // The 1 ps simulator rounds each half-period to 6.667 ns, about 50 ppm.
 if(commits>1 && presentation_cycle-last_presentation>301000000)
  $fatal(1,"frame interval exceeds 3 display refreshes: %d",presentation_cycle-last_presentation);
 last_presentation=presentation_cycle;mirror_start=cycle;
 $display("commit=%0d original_frame=%0d at_ms=%0.3f late=%0d",commits,reference,$realtime/1000000.0,late);
 $fflush();
 if(commits==max_commits)begin
  if(late!=0)$fatal(1,"animation preparation missed deadlines %d times",late);
  $display("PASS pipeline: %0d original presentations with native FIFOs and video raster, exact RGB565 scene and black borders, pixels=%0d, zero underruns, max mirror/prepare<=%0d ticks; encrypted SDRAM model not included",commits,pixels,max_prepare);
  $finish;
 end
end
initial begin
 if(!$value$plusargs("package=%s",path) || !$value$plusargs("folder=%s",folder))$fatal;
 if($value$plusargs("commits=%d",max_commits))begin end
 $readmemh(path,package_words);for(j=0;j<921600;j=j+1)ram[j]=0;
 repeat(5)@(negedge clk);rst=0;
end
initial begin #1800000000;$fatal(1,"pipeline timeout");end
endmodule
