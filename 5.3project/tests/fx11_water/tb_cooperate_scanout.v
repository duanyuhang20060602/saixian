`timescale 1ns/1ps
module tb #(parameter TEST_MODE=6);
reg mem=0,pixel=0;always #10 mem=~mem;always #6.6665 pixel=~pixel;
reg rst=1;wire req;wire ack,done,re,we,busy,clear;wire[20:0] addr;wire[31:0] data,timeouts;
integer xc=0,yc=720,ack0=0,ack1=0,memcycle=0,hold=0,write_total=0,read_total=0,underflows=0;
integer frame_pixels=0,frame_words=0,requests=0,max_used=0;
wire[9:0] used;
sdram_contract contract(mem,rst,re,addr);
wire fifo_empty,pop,display_de,display_vs,display_hs,display_fault;wire[31:0] fifo_dout;wire[23:0] rgb;
wire raw_de=yc<720&&xc<1280&&!rst;
wire raw_vs=yc>=725&&yc<730;
reg[31:0] checksum=32'h811c9dc5;
reg[31:0] expected_checksum[0:4];
rfifo_32_32_512 #(.ADDR_WIDTH_W(10),.ADDR_WIDTH_R(10),.AL_FULL_NUM(1021)) fifo(
 .rst(rst||clear),.clkw(mem),.clkr(pixel),.we(we),.di(data),.re(pop),.dout(fifo_dout),.empty_flag(fifo_empty),.wrusedw(used));
reg[1:0] display_delay=0;
always @(posedge pixel)display_delay<={display_delay[0],raw_de};
assign display_de=display_delay[1];
frame_pixels display_pipe(.clk(pixel),.rst(rst),.de(raw_de),.high_color(1'b0),
 .x(xc[11:0]),.y(yc[10:0]),.image_valid(1'b1),.read_ack(ack),.empty(fifo_empty),.data(fifo_dout),
 .read_req(req),.read_en(pop),.rgb(rgb),.underflow(display_fault),.armed(),.output_started());
wire writer_busy,writer_enable,writer_ack,writer_done,urgent;
wire[20:0] writer_address;reg writer_request=1;integer writer_commands=0,active_writer_commands=0;
frame_fifo_write #(.WRITE_V_FLIP(0),.FRAME_WIDTH(640),.FRAME_HEIGHT(720)) background_writer(
 .high_color(1'b0),.read_urgent(urgent),.rst(rst),.mem_clk(mem),.Sdr_init_done(1'b1),
 .Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),.App_rd_busy(busy),.O_wr_busy(writer_busy),
 .App_wr_en(writer_enable),.App_wr_addr(writer_address),.write_req(writer_request),
 .write_req_ack(writer_ack),.write_finish(writer_done),.write_addr_0(21'd0),
 .write_addr_1(21'd691200),.write_addr_2(21'd1382400),.write_addr_3(21'd0),
 .write_addr_index(2'd2),.write_len(21'd691200),.write_vga(1'b0),.fifo_aclr(),.rdusedw(9'd255));
always @(posedge mem)begin
 if(writer_ack)writer_request<=0;
 if(writer_enable)begin
  writer_commands=writer_commands+1;
  if(yc<720)active_writer_commands=active_writer_commands+1;
  if(re)$fatal(1,"simultaneous read and background write commands");
 end
end
reg sdr_v=0;reg[31:0] sdr_data=0;
integer tail=0,head=0;reg[20:0] mq[0:1048575];integer stamp[0:1048575];
water_reader d(.rst(rst),.mem_clk(mem),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),
 .Sdr_rd_en(sdr_v),.Sdr_rd_dout(sdr_data),.App_wr_busy(writer_busy),.O_rd_busy(busy),.App_rd_en(re),.App_rd_addr(addr),
 .read_req(req),.read_req_ack(ack),.read_finish(done),.read_addr_0(21'd0),.read_addr_1(21'd691200),.read_addr_2(21'd0),.read_addr_3(21'd1382400),
 .read_addr_index(2'd0),.slide_old_index(2'd0),.slide_new_index(2'd1),.read_len(21'd460800),.slide_active(TEST_MODE==6||TEST_MODE==5||TEST_MODE==9),.slide_right(1'b0),.transition_mode(TEST_MODE[3:0]),.slide_offset(11'd0),
 .force_effect_plane(1'b0),.water_cfg((TEST_MODE==6||TEST_MODE==5||TEST_MODE==9) ? {68'd0,9'd128}:TEST_MODE==7 ? 77'd0:{2'b11,11'd998,11'd346,10'd454,10'd432,12'd600,12'd400,9'd0}),
 .fifo_aclr(clear),.wrusedw({1'b0,used}),.fifo_we(we),.fifo_data(data),.read_timeouts(timeouts),.read_urgent(urgent));
always @(posedge mem)begin
 memcycle=memcycle+1;sdr_v<=0;
 if(hold>0)hold=hold-1;else if(!busy&&memcycle%5000<15)hold=256;
 if(re)begin mq[tail]=addr;stamp[tail]=memcycle;tail=tail+1;requests=requests+1;end
 // Ordered memory response, initial latency plus periodic refresh service.
 if(head<tail&&memcycle-stamp[head]>=14&&memcycle%768>=6)begin
  sdr_v<=1;sdr_data<={mq[head][15:0],mq[head][15:0]^16'hffff};head=head+1;
 end
 if(clear)write_total=0;
 else if(we)begin
  if(write_total-read_total>=1024)$fatal(1,"overflow");
  write_total=write_total+1;
  if(write_total-read_total>max_used)max_used=write_total-read_total;
 end
end
always @(posedge pixel)begin
 if(rst)begin xc=0;yc=720;read_total=0;end
 else begin
  ack0<=ack;ack1<=ack0;
  if(clear)read_total=0;
  else if(pop)begin
   if(read_total==write_total)begin underflows=underflows+1;$fatal(1,"underflow at %0d,%0d produced%0d",xc,yc,write_total);end
   read_total=read_total+1;frame_words=frame_words+1;
  end
  if(xc==1649)begin xc=0;yc=yc==749 ? 0:yc+1;end else xc=xc+1;
  if(yc==720&&frame_words>0)begin
   if(frame_words!=460800||frame_pixels!=921600||underflows!=0||timeouts!=0||display_fault)$fatal(1,"frame size/timeout fault words%0d pixels%0d underflow%b",frame_words,frame_pixels,display_fault);
   if(checksum!==expected_checksum[TEST_MODE==6 ? 0:TEST_MODE==0 ? 1:TEST_MODE==7 ? 2:TEST_MODE==5 ? 3:4])$fatal(1,"full-frame RGB mismatch mode%0d checksum%h expected%h",TEST_MODE,checksum,expected_checksum[TEST_MODE==6 ? 0:TEST_MODE==0 ? 1:TEST_MODE==7 ? 2:TEST_MODE==5 ? 3:4]);
   if(active_writer_commands<512)$fatal(1,"background writer starved during visible frame: %0d words",active_writer_commands);
   $display("PASS background writer made %0d accepted write commands, %0d during visible scanout",writer_commands,active_writer_commands);
   $display("PASS full 720p60 frame mode%0d: 921600 exact RGB pixels checksum%h, 50MHz SDRAM model, %0d requests, actual async FIFO peak %0d/1024",TEST_MODE,checksum,requests,max_used);$finish;
  end
 end
end
always @(posedge pixel)begin #1;
 if(display_de)begin checksum=(checksum^{8'd0,rgb})*32'h01000193;frame_pixels=frame_pixels+1;end
end
initial begin $readmemh("frame_checksums.hex",expected_checksum);#200;rst=0;end
initial begin #25000000;$fatal(1,"bandwidth timeout");end
always @(posedge mem)if(!rst)begin
 if(d.mapped_valid && d.old_ra>=5120)$fatal(1,"effect cache read outside compact window");
 if(d.fetch_valid && d.fetch_kind==0 && d.fetch_cache_address>=5120)$fatal(1,"effect cache write outside compact window");
end
endmodule
