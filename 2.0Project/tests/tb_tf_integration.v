`timescale 1ns/1ps
// Real loader/player/arbiter/shared FIFOs with SD sector and SDRAM bus models.
// Physical encrypted SDRAM/HDMI PHY is covered by routed build and board test.
module tb_tf_integration;
reg sdclk=0,mclk=0,vclk=0;
reg rst=1,active=0;reg [31:0] ram[0:2097151],expected[0:115199];
// SD has no work after upload; resume its test clock on every exit/reentry.
always #5 if(!dut.loader.ready || !active || rst)sdclk=~sdclk;
always #10 mclk=~mclk;always #6.667 vclk=~vclk;
wire mode_sd,mode_mem,photo_rst,photo_video_rst,mem_rst;
wire rd,wr;wire [20:0] ra,wa;wire [31:0] wd;wire [3:0] dm;
wire urst,uwe,ufull,uempty,upop,vreset,vpush,vpop,vempty;
wire [31:0] udata,uhead,vdata,vhead;wire [8:0] ucount,vcount;
wire [23:0] rgb;wire de,vs,ft,initialized,visible,underflow;
wire [2:0] sd_error;wire [3:0] mem_error,player_error;
always @(negedge vclk)
 if(active && !rst && !dut.delta_rst_video && !visible && rgb!==24'd0)
  $fatal(1,"TF loading displayed a spinner instead of black");
wire host_reset,host_initialized,sector_req,sector_valid,sector_end;
wire [31:0] sector_addr;wire [7:0] sector_data;
reg [9:0] pending=0;reg [31:0] response[0:9];
integer i,b,cycle=0,refresh_clock=0,refresh_left=0,wr_beats=0;
reg refreshing=0,refresh_pending=0,was_wr=0;reg [20:0] previous_wa;
wire busy=rd || wr || |pending;
wire inhibit_refresh=refreshing || (refresh_pending && dut.memory_bus.state==0 && !busy);
saixian_tf_animation #(.EXTERNAL_SD_HOST(1)) dut(
 .shared_sd_reset(host_reset),.shared_sd_initialized(host_initialized),.sector_req(sector_req),.sector_addr(sector_addr),
 .sector_data(sector_data),.sector_valid(sector_valid && mode_sd),.sector_end(sector_end && mode_sd),
 .sd_clk(sdclk),.mem_clk(mclk),.video_clk(vclk),.rst_sd(rst),.rst_mem(rst),.rst_video(rst),.active(active),
 .mode_sd(mode_sd),.mode_mem(mode_mem),.photo_reset_sd(photo_rst),.photo_reset_video(photo_video_rst),.memory_reset(mem_rst),
 .sd_cs(),.sd_sck(),.sd_mosi(),.sd_miso(1'b1),.sdr_init(cycle>100),.sdr_refresh(inhibit_refresh),.sdr_busy(busy),
 .rd_valid(pending[9]),.rd_data(response[8]),.app_rd(rd),.rd_addr(ra),.app_wr(wr),.wr_addr(wa),.wr_data(wd),.wr_dm(dm),
 .upload_reset(urst),.upload_we(uwe),.upload_data(udata),.upload_full(ufull),
 .upload_empty(uempty),.upload_count(ucount),.upload_head(uhead),.upload_pop(upop),
 .video_reset(vreset),.video_push(vpush),.video_data(vdata),.video_count(vcount),
 .video_head(vhead),.video_empty(vempty),.video_pop(vpop),.rgb(rgb),.de(de),.vs(vs),.frame_tick(ft),
 .initialized(initialized),.visible(visible),.sd_error(sd_error),.memory_error(mem_error),.player_error(player_error),.underflow(underflow));
sd_card_top host(.clk(sdclk),.rst(host_reset),.SD_nCS(),.SD_DCLK(),.SD_MOSI(),.SD_MISO(1'b1),
 .sd_init_done(host_initialized),.init_stage(),.sd_sec_read(sector_req && mode_sd),.sd_sec_read_addr(sector_addr),
 .sd_sec_read_data(sector_data),.sd_sec_read_data_valid(sector_valid),.sd_sec_read_end(sector_end),
 .sd_sec_write(1'b0),.sd_sec_write_addr(32'd0),.sd_sec_write_data(8'd0),.sd_sec_write_data_req(),.sd_sec_write_end());
// Do not spend 50 million cycles testing the separately proven first-frame hold.
defparam dut.player.INITIAL_HOLD_TICKS=0;
frame_read_write #(.ENABLE_DELTA(1)) shared(
 .rst(mem_rst),.mem_clk(mclk),.Sdr_init_done(1'b0),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),
 .Sdr_rd_en(1'b0),.Sdr_rd_dout(32'd0),.read_clk(vclk),.read_req(1'b0),.read_en(1'b0),
 .read_fifo_empty(vempty),.write_clk(sdclk),.write_req(1'b0),.write_en(1'b0),.write_data(32'd0),.write_fifo_full(ufull),
 .delta_mode(mode_mem),.delta_upload_reset(urst),.delta_upload_we(uwe),.delta_upload_data(udata),
 .delta_upload_pop(upop),.delta_upload_head(uhead),.delta_upload_count(ucount),.delta_upload_empty(uempty),
 .delta_video_reset(vreset),.delta_video_push(vpush),.delta_video_data(vdata),
 .delta_video_pop(vpop),.delta_video_head(vhead),.delta_video_count(vcount));
always @(posedge mclk)begin
 if(mem_rst)begin
  pending<=0;cycle<=0;refreshing<=0;refresh_pending<=0;refresh_clock<=0;refresh_left<=0;was_wr<=0;
 end else begin
  cycle<=cycle+1;pending<={pending[8:0],rd};
  if(rd || |pending)begin response[0]<=ram[ra];for(i=1;i<10;i=i+1)response[i]<=response[i-1];end
  if(wr)begin
   if(refreshing)$fatal(1,"write during refresh");
   if(visible && wa<230400 && (dut.active_slot ? wa>=115200 : wa<115200))$fatal(1,"write to visible frame");
   if(!was_wr)begin if(wa[1:0]!=0)$fatal(1,"unaligned write");wr_beats=1;end
   else begin if(wa!=previous_wa+1)$fatal(1,"write address jump");wr_beats=wr_beats+1;end
   previous_wa<=wa;
   for(b=0;b<4;b=b+1)if(!dm[b])ram[wa][b*8+:8]<=wd[b*8+:8];
  end
  if(was_wr && !wr && wr_beats%4!=0)$fatal(1,"incomplete four-word write");
  was_wr<=wr;
  if(rd && refreshing)$fatal(1,"read during refresh");
  if(mem_error || player_error || underflow)$fatal(1,"integrated error SD=%d memory=%d player=%d underflow=%d",sd_error,mem_error,player_error,underflow);
  refresh_clock<=refresh_clock+1;
  if(refresh_clock==760)begin refresh_pending<=1;refresh_clock<=0;end
  if(refresh_pending && dut.memory_bus.state==0 && !busy)begin refreshing<=1;refresh_left<=8;refresh_pending<=0;end
  else if(refreshing)begin refresh_left<=refresh_left-1;if(refresh_left==1)refreshing<=0;end
 end
end
string folder,expected_path;integer commits=0,reference=0,j,x,y,pixels=0,max_commits=28;
reg last_commit=0;reg [15:0] pixel;reg [23:0] want;
always @(posedge vclk)begin
 if(!rst && active && visible && dut.video_scan.h>=660 && dut.video_scan.h<1140 &&
    dut.video_scan.v>=145 && dut.video_scan.v<625)begin
  x=dut.video_scan.h-660;y=dut.video_scan.v-145;
  pixel=x[0] ? expected[(y*480+x)/2][31:16] : expected[(y*480+x)/2][15:0];
  want={pixel[15:11],pixel[15:13],pixel[10:5],pixel[10:9],pixel[4:0],pixel[4:2]};
  #1;if(rgb!==want)$fatal(1,"RGB mismatch frame=%d x=%d y=%d got=%h want=%h",reference,x,y,rgb,want);
  pixels=pixels+1;
 end else if(!rst && active && visible)begin #1;if(rgb!==0)$fatal(1,"black border mismatch");end
end
always @(negedge vclk)begin
 if(!active)last_commit=0;
 else if(dut.commit!=last_commit)begin
  last_commit=dut.commit;reference=commits%dut.frames_sync;
  expected_path=$sformatf("%s/frame%0d.hex",folder,reference);$readmemh(expected_path,expected);
  for(j=0;j<115200;j=j+1)if(ram[(dut.active_slot?115200:0)+j]!==expected[j])
   $fatal(1,"frame buffer mismatch frame=%d word=%d",reference,j);
  commits=commits+1;
  $display("commit=%0d source=%0d at_ms=%0.3f",commits,reference,$realtime/1000000.0);$fflush();
 end
end
initial begin
 if(!$value$plusargs("folder=%s",folder))$fatal;
 if($value$plusargs("commits=%d",max_commits))begin end
 for(j=0;j<230400;j=j+1)ram[j]=32'hdeadbeef;
 repeat(10)@(negedge mclk);rst=0;repeat(25)@(negedge vclk);
 if(mode_sd || mode_mem || visible)$fatal(1,"TF started before KEY2");
 active=1;
 // Abort while scanning/uploading, then verify a completely fresh entry.
 wait(dut.loader.loading && dut.loader.bytes_loaded>1024);
 @(negedge vclk);active=0;
 wait(!mode_sd && !mode_mem && !photo_rst && !mem_rst);
 repeat(30)@(negedge mclk);
 if(visible || rd || wr)$fatal(1,"TF continued after exit");
 @(negedge vclk);active=1;
 wait(commits==max_commits);
 @(negedge vclk);active=0;
 wait(!mode_sd && !mode_mem && !photo_rst && !mem_rst);
 repeat(30)@(negedge mclk);
 if(visible || dut.cache_ready || rd || wr)$fatal(1,"stale cache after exit");
 $display("PASS integrated TF path: loader/shared host/FIFOs, %0d presentations, exact RGB565 pixels=%0d, refresh/masked writes, abort/reentry/exit, zero errors",commits,pixels);$fflush();
 // Corrupt one payload byte on the next entry: never publish a partial frame.
 host.inject=1;commits=0;
 @(negedge vclk);active=1;wait(sd_error!=0);
 if(sd_error!=5 || visible || commits!=0)$fatal(1,"CRC corruption published a frame");
 @(negedge vclk);active=0;wait(!mode_sd && !mode_mem && !photo_rst && !mem_rst);
 $display("PASS integrated CRC corruption: SD error 5 blocks publication; exit recovers ownership");$finish;
end
initial begin #2500000000;$fatal(1,"TF integration timeout");end
initial begin
 repeat(250)begin
  #10000000;
  $display("progress ms=%0.3f active=%b loader=%0d bytes=%0d cache=%b bus=%0d player=%0d commits=%0d",
   $realtime/1000000.0,active,dut.loader.state,dut.loader.bytes_loaded,dut.cache_ready,dut.memory_bus.state,dut.player.state,commits);
  $fflush();
 end
end
endmodule

// SPI/physical SD is not emulated. This supplies sector bytes to the real loader.
module sd_card_top #(parameter SPI_LOW_SPEED_DIV=248,SPI_HIGH_SPEED_DIV=2)(
 input clk,rst,output SD_nCS,SD_DCLK,SD_MOSI,input SD_MISO,
 output reg sd_init_done,output [2:0] init_stage,input sd_sec_read,input [31:0] sd_sec_read_addr,
 output reg [7:0] sd_sec_read_data,output reg sd_sec_read_data_valid,sd_sec_read_end,
 input sd_sec_write,input [31:0] sd_sec_write_addr,input [7:0] sd_sec_write_data,
 output sd_sec_write_data_req,sd_sec_write_end);
reg [31:0] words[0:472575];string package_path;
reg [1:0] state=0;reg [31:0] address=0;integer index=0,wait_count=0,byte_address,package_word_count=472576;
reg phase=0,inject=0;reg [7:0] value;
assign SD_nCS=rst || state!=1;assign SD_DCLK=clk;assign SD_MOSI=1;
assign init_stage=sd_init_done?7:0;assign sd_sec_write_data_req=0;assign sd_sec_write_end=0;
initial begin
 if(!$value$plusargs("package=%s",package_path))$fatal;
 if($value$plusargs("package_words=%d",package_word_count))begin end
 $readmemh(package_path,words,0,package_word_count-1);
end
always @(posedge clk)begin
 if(rst)begin state<=0;index<=0;wait_count<=0;phase<=0;sd_init_done<=0;sd_sec_read_data_valid<=0;sd_sec_read_end<=0;sd_sec_read_data<=0;end
 else begin
  sd_sec_read_data_valid<=0;sd_sec_read_end<=0;
  if(wait_count<16)wait_count<=wait_count+1;else sd_init_done<=1;
  case(state)
   0:if(sd_sec_read && sd_init_done)begin state<=1;address<=sd_sec_read_addr;index<=0;phase<=0;end
   1:begin
    phase<=!phase;
    if(phase)begin
     byte_address=(address-3)*512+index;
     value=address>=3 && byte_address<package_word_count*4 ? words[byte_address/4][(byte_address%4)*8+:8] : 8'd0;
     if(inject && byte_address==612)value=value^8'd1;
     sd_sec_read_data<=value;sd_sec_read_data_valid<=1;index<=index+1;
     if(index==511)state<=2;
    end
   end
   2:begin sd_sec_read_end<=1;state<=3;end
   3:if(!sd_sec_read)state<=0;
  endcase
 end
end
endmodule
