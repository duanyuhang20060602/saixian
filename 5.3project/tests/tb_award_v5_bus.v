`timescale 1ns/1ps
// Production framebuffer FSM/FIFOs plus sparse light reads at 75/50 MHz.
module tb #(parameter TEST_FRAMES=5,IMAGE_ROWS=64);
reg mc=0,vc=0,rst=1;always #10 mc=~mc;always #6.666667 vc=~vc;
reg [31:0] sparse[0:230399],raw[0:326399];reg [7:0] golden[0:3686399];integer expected_frame=0,golden_frame,f;
reg [11:0] pipeline=0;reg [31:0] response[0:11];
reg [3:0] launch=0;reg [20:0] launch_address;
integer x=0,y=IMAGE_ROWS,frames=0,word_number=0,checks=0,underflows=0,max_latency=0,request_cycle=0,line_jobs=0;
integer cycle=0,i,refreshes=0;reg refresh=0,pending_refresh=0;reg [4:0] refresh_left=0;
wire light_req,light_ack,light_valid,claim,light_rd,frame_rd,wr,frame_busy;
wire [20:0] light_address,light_ra,frame_ra,wa;
wire [31:0] light_data,pixel_data,wd;wire [3:0] dm,error;
wire rd=claim ? light_rd:frame_rd;wire [20:0] ra=claim ? light_ra:frame_ra;
wire response_valid=pipeline[11];wire [31:0] response_data=response[11];
wire busy=|pipeline || launch!=0;
wire refresh_gate=refresh || (pending_refresh && !busy && !claim && !frame_busy);
always @(posedge mc)begin
 cycle<=cycle+1;
 if(rst)begin pipeline<=0;launch<=0;refresh<=0;pending_refresh<=0;end
 else begin
  pipeline<={pipeline[10:0],rd};
 if(rd)begin
  if(refresh || wr)$fatal(1,"native command overlap");
  response[0]<=ra<460800 ? ra:sparse[ra-460800];
 end
  for(i=1;i<12;i=i+1)response[i]<=response[i-1];
  if(cycle%389==0)pending_refresh<=1;
  if(pending_refresh && !busy && !claim && !frame_busy)begin refresh<=1;refresh_left<=8;pending_refresh<=0;refreshes<=refreshes+1;end
  else if(refresh)begin if(refresh_left==0)refresh<=0;else refresh_left<=refresh_left-1'b1;end
  if(error)$fatal(1,"light error=%0d video_error=%b at raster %0d/%0d",error,dut.video_error,x,y);
  if(claim && (frame_rd || wr))$fatal(1,"framebuffer uses reserved light turn");
 end
end
photo_award_memory bus(.clk(mc),.rst(rst),.enable(1'b1),.init_done(1'b1),.refresh(refresh_gate),.busy(busy),.frame_busy(frame_busy),
 .request(light_req),.address(light_address),.acknowledge(light_ack),.data(light_data),.valid(light_valid),
 .claim(claim),.read_command(light_rd),.read_address(light_ra),.response_valid(response_valid),.response(response_data));

reg running=0,read_req=0,pause=0,write_req=0,write_en=0;wire write_ack,write_full;integer background_words=0;
// Offer 10 Mword/s on the 50 MHz memory-side producer: above the optimized
// 25 MHz link's 8.33 Mword/s ceiling. Honor full to verify real backpressure.
always @(negedge mc)begin write_en=running && !write_full && cycle%5==0; if(write_en)background_words=background_words+1;end
wire de=running && x<1280 && y<IMAGE_ROWS;
wire vs=running && x==0 && y==IMAGE_ROWS;
wire ack,empty,finish;wire pop=de && !x[0] && !empty;
reg pop_previous=0;
always @(posedge vc)begin
 pop_previous<=pop;
 if(pop_previous)begin
  if(pixel_data!==word_number)$fatal(1,"display word mismatch %0d != %h",word_number,pixel_data);
  word_number=word_number+1;
 end
 if(de && !x[0] && empty)underflows=underflows+1;
 if(!rst && dut.request_pending && request_cycle==0)request_cycle=cycle;
 if(!rst && !dut.request_pending && request_cycle!=0)begin
  if(cycle-request_cycle>max_latency)max_latency=cycle-request_cycle;
  request_cycle=0;line_jobs=line_jobs+1;
 end
end
always @(negedge vc)if(running)begin
 if(x==1649)begin x=0;if(y==IMAGE_ROWS+29)begin y=0;frames=frames+1;end else y=y+1;end else x=x+1;
end
frame_read_write rw(.external_request(light_req),.external_busy(claim),.access_busy(frame_busy),
 .fluid_progress(9'd0),.water_cfg(77'd0),.rst(rst),.mem_clk(mc),
 .Sdr_init_done(1'b1),.Sdr_init_ref_vld(refresh_gate),.Sdr_busy(busy),.App_rd_en(frame_rd),.App_rd_addr(frame_ra),
 .Sdr_rd_en(response_valid && !claim),.Sdr_rd_dout(response_data),.read_clk(vc),.read_req(read_req),.read_req_ack(ack),.read_finish(finish),
 .read_addr_0(21'd0),.read_addr_1(21'd691200),.read_addr_2(21'd1382400),.read_addr_3(21'd0),.read_addr_index(2'd0),.read_len(IMAGE_ROWS*640),
 .read_en(pop),.read_data(pixel_data),.read_fifo_empty(empty),.slide_active(1'b0),.slide_old_index(2'd0),.slide_new_index(2'd1),
 .slide_offset(11'd0),.slide_right(1'b0),.transition_mode(5'd0),.buffer0_vga(1'b0),.buffer1_vga(1'b0),
 .App_wr_en(wr),.App_wr_addr(wa),.App_wr_din(wd),.App_wr_dm(dm),.write_clk(mc),.write_req(write_req),.write_req_ack(write_ack),.write_fifo_full(write_full),.write_en(write_en),.write_data(32'h12345678),
 .write_addr_0(21'd0),.write_addr_1(21'd691200),.write_addr_2(21'd1382400),.write_addr_3(21'd0),.write_addr_index(2'd1),.write_len(21'd460800),.write_vga(1'b0));
wire [23:0] out;wire ode,ovs;wire [6:0] index;wire initialized;
photo_spotlight_player dut(.mem_clk(mc),.mem_rst(rst),.enable(!rst),.base(21'd460800),
 .stream_start(light_req),.stream_offset(light_address),.stream_ack(light_ack),.data(light_data),.data_valid(light_valid),.error(error),
 .video_clk(vc),.video_rst(rst),.display_valid(1'b1),.pause(pause),.rgb_in(24'h283c50),.de_in(de),.vs_in(vs),
 .rgb_out(out),.de_out(ode),.vs_out(ovs),.frame_index(index),.initialized(initialized));
function integer threshold;input integer px,py;begin threshold=((px%2)^(py%2))*128+(py%2)*64+(((px/2)%2)^((py/2)%2))*32+((py/2)%2)*16+8;end endfunction
function integer map_byte;input integer f,px,py;begin map_byte=py<68 ? (raw[(f*68+py)*40+px/4]>>((px%4)*8))&255:0;end endfunction
function integer spatial;
 input integer f,px,py;integer lx,rx,uy,ly,fx,fy,top,bottom;
 begin
  lx=px<4 ? 0:(px-4)/8;uy=py<4 ? 0:(py-4)/8;
  if(lx>159)lx=159;if(uy>89)uy=89;rx=lx<159 ? lx+1:lx;ly=uy<89 ? uy+1:uy;
  fx=px<4 ? 0:(px-4)%8;fy=py<4 ? 0:(py-4)%8;
  top=map_byte(f,lx,uy)*(8-fx)+map_byte(f,rx,uy)*fx;
  bottom=map_byte(f,lx,ly)*(8-fx)+map_byte(f,rx,ly)*fx;
  spatial=(top*(8-fy)+bottom*fy+threshold(px,py)/4)/64;
 end
endfunction
function [7:0] lit;input integer c,t,a;begin lit=c+((t>c ? t-c:0)*a)/256;end endfunction
reg [23:0] expected[0:6];reg [6:0] expected_de=0,expected_vs=0;integer alpha,phase,p;
always @(posedge vc)if(!rst)begin
 for(p=6;p>0;p=p-1)expected[p]=expected[p-1];
 phase=(dut.step*256+1)/3;alpha=0;
 if(de)begin
  golden_frame=expected_frame==0 ? 0:expected_frame==1 || expected_frame==2 ? 1:expected_frame==3 ? 2:3;
  if(x==0 && y==0 && (index!=(expected_frame==4 ? 0:119) || dut.step!=(expected_frame==0 || expected_frame==4 ? 0:expected_frame==1 || expected_frame==2 ? 1:2)))$fatal(1,"temporal schedule mismatch frame %0d index/step %0d/%0d",expected_frame,index,dut.step);
  alpha=golden[golden_frame*921600+y*1280+x];
 end
 expected[0]={lit(40,255,alpha),lit(60,235,alpha),lit(80,200,alpha)};
 expected_de={expected_de[5:0],de};expected_vs={expected_vs[5:0],vs};
 #1;
 if(ode!==expected_de[6] || ovs!==expected_vs[6])$fatal(1,"light video alignment changed");
 if(ode && out!==expected[6])begin
 $display("DEBUG init=%b ready=%b idx=%0d step=%0d xy=%0d/%0d field=%0d rows=%h/%h expectedRows=%h/%h top=%h",initialized,dut.next_ready,index,dut.step,dut.pixel_x,dut.pixel_y,dut.field4,dut.row_bank[3],dut.row_bank[67],raw[(119*68)*40+3],raw[3],dut.point_data);
 $fatal(1,"light pixel mismatch %0d/%0d got=%h expected=%h frame=%0d phase=%0d",x,y,out,expected[6],index,phase);end
 if(ode)checks=checks+1;
end
initial begin
 $readmemh("light_golden.hex",golden);$readmemh("light_tail.hex",sparse);$readmemh("light_raw.hex",raw);
 repeat(8)@(negedge mc);rst=0;repeat(8)@(negedge mc);
 force dut.frame_index=119;
 for(f=0;f<TEST_FRAMES;f=f+1)begin
  expected_frame=f;word_number=0;read_req=1;if(f==0)write_req=1;wait(ack && (f!=0 || write_ack));@(negedge vc);read_req=0;write_req=0;wait(!ack);
  @(negedge vc);#1;running=1;
  wait(y==IMAGE_ROWS && x==1649);@(negedge vc); // initial blank already requested fields
  wait(y==IMAGE_ROWS-1 && x==1649);@(negedge vc);running=0;
  repeat(10)@(negedge vc);
  if(underflows || word_number!=IMAGE_ROWS*640)$fatal(1,"framebuffer starved words=%0d misses=%0d",word_number,underflows);
  if(f==0)release dut.frame_index;
  pause=f==1;
 end
 if(background_words<1000)$fatal(1,"background store made no progress");
 if(checks!=TEST_FRAMES*IMAGE_ROWS*1280 || refreshes<100 || line_jobs<TEST_FRAMES*(IMAGE_ROWS>=548 ? 60:6))$fatal(1,"insufficient scan coverage %0d %0d",checks,line_jobs);
 $display("PASS %0d spotlight scan frames, %0d pixels, zero underflow during photo store; %0d refreshes; worst row latency %0d memory clocks; %0d accepted photo words with 10 Mword/s offered load",TEST_FRAMES,checks,refreshes,max_latency,background_words);$finish;
end
initial begin #100000000;$fatal(1,"bus test timeout %0d/%0d",x,y);end
endmodule
