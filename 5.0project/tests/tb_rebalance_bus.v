`timescale 1ns/1ps
// Production framebuffer/FIFOs with indexed relief reads at 75/50 MHz.
// Native SDRAM response latency and refresh exclusion are modeled explicitly.
module tb #(parameter TEST_FRAMES=2,IMAGE_ROWS=720);
reg mc=0,vc=0,rst=1;always #10 mc=~mc;always #6.666667 vc=~vc;
reg [31:0] sparse[0:524287];integer f;
reg [11:0] pipeline=0;reg [31:0] response[0:11];
reg [3:0] launch=0;reg [20:0] launch_address;
integer x=0,y=IMAGE_ROWS,frames=0,word_number=0,checks=0,underflows=0,max_latency=0,request_cycle=0,line_jobs=0,write_commands=0;
integer cycle=0,i,refreshes=0;reg refresh=0,pending_refresh=0;reg [4:0] refresh_left=0;
wire light_wide,light_req,light_ack,light_valid,claim,light_rd,frame_rd,wr,frame_busy;
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
 if(wr)write_commands=write_commands+1;
 if(rd)begin
  if(refresh || wr)$fatal(1,"native command overlap");
  response[0]<=ra<460800 ? ra:sparse[ra-460800];
 end
  for(i=1;i<12;i=i+1)response[i]<=response[i-1];
  if(cycle%389==0)pending_refresh<=1;
  if(pending_refresh && !busy && !claim && !frame_busy)begin refresh<=1;refresh_left<=8;pending_refresh<=0;refreshes<=refreshes+1;end
  else if(refresh)begin if(refresh_left==0)refresh<=0;else refresh_left<=refresh_left-1'b1;end
  if(error)$fatal(1,"light error=%0d video_error=%b at raster %0d/%0d source=%0d requestrow=%0d next=%0d valid=%b tags=%0d,%0d,%0d,%0d memstate=%0d column=%0d pending=%0d maxlat=%0d",error,dut.video_error,x,y,dut.source_row,dut.requested_row,dut.next_prefetch_row,dut.row_valid,0,0,0,0,dut.state,dut.column,dut.pending,max_latency);
  if(claim && (frame_rd || wr))$fatal(1,"framebuffer uses reserved light turn");
 end
end
photo_award_memory bus(.wide_request(light_wide),.clk(mc),.rst(rst),.enable(1'b1),.init_done(1'b1),.refresh(refresh_gate),.busy(busy),.frame_busy(frame_busy),
 .request(light_req),.address(light_address),.acknowledge(light_ack),.data(light_data),.valid(light_valid),
 .claim(claim),.read_command(light_rd),.read_address(light_ra),.response_valid(response_valid && claim),.response(response_data));

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
 if(!rst && dut.pending && request_cycle==0)request_cycle=cycle;
 if(!rst && !dut.pending && request_cycle!=0)begin
  if(cycle-request_cycle>max_latency)max_latency=cycle-request_cycle;
  request_cycle=0;line_jobs=line_jobs+1;
 end
end
always @(negedge vc)if(running)begin
 if(x==1649)begin x=0;if(y==IMAGE_ROWS+29)begin y=0;frames=frames+1;end else y=y+1;end else x=x+1;
end
wire external_allowed;
frame_read_write rw(.display_active(1'b1),.external_allowed(external_allowed),.external_request(light_req),.external_busy(claim),.access_busy(frame_busy),
 .fluid_progress(9'd0),.water_cfg(77'd0),.rst(rst),.mem_clk(mc),
 .Sdr_init_done(1'b1),.Sdr_init_ref_vld(refresh_gate),.Sdr_busy(busy),.App_rd_en(frame_rd),.App_rd_addr(frame_ra),
 .Sdr_rd_en(response_valid && !claim),.Sdr_rd_dout(response_data),.read_clk(vc),.read_req(read_req),.read_req_ack(ack),.read_finish(finish),
 .read_addr_0(21'd0),.read_addr_1(21'd1048576),.read_addr_2(21'd0),.read_addr_3(21'd0),.read_addr_index(2'd0),.read_len(IMAGE_ROWS*640),
 .read_en(pop),.read_data(pixel_data),.read_fifo_empty(empty),.slide_active(1'b0),.slide_old_index(2'd0),.slide_new_index(2'd1),
 .slide_offset(11'd0),.slide_right(1'b0),.transition_mode(5'd0),.buffer0_vga(1'b0),.buffer1_vga(1'b0),
 .App_wr_en(wr),.App_wr_addr(wa),.App_wr_din(wd),.App_wr_dm(dm),.write_clk(mc),.write_req(write_req),.write_req_ack(write_ack),.write_fifo_full(write_full),.write_en(write_en),.write_data(32'h12345678),
 .write_addr_0(21'd0),.write_addr_1(21'd1048576),.write_addr_2(21'd0),.write_addr_3(21'd0),.write_addr_index(2'd1),.write_len(21'd460800),.write_vga(1'b0));
wire [23:0] out;wire [4:0] angle;
wire [7:0] palette_address;wire [6:0] wall_address;reg [31:0] palette_data;reg [23:0] wall_data;
reg [31:0] lit_palette[0:511];reg [23:0] wall_table[0:127];
always @(posedge vc)begin palette_data<=lit_palette[{f[0],palette_address}];wall_data<=wall_table[wall_address];end

photo_relief_player #(.REMOTE_RELIEF(1),.SHARED_PALETTE(1),.HOLD_FRAMES(2)) dut(
 .remote_valid(1'b1),.remote_angle(f[4:0]),.remote_light_x(-6'sd16),.remote_light_y(6'sd6),
 .cache_read_address(palette_address),.cache_read_data(palette_data),.wall_address(wall_address),.wall_rgb(wall_data),.mem_clk(mc),.mem_rst(rst),.enable(!rst),.base(21'd460800),
 .wide_request(light_wide),.request(light_req),.address(light_address),.ack(light_ack),.data(light_data),.valid(light_valid),.error(error),
 .clk(vc),.rst(rst),.pause(pause),.rgb_in(24'h283c50),.de(de),.frame_tick(vs),.x(x[10:0]),.y(y[9:0]),
 .rgb_out(out),.angle(angle),.touch_contact(1'b0),.cursor_x(11'd640),.cursor_y(10'd360));
always @(posedge vc)if(de)begin
 checks=checks+1;
 if(x==0 && y==0 && angle!=f)$fatal(1,"rotation angle mismatch got=%0d frame=%0d",angle,f);
 if(x>=352 && x<928 && y>=48 && y<624 && (^out===1'bx))$fatal(1,"unknown pixel under shared memory load");
end
initial begin
 $readmemh("relief_tail.hex",sparse);
 $readmemh("lit_palettes.hex",lit_palette);$readmemh("wall_table.hex",wall_table);
 repeat(8)@(negedge mc);rst=0;repeat(8)@(negedge mc);
 for(f=0;f<TEST_FRAMES;f=f+1)begin
  word_number=0;read_req=1;if(f==0)write_req=1;wait(ack && (f!=0 || write_ack));@(negedge vc);read_req=0;write_req=0;wait(!ack);
  @(negedge vc);#1;running=1;
  wait(y==IMAGE_ROWS && x==1649);@(negedge vc); // initial blank already requested fields
  wait(y==IMAGE_ROWS-1 && x==1649);@(negedge vc);running=0;
  repeat(10)@(negedge vc);
  if(underflows || word_number!=IMAGE_ROWS*640)$fatal(1,"framebuffer starved words=%0d misses=%0d",word_number,underflows);

 end
 if(background_words<1000 || write_commands<1000)$fatal(1,"background store made no progress");
 if(checks!=TEST_FRAMES*IMAGE_ROWS*1280 || refreshes<100 || line_jobs!=TEST_FRAMES*576)$fatal(1,"insufficient scan coverage %0d %0d",checks,line_jobs);
 $display("PASS %0d full 720p relief frames, %0d pixels, zero framebuffer/row underflow; %0d completed rows; %0d refreshes; worst row latency %0d memory clocks; %0d accepted/%0d written background words with 10 Mword/s offered load",TEST_FRAMES,checks,line_jobs,refreshes,max_latency,background_words,write_commands);$finish;
end
initial begin #100000000;$fatal(1,"bus test timeout %0d/%0d",x,y);end
endmodule
