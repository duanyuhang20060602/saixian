`timescale 1ns/1ps
// Six-entry directory, three SDRAM slots. A locked transmit slot is never a
// load destination. Neighbour prefetch runs while the link consumes its slot.
module photo_sd_cache #(parameter CLK_HZ=100000000,SCAN_MAX_SECTOR=1048575,FRAME_WORDS=460800,FORWARD_ONLY=0,DISPLAY_PIN=0)(
 input display_valid,input [2:0] display_image,input prefetch_pause,
 input clk,rst,request,input [2:0] target,input release_slot,cancel,
 output reg [1:0] ready_gain,output reg ready,output reg [1:0] ready_slot,output reg [2:0] image_count,
 output reg [3:0] error,output directory_ready,
 output reg [15:0] ready_source_width,ready_source_height,
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
reg [15:0] directory_width[0:5],directory_height[0:5];
reg [1:0] load_slot;reg [2:0] load_image,current_image,wanted,playback_image;
reg demand,scanned,scanning,loading,load_started;
reg [31:0] timer,init_timer;reg fin_meta,fin_sync,fin_seen;
reg [1:0] cache_gain[0:2];
reg [10:0] stat_x;reg [9:0] stat_y;reg [20:0] stat_sum;reg [12:0] stat_count;
wire [20:0] count_ext={8'd0,stat_count};
wire [9:0] raw_luma={2'd0,pixel[23:16]}+{1'b0,pixel[15:8],1'b0}+{2'd0,pixel[7:0]};
wire [1:0] loaded_gain=stat_sum<(count_ext<<6) ? 2'd3:
 stat_sum<((count_ext<<6)+(count_ext<<5)) ? 2'd2:
 stat_sum<((count_ext<<7)+(count_ext<<4)) ? 2'd1:2'd0;
reg half;reg [15:0] first;reg [20:0] words;
reg read_owner,read_settle;reg [31:0] read_address;
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
wire [2:0] second_prefetch=FORWARD_ONLY ? next_id(next_id(current_image,image_count),image_count):prev_id(current_image,image_count);
// Pin only while adjusting settings. Playback retains all three slots for
// the last transmitted image and its two forward neighbours.
wire pin_active=DISPLAY_PIN && display_valid && prefetch_pause;
reg pin_hit;
reg hit,next_hit,prev_hit;reg [1:0] hit_slot,victim;
reg victim_ok;integer i;
always @*begin
 pin_hit=0;hit=0;hit_slot=0;next_hit=0;prev_hit=0;victim=0;victim_ok=0;
 for(i=0;i<3;i=i+1)begin
  if(cache_valid[i] && cache_id[i]==display_image)pin_hit=1;
  if(cache_valid[i] && (!loading || load_slot!=i) && cache_id[i]==wanted)begin hit=1;hit_slot=i;end
  if(cache_valid[i] && cache_id[i]==next_id(current_image,image_count))next_hit=1;
  if(cache_valid[i] && cache_id[i]==second_prefetch)prev_hit=1;
 end
 // Prefer invalid slots; otherwise evict a non-current, non-locked slot
 // which is not the other neighbour we intend to preserve.
 for(i=2;i>=0;i=i-1)begin
  if((!pin_active || !cache_valid[i] || cache_id[i]!=display_image) && (!ready || ready_slot!=i) && (!loading || load_slot!=i) && (!demand || !hit || hit_slot!=i) &&
    (!cache_valid[i] || (cache_id[i]!=current_image &&
     (demand || cache_id[i]!=next_id(current_image,image_count)))))begin victim=i;victim_ok=1;end
 end
 for(i=2;i>=0;i=i-1)
  if(!cache_valid[i] && (!ready || ready_slot!=i) && (!loading || load_slot!=i))begin victim=i;victim_ok=1;end
end
always @(posedge clk or posedge rst)begin
 if(rst)begin read_owner<=0;read_settle<=0;read_address<=0;end
 else if(abort_op)begin read_owner<=0;read_settle<=0;end
 // Allow BMP request/address registers to settle after sector completion.
 // In particular, do not enqueue a stale request at the end of a file.
 else if(sector_end)begin read_owner<=0;read_settle<=1;end
 else if(read_settle)read_settle<=0;
 else if(!read_owner && bmp_read_req)begin read_owner<=1;read_address<=bmp_read_addr;end
end
sd_card_top #(.SPI_LOW_SPEED_DIV(248),.SPI_HIGH_SPEED_DIV(2),.READ_MULTIBLOCK(1),.FAST_READ_STREAM(1)) sd(
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
// Reset word accounting from the registered load pulse, keeping the cache
// victim/priority decoder out of the 100 MHz counter enable path.
always @(posedge clk or posedge rst)begin
 if(rst)words<=0;
 else if(load_start)words<=0;
 else if(loading && write_en && !full)words<=words+1'b1;
end
always @(posedge clk or posedge rst)begin
 if(rst)begin
  ready_gain<=1;stat_x<=0;stat_y<=0;stat_sum<=0;stat_count<=0;
  ready<=0;ready_slot<=0;image_count<=0;error<=0;cache_valid<=0;load_slot<=0;load_image<=0;
  ready_source_width<=0;ready_source_height<=0;
  current_image<=0;playback_image<=0;wanted<=0;demand<=0;scanned<=0;scanning<=0;loading<=0;load_started<=0;
  scan_start<=0;load_start<=0;abort_op<=0;load_sector<=0;timer<=0;init_timer<=0;fin_seen<=0;
  half<=0;first<=0;write_en<=0;write_data<=0;
 end else begin
  scan_start<=0;load_start<=0;abort_op<=0;write_en<=0;
  if(!initialized)begin
   if(init_timer>=CLK_HZ*8)begin abort_op<=1;init_timer<=0;scanning<=0;end
   else init_timer<=init_timer+1'b1;
  end else init_timer<=0;
  if(initialized && !scanned && !scanning && bmp_ready)begin scan_start<=1;scanning<=1;image_count<=0;timer<=0;end
  if(scanning)begin
   timer<=timer+1'b1;
   if(found && image_count<6)begin
    directory[image_count]<=sector;directory_width[image_count]<=width;directory_height[image_count]<=height;
    image_count<=image_count+1'b1;timer<=0;
   end
   if(scan_done || image_count==6)begin scanning<=0;scanned<=1;if(image_count==0 && !found)error<=1;end
   // Stop after a finite idle period on cards with fewer than six images.
   if(timer>=CLK_HZ*20)begin scanning<=0;scanned<=1;abort_op<=1;if(image_count==0)error<=1;end
  end
  if(request && scanned && target<image_count)begin wanted<=target;demand<=1;ready<=0;error<=0;end
  if(release_slot)begin ready<=0;playback_image<=cache_id[ready_slot];
   if(!pin_active)current_image<=cache_id[ready_slot];
  end
  // During settings, follow the HDMI image; during playback, follow the sender.
  if(pin_active)current_image<=display_image;
  else if(!release_slot)current_image<=playback_image;
  if(cancel)begin ready<=0;demand<=0;end
  // Deliver a complete cached image even while BMP/SD is loading another
  // slot. ready locks hit_slot until release_slot; load_slot stays separate.
  // Control pulses win over the previous cycle's pending demand.
  if(!request && !release_slot && !cancel && scanned && error==0)begin
   if(demand && hit && !ready)begin
    ready<=1;ready_slot<=hit_slot;ready_gain<=cache_gain[hit_slot];demand<=0;
    ready_source_width<=directory_width[wanted];ready_source_height<=directory_height[wanted];
   end
   else if(!loading && bmp_ready && (!DISPLAY_PIN || current_image==(pin_active ? display_image:playback_image)))begin
   if(demand && !hit && victim_ok)begin
    load_slot<=victim;load_image<=wanted;load_sector<=directory[wanted];load_start<=1;loading<=1;
    cache_valid[victim]<=0;load_started<=0;half<=0;fin_seen<=fin_sync;timer<=0;
   end else if(!demand && pin_active && !pin_hit && victim_ok)begin
    // Restore the actual HDMI image before any speculative SD read.
    load_slot<=victim;load_image<=display_image;load_sector<=directory[display_image];load_start<=1;loading<=1;
    cache_valid[victim]<=0;load_started<=0;half<=0;fin_seen<=fin_sync;timer<=0;
   end else if(!demand && (!DISPLAY_PIN || !prefetch_pause) && image_count>1 && !next_hit && victim_ok)begin
    load_slot<=victim;load_image<=next_id(current_image,image_count);
    load_sector<=directory[next_id(current_image,image_count)];load_start<=1;loading<=1;
    cache_valid[victim]<=0;load_started<=0;half<=0;fin_seen<=fin_sync;timer<=0;
   end else if(!demand && (!DISPLAY_PIN || !prefetch_pause) && image_count>1 && next_hit && !prev_hit && victim_ok)begin
    load_slot<=victim;load_image<=second_prefetch;
    load_sector<=directory[second_prefetch];load_start<=1;loading<=1;
    cache_valid[victim]<=0;load_started<=0;half<=0;fin_seen<=fin_sync;timer<=0;
   end
   end
  end
  if(load_start)begin stat_x<=0;stat_y<=0;stat_sum<=0;stat_count<=0;end
  if(loading)begin
   timer<=timer+1'b1;
   if(write_req)begin half<=0;load_started<=1;end
   if(scaler_pixel)begin
    if(stat_x[3:0]==0 && stat_y[3:0]==0)begin stat_sum<=stat_sum+raw_luma[9:2];stat_count<=stat_count+1'b1;end
    if(stat_x==1279)begin stat_x<=0;stat_y<=stat_y+1'b1;end else stat_x<=stat_x+1'b1;
    if(!half)begin first<=rgb565(pixel);half<=1;end
    else begin write_data<={first,rgb565(pixel)};write_en<=1;half<=0;end
   end
   
   if(load_started && bmp_ready && fin_sync!=fin_seen)begin
    loading<=0;fin_seen<=fin_sync;
    if(words==FRAME_WORDS && !half)begin cache_valid[load_slot]<=1;cache_id[load_slot]<=load_image;cache_gain[load_slot]<=loaded_gain;end
    else begin error<=3;abort_op<=1;end
   end
   if((write_en && full) || scaler_fault || timer>=64'd30*CLK_HZ)begin
    error<=write_en && full ? 4'd4:4'd2;loading<=0;abort_op<=1;
   end
  end
 end
end
endmodule
