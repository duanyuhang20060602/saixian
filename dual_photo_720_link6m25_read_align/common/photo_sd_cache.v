`timescale 1ns/1ps
// Six-entry directory, three SDRAM slots. A locked transmit slot is never a
// load destination. Neighbour prefetch runs while the link consumes its slot.
module photo_sd_cache #(parameter CLK_HZ=100000000,SCAN_MAX_SECTOR=1048575,FRAME_WORDS=460800)(
 input clk,rst,request,input [2:0] target,input release_slot,cancel,
 output reg ready,output reg [1:0] ready_slot,output reg [2:0] image_count,
 output reg [3:0] error,output directory_ready,
 output [1:0] write_slot,output write_req,input write_ack,full,
 output reg write_en,output reg [31:0] write_data,input finish_toggle,
 output sd_ncs,sd_dclk,sd_mosi,input sd_miso
);
wire initialized,bmp_ready,scan_done,found,scaler_pixel;
wire [31:0] sector;wire [15:0] width,height;wire [23:0] pixel;
wire [3:0] bmp_state;wire [31:0] bmp_read_addr;wire bmp_read_req;
wire sector_end,byte_valid,scaler_fault;wire [7:0] byte_data;
reg scan_start,load_start,abort_op;reg [31:0] load_sector;
reg [31:0] directory[0:5];reg [2:0] cache_id[0:2];reg [2:0] cache_valid;
reg [1:0] load_slot;reg [2:0] load_image,current_image,wanted;
reg demand,scanned,scanning,loading,load_started;
reg [31:0] timer,init_timer;reg fin_meta,fin_sync,fin_seen;
reg half;reg [15:0] first;reg [20:0] words;
reg read_owner;reg [31:0] read_address;
assign write_slot=load_slot;
assign directory_ready=scanned && image_count!=0;
function [15:0] rgb565;
 input [23:0] rgb;begin rgb565={rgb[23:19],rgb[15:10],rgb[7:3]};end
endfunction
function [2:0] next_id;
 input [2:0] id,count;begin next_id=id==count-1 ? 0:id+1'b1;end
endfunction
function [2:0] prev_id;
 input [2:0] id,count;begin prev_id=id==0 ? count-1:id-1'b1;end
endfunction
reg hit,next_hit,prev_hit;reg [1:0] hit_slot,victim;
reg victim_ok;integer i;
always @*begin
 hit=0;hit_slot=0;next_hit=0;prev_hit=0;victim=0;victim_ok=0;
 for(i=0;i<3;i=i+1)begin
  if(cache_valid[i] && cache_id[i]==wanted)begin hit=1;hit_slot=i;end
  if(cache_valid[i] && cache_id[i]==next_id(current_image,image_count))next_hit=1;
  if(cache_valid[i] && cache_id[i]==prev_id(current_image,image_count))prev_hit=1;
 end
 // Prefer invalid slots; otherwise evict a non-current, non-locked slot
 // which is not the other neighbour we intend to preserve.
 for(i=2;i>=0;i=i-1)begin
  if((!ready || ready_slot!=i) && (!loading || load_slot!=i) &&
    (!cache_valid[i] || (cache_id[i]!=current_image &&
     (demand || cache_id[i]!=next_id(current_image,image_count)))))begin victim=i;victim_ok=1;end
 end
 for(i=2;i>=0;i=i-1)
  if(!cache_valid[i] && (!ready || ready_slot!=i) && (!loading || load_slot!=i))begin victim=i;victim_ok=1;end
end
always @(posedge clk or posedge rst)begin
 if(rst)begin read_owner<=0;read_address<=0;end
 else if(abort_op)read_owner<=0;
 else if(!read_owner && bmp_read_req)begin read_owner<=1;read_address<=bmp_read_addr;end
 else if(sector_end)read_owner<=0;
end
sd_card_top #(.SPI_LOW_SPEED_DIV(248),.SPI_HIGH_SPEED_DIV(2)) sd(
 .clk(clk),.rst(rst || abort_op),.SD_nCS(sd_ncs),.SD_DCLK(sd_dclk),.SD_MOSI(sd_mosi),.SD_MISO(sd_miso),
 .sd_init_done(initialized),.init_stage(),.sd_sec_read(read_owner),.sd_sec_read_addr(read_address),
 .sd_sec_read_data(byte_data),.sd_sec_read_data_valid(byte_valid),.sd_sec_read_end(sector_end),
 .sd_sec_write(1'b0),.sd_sec_write_addr(32'd0),.sd_sec_write_data(8'd0),.sd_sec_write_data_req(),.sd_sec_write_end());
bmp_read bmp(.clk(clk),.rst(rst),.op_abort(abort_op),.ready(bmp_ready),
 .scan_start(scan_start),.scan_stop(image_count==6),.scan_start_sector(32'd0),.scan_max_sector(SCAN_MAX_SECTOR),
 .scan_target_count(3'd6),.scan_done(scan_done),.scan_found_valid(found),.scan_found_sector(sector),
 .scan_found_total(),.scan_found_width(width),.scan_found_height(height),.scan_found_sprint(),
 .audio_found_valid(),.audio_found_index(),.audio_found_sector(),.audio_found_bytes(),
 .load_start(load_start),.load_sector(load_sector),.sd_init_done(initialized),.state_code(bmp_state),
 .bmp_width(16'd1280),.bmp_height(16'd720),.write_req(write_req),.write_req_ack(write_ack),
 .sd_sec_read(bmp_read_req),.sd_sec_read_addr(bmp_read_addr),.sd_sec_read_data(byte_data),
 .sd_sec_read_data_valid(byte_valid && read_owner),.sd_sec_read_end(sector_end && read_owner),
 .bmp_data_wr_en(scaler_pixel),.bmp_data(pixel),.scaler_fault_o(scaler_fault));
always @(posedge clk or posedge rst)begin
 if(rst)begin fin_meta<=0;fin_sync<=0;end
 else begin fin_meta<=finish_toggle;fin_sync<=fin_meta;end
end
always @(posedge clk or posedge rst)begin
 if(rst)begin
  ready<=0;ready_slot<=0;image_count<=0;error<=0;cache_valid<=0;load_slot<=0;load_image<=0;
  current_image<=0;wanted<=0;demand<=0;scanned<=0;scanning<=0;loading<=0;load_started<=0;
  scan_start<=0;load_start<=0;abort_op<=0;load_sector<=0;timer<=0;init_timer<=0;fin_seen<=0;
  half<=0;first<=0;words<=0;write_en<=0;write_data<=0;
 end else begin
  scan_start<=0;load_start<=0;abort_op<=0;write_en<=0;
  if(!initialized)begin
   if(init_timer>=CLK_HZ*8)begin abort_op<=1;init_timer<=0;scanning<=0;end
   else init_timer<=init_timer+1'b1;
  end else init_timer<=0;
  if(initialized && !scanned && !scanning && bmp_ready)begin scan_start<=1;scanning<=1;image_count<=0;timer<=0;end
  if(scanning)begin
   timer<=timer+1'b1;
   if(found && image_count<6)begin directory[image_count]<=sector;image_count<=image_count+1'b1;timer<=0;end
   if(scan_done || image_count==6)begin scanning<=0;scanned<=1;if(image_count==0 && !found)error<=1;end
   // Stop after a finite idle period on cards with fewer than six images.
   if(timer>=CLK_HZ*20)begin scanning<=0;scanned<=1;abort_op<=1;if(image_count==0)error<=1;end
  end
  if(request && scanned && target<image_count)begin wanted<=target;demand<=1;ready<=0;error<=0;end
  if(release_slot)begin ready<=0;current_image<=cache_id[ready_slot];end
  if(cancel)begin ready<=0;demand<=0;end
  if(!loading && scanned && bmp_ready && error==0)begin
   if(demand && hit && !ready)begin ready<=1;ready_slot<=hit_slot;demand<=0;end
   else if(demand && !hit && victim_ok)begin
    load_slot<=victim;load_image<=wanted;load_sector<=directory[wanted];load_start<=1;loading<=1;
    cache_valid[victim]<=0;load_started<=0;words<=0;half<=0;fin_seen<=fin_sync;timer<=0;
   end else if(!demand && image_count>1 && !next_hit && victim_ok)begin
    load_slot<=victim;load_image<=next_id(current_image,image_count);
    load_sector<=directory[next_id(current_image,image_count)];load_start<=1;loading<=1;
    cache_valid[victim]<=0;load_started<=0;words<=0;half<=0;fin_seen<=fin_sync;timer<=0;
   end else if(!demand && image_count>1 && next_hit && !prev_hit && victim_ok)begin
    load_slot<=victim;load_image<=prev_id(current_image,image_count);
    load_sector<=directory[prev_id(current_image,image_count)];load_start<=1;loading<=1;
    cache_valid[victim]<=0;load_started<=0;words<=0;half<=0;fin_seen<=fin_sync;timer<=0;
   end
  end
  if(loading)begin
   timer<=timer+1'b1;
   if(write_req)begin half<=0;load_started<=1;end
   if(scaler_pixel)begin
    if(!half)begin first<=rgb565(pixel);half<=1;end
    else begin write_data<={first,rgb565(pixel)};write_en<=1;half<=0;end
   end
   if(write_en && !full)words<=words+1'b1;
   if(load_started && bmp_ready && fin_sync!=fin_seen)begin
    loading<=0;fin_seen<=fin_sync;
    if(words==FRAME_WORDS && !half)begin cache_valid[load_slot]<=1;cache_id[load_slot]<=load_image;end
    else begin error<=3;abort_op<=1;end
   end
   if((write_en && full) || scaler_fault || timer>=64'd30*CLK_HZ)begin
    error<=write_en && full ? 4'd4:4'd2;loading<=0;abort_op<=1;
   end
  end
 end
end
endmodule
