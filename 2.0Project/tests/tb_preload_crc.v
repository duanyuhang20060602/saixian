`timescale 1ns/1ps
module tb_preload_crc;
localparam BASE=1382400;
reg sdclk=0,mclk=0,vclk=0,rst=1,prepare=0,active=0;
always #10 mclk=~mclk;always #6.667 vclk=~vclk;
reg [10:0] h=0;reg [9:0] v=0;
wire tick=h==0 && v==0;
wire raster_de=h>=260 && h<1540 && v>=25 && v<745;
wire [10:0] rx=h-260;wire [9:0] ry=v-25;
always @(posedge vclk)if(rst)begin h<=0;v<=0;end
else if(h==1649)begin h<=0;v<=v==749 ? 0 : v+1'b1;end else h<=h+1'b1;
wire mode_sd,mode_mem,photo_rst,photo_vrst,mem_rst,photo_pause;
always #5 sdclk=~sdclk;
wire trd,twr,prd,pwr,claim;
wire [20:0] tra,twa,pra,pwa;wire [31:0] twd,pwd;wire [3:0] tdm,pdm;
wire rd=mode_mem ? trd : prd,wr=mode_mem ? twr : pwr;
wire [20:0] ra=mode_mem ? tra : pra,wa=mode_mem ? twa : pwa;
wire [31:0] wd=mode_mem ? twd : pwd;wire [3:0] dm=mode_mem ? tdm : pdm;
wire urst,uwe,ufull,uempty,upop,vreset,vpush,vpop,vempty,visible,underflow;
wire [31:0] udata,uhead,vdata,vhead;wire [8:0] ucount,vcount;
wire [23:0] rgb;wire de,vs,ft,initialized;
wire [2:0] sd_error;wire [3:0] mem_error,player_error;
wire host_reset,host_initialized,sector_req,sector_valid,sector_end;
wire [31:0] sector_addr;wire [7:0] sector_data;
reg [31:0] ram[0:2097151],expected[0:115199];
reg [9:0] pending=0;reg [31:0] response[0:9];
integer i,b,cycle=0,refresh_clock=0,refresh_left=0,wr_beats=0,photo_reads=0,sd_transactions=0,initializations=0;
reg refreshing=0,refresh_pending=0,was_wr=0,host_was_reset=0;
reg [20:0] previous_wa;
wire busy=rd || wr || |pending;
wire inhibit_refresh=refreshing || (refresh_pending && !mode_mem && !claim && !busy);
wire show=active && visible;
saixian_tf_preload dut(
 .prepare(prepare),.active(active),.show(show),.photo_idle(1'b1),.photo_bus_claim(claim),.photo_pause(photo_pause),
 .shared_sd_reset(host_reset),.shared_sd_initialized(host_initialized),.sector_req(sector_req),.sector_addr(sector_addr),
 .sector_data(sector_data),.sector_valid(sector_valid),.sector_end(sector_end),.observed_sector(sector_addr),
 .sd_clk(sdclk),.mem_clk(mclk),.video_clk(vclk),.rst_sd(rst),.rst_mem(rst),.rst_video(rst),
 .mode_sd(mode_sd),.mode_mem(mode_mem),.photo_reset_sd(photo_rst),.photo_reset_video(photo_vrst),.memory_reset(mem_rst),
 .sdr_init(cycle>100),.sdr_refresh(inhibit_refresh),.sdr_busy(busy),
 .rd_valid(pending[9] && mode_mem),.rd_data(response[8]),.app_rd(trd),.rd_addr(tra),.app_wr(twr),.wr_addr(twa),.wr_data(twd),.wr_dm(tdm),
 .upload_reset(urst),.upload_we(uwe),.upload_data(udata),.upload_full(ufull),
 .upload_empty(uempty),.upload_count(ucount),.upload_head(uhead),.upload_pop(upop),
 .video_reset(vreset),.video_push(vpush),.video_data(vdata),.video_head(vhead),.video_count(vcount),.video_empty(vempty),.video_pop(vpop),
 .raster_x(rx),.raster_y(ry),.raster_de(raster_de),.raster_vs(v<5),.raster_frame(tick),
 .rgb(rgb),.de(de),.vs(vs),.frame_tick(ft),.initialized(initialized),.visible(visible),
 .sd_error(sd_error),.memory_error(mem_error),.player_error(player_error),.underflow(underflow));
sd_card_top host(.clk(sdclk),.rst(host_reset),.SD_nCS(),.SD_DCLK(),.SD_MOSI(),.SD_MISO(1'b1),
 .sd_init_done(host_initialized),.init_stage(),.sd_sec_read(sector_req && mode_sd),.sd_sec_read_addr(sector_addr),
 .sd_sec_read_data(sector_data),.sd_sec_read_data_valid(sector_valid),.sd_sec_read_end(sector_end),
 .sd_sec_write(1'b0),.sd_sec_write_addr(32'd0),.sd_sec_write_data(8'd0),.sd_sec_write_data_req(),.sd_sec_write_end());
reg photo_req=0;wire photo_ack,photo_empty;wire [31:0] photo_data;
always @(posedge vclk)begin
 if(rst)photo_req<=0;
 else if(v==5 && h==0 && !show)photo_req<=1;
 else if(photo_ack)photo_req<=0;
end
frame_read_write #(.ENABLE_DELTA(1),.INDEPENDENT_VIDEO(1)) shared(
 .rst(mem_rst),.mem_clk(mclk),.Sdr_init_done(cycle>100),.Sdr_init_ref_vld(inhibit_refresh),.Sdr_busy(busy),
 .background_busy(mode_mem),.photo_bus_claim(claim),
 .App_rd_en(prd),.App_rd_addr(pra),.App_wr_en(pwr),.App_wr_addr(pwa),.App_wr_din(pwd),.App_wr_dm(pdm),
 .Sdr_rd_en(pending[9] && !mode_mem),.Sdr_rd_dout(response[8]),
 .read_clk(vclk),.read_req(photo_req),.read_req_ack(photo_ack),.read_en(raster_de && rx[0] && !show),
 .read_addr_0(21'd0),.read_addr_1(21'd460800),.read_addr_2(21'd921600),.read_addr_3(21'd0),
 .read_addr_index(2'd0),.read_len(21'd460800),.slide_active(1'b0),.slide_old_index(2'd0),.slide_new_index(2'd1),
 .slide_offset(11'd0),.slide_right(1'b0),.transition_mode(3'd0),.buffer0_vga(1'b0),.buffer1_vga(1'b0),
 .read_data(photo_data),.read_fifo_empty(photo_empty),.write_clk(sdclk),.write_req(1'b0),.write_en(1'b0),.write_data(32'd0),.write_fifo_full(ufull),
 .delta_mode(mode_sd),.delta_upload_reset(urst),.delta_upload_we(uwe),.delta_upload_data(udata),
 .delta_upload_pop(upop),.delta_upload_head(uhead),.delta_upload_count(ucount),.delta_upload_empty(uempty));
always @(posedge sdclk)begin
 if(sector_end)sd_transactions<=sd_transactions+1;
 if(host_reset && !host_was_reset)initializations<=initializations+1;
 host_was_reset<=host_reset;
end
always @(posedge mclk)begin
 if(mem_rst)begin pending<=0;cycle<=0;refreshing<=0;refresh_pending<=0;refresh_clock<=0;refresh_left<=0;was_wr<=0;end
 else begin
  cycle<=cycle+1;pending<={pending[8:0],rd};
  if(rd || |pending)begin response[0]<=ram[ra];for(i=1;i<10;i=i+1)response[i]<=response[i-1];end
  if((trd || twr) && (prd || pwr))$fatal(1,"photo/TF bus collision");
  if(rd && !mode_mem)photo_reads<=photo_reads+1;
  if(mode_mem && rd && ra<BASE)$fatal(1,"TF read escaped partition");
  if(wr)begin
   if(refreshing || wa<BASE)$fatal(1,"TF write corrupted retained photo/background");
   if(visible && wa<BASE+230400 && (dut.active_slot ? wa>=BASE+115200 : wa<BASE+115200))$fatal(1,"write to visible TF frame");
   if(!was_wr)begin if(wa[1:0]!=0)$fatal(1,"unaligned write");wr_beats=1;end
   else begin if(wa!=previous_wa+1)$fatal(1,"write jump");wr_beats=wr_beats+1;end
   previous_wa<=wa;
   for(b=0;b<4;b=b+1)if(!dm[b])ram[wa][b*8+:8]<=wd[b*8+:8];
  end
  if(was_wr && !wr && wr_beats%4!=0)$fatal(1,"incomplete masked write");was_wr<=wr;
  if(rd && refreshing)$fatal(1,"read during refresh");
  if(mem_error || player_error || underflow)$fatal(1,"integrated error SD=%d memory=%d player=%d underflow=%d",sd_error,mem_error,player_error,underflow);
  refresh_clock<=refresh_clock+1;
  if(refresh_clock==760)begin refresh_pending<=1;refresh_clock<=0;end
  if(refresh_pending && !mode_mem && !claim && !busy)begin refreshing<=1;refresh_left<=8;refresh_pending<=0;end
  else if(refreshing)begin refresh_left<=refresh_left-1;if(refresh_left==1)refreshing<=0;end
 end
end
string folder,path;integer commits=0,reference=0,j,x,y,pixels=0,saved_sectors,saved_reads;
reg last_commit=0;reg [15:0] pixel;reg [23:0] want;
always @(posedge vclk)begin
 if(!rst && active && visible && raster_de && rx>=400 && rx<880 && ry>=120 && ry<600)begin
  x=rx-400;y=ry-120;pixel=x[0] ? expected[(y*480+x)/2][31:16] : expected[(y*480+x)/2][15:0];
  want={pixel[15:11],pixel[15:13],pixel[10:5],pixel[10:9],pixel[4:0],pixel[4:2]};
  #1;if(rgb!==want)$fatal(1,"RGB mismatch frame=%d x=%d y=%d got=%h want=%h",reference,x,y,rgb,want);
  pixels=pixels+1;
 end
end
always @(negedge vclk)begin
 if(!active)last_commit=0;
 else if(dut.commit!=last_commit)begin
  last_commit=dut.commit;reference=commits%dut.frames_sync;
  path=$sformatf("%s/frame%0d.hex",folder,reference);$readmemh(path,expected);
  for(j=0;j<115200;j=j+1)if(ram[BASE+(dut.active_slot?115200:0)+j]!==expected[j])$fatal(1,"TF frame buffer mismatch");
  commits=commits+1;$display("preload commit=%0d at_ms=%0.3f",commits,$realtime/1000000.0);$fflush();
 end
end
initial begin
 if(!$value$plusargs("folder=%s",folder))$fatal;
 repeat(10)@(negedge mclk);rst=0;wait(host_initialized);
 host.inject=1;prepare=1;
 wait(sd_error!=0);
 if(sd_error!=5 || visible || dut.cache_ready || dut.publish)$fatal(1,"corrupted TF published");
 prepare=0;wait(!mode_sd && !dut.session);
 if(photo_rst || photo_vrst || mem_rst || host_reset)$fatal(1,"CRC cancellation reset photo/card");
 host.inject=0;prepare=1;wait(dut.cache_ready);
 if(sd_error || mem_error || player_error)$fatal(1,"retry failed");
 // Model a previously displayed TF frame and stale commit before card loss.
 // Card replacement must clear this state without waiting a whole raster.
 dut.video_scan.display_valid=1;dut.video_scan.commit_toggle=1;
 force host.sd_init_done=0;
 wait(mem_rst && photo_rst && photo_vrst);wait(!dut.session);
 repeat(5)@(negedge mclk);
 if(dut.cache_ready)$fatal(1,"card replacement retained stale cache");
 if(dut.video_scan.display_valid || dut.video_scan.commit_toggle || dut.video_scan.underrun_latched)
  $fatal(1,"card replacement retained stale video publication");
 release host.sd_init_done;
 wait(host_initialized && !mem_rst && !photo_rst && !photo_vrst);
 wait(dut.cache_ready);
 if(sd_error || mem_error || player_error)$fatal(1,"card reset reload failed");
 $display("PASS preload CRC: actual corrupt payload rejected before publication, KEY2 cancellation retains photos/host, healthy retry, card reset invalidates cache and reloads");$finish;
end
initial begin #500000000;$fatal(1,"preload integration timeout");end
initial begin repeat(50)begin #10000000;$display("preload progress ms=%0.3f prepare=%b active=%b cache=%b player=%0d bus=%0d photo=%0d pixels=%0d",$realtime/1000000.0,prepare,active,dut.cache_ready,dut.player.state,dut.memory_bus.state,photo_reads,pixels);$fflush();end end
endmodule
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
