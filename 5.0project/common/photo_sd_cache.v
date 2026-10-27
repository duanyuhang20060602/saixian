`timescale 1ns/1ps
// Six-entry directory, two external SDRAM slots. A locked transmit slot is never a
// load destination. Neighbour prefetch runs while the link consumes its slot.
module photo_sd_cache #(parameter CLK_HZ=100000000,SCAN_MAX_SECTOR=1048575,FRAME_WORDS=460800,FORWARD_ONLY=0,DISPLAY_PIN=0,EARLY_PREFETCH=0,TITLE_SD=0,INDEPENDENT_TEXT=0)(
 output title_ready,output [4:0] title_length,input [6+INDEPENDENT_TEXT:0] title_address,output [31:0] title_data,
 input display_valid,input [2:0] display_image,input prefetch_pause,
 input audio_packet_active,input audio_request_valid,input [7:0] requested_audio_epoch,input [2:0] requested_audio_track,
 output reg [7:0] active_audio_epoch,output reg [2:0] active_audio_track,audio_count,
 output [3:0] audio_scan_state,output audio_switching,output audio_stream_reset,output [13:0] audio_fifo_used,output [31:0] audio_fifo_data,input audio_fifo_read,
 input clk,rst,request,input [2:0] target,input release_slot,cancel,
 output reg [1:0] ready_gain,output reg ready,output reg [1:0] ready_slot,output reg [2:0] image_count,
 output reg [3:0] error,output directory_ready,output reg award_available,relief_available,output award_scan_complete,
 output reg [3:0] award_decode_error,
 output reg [15:0] ready_source_width,ready_source_height,
 output write_relief,output write_award,output [1:0] write_slot,output write_req,output write_top_down,input write_ack,full,
 output write_en,output [31:0] write_data,input finish_toggle,
 output sd_ncs,sd_dclk,sd_mosi,input sd_miso
);
reg demand,scanned,scanning,loading,load_started;

wire initialized,bmp_ready,scan_done,scan_exhausted,found,scaler_pixel;
wire [31:0] sector;wire [15:0] width,height;wire [23:0] pixel,bmp_pixel;
wire found_dlt,bmp_pixel_valid,bmp_write_req,bmp_fault;
reg [7:0] directory_dlt;reg load_is_dlt;
wire dlt_ready,dlt_done,dlt_pixel_valid,dlt_req,dlt_write_req;wire [23:0] dlt_pixel;
wire [31:0] dlt_sector;wire [3:0] dlt_error;
assign scaler_pixel=load_is_dlt ? dlt_pixel_valid:bmp_pixel_valid;
assign pixel=load_is_dlt ? dlt_pixel:bmp_pixel;
assign write_req=load_is_dlt ? dlt_write_req:bmp_write_req;
assign write_top_down=loading && load_is_dlt;
wire load_ready=load_is_dlt ? (dlt_ready && dlt_done):bmp_ready;
wire [3:0] bmp_state;wire [31:0] bmp_read_addr;wire bmp_read_req;
wire sector_end,byte_valid,scaler_fault;wire [7:0] byte_data;
reg [1:0] read_owner;reg read_settle;reg [31:0] read_address;
generate if(TITLE_SD)begin:title_storage
photo_sd_title_store #(.INDEPENDENT_TEXT(INDEPENDENT_TEXT)) title_store(.clk(clk),.rst(rst),
 .valid(TITLE_SD && byte_valid && read_owner==1),.data(byte_data),
 .sector_end(sector_end && read_owner==1),.ready(title_ready),.length(title_length),
 .address(title_address),.word(title_data));
end else begin:no_sd_title
 assign title_ready=0;assign title_length=0;assign title_data=0;
end endgenerate
assign scaler_fault=load_is_dlt ? dlt_error!=0:bmp_fault;
reg scan_start,scan_resume,scan_complete,scan_yield;reg load_start,load_launch,abort_op;reg [31:0] load_sector;
reg scan_stop_q;
always @(posedge clk or posedge rst)
 if(rst)scan_stop_q<=0;else scan_stop_q<=(image_count!=0 || award_available || relief_available) && (!scanned || scan_yield || (image_count==6 && audio_count==5 && award_available && relief_available && (!TITLE_SD || title_ready)));
reg [31:0] directory[0:7];reg [2:0] cache_id[0:1];reg [1:0] cache_valid;
reg [15:0] directory_width[0:7],directory_height[0:7];
reg [1:0] load_slot;reg [2:0] load_image,current_image,wanted,playback_image;

localparam [31:0] SCAN_LIMIT=CLK_HZ*20;
localparam [63:0] LOAD_LIMIT=64'd30*CLK_HZ;
reg due_scan,due_load;
reg [31:0] timer,init_timer;reg fin_meta,fin_sync,fin_seen;
reg [1:0] cache_gain[0:1];
reg [10:0] stat_x;reg [9:0] stat_y;reg [20:0] stat_sum;reg [12:0] stat_count;
wire [20:0] count_ext={8'd0,stat_count};
wire [9:0] raw_luma={2'd0,pixel[23:16]}+{1'b0,pixel[15:8],1'b0}+{2'd0,pixel[7:0]};
// Maintain exact multiples while sampling, instead of adding wide
// shifted counts on the final cache-gain selection path.
reg [14:0] stat_count3;
reg [16:0] stat_count9;
wire stat_sample=loading && scaler_pixel && stat_x[3:0]==0 && stat_y[3:0]==0;
always @(posedge clk or posedge rst)begin:gain_counts
 if(rst)begin stat_count3<=0;stat_count9<=0;end
 else if(stat_sample)begin
  stat_count3<=stat_count==13'h1fff ? 15'd0:stat_count3+15'd3;
  stat_count9<=stat_count==13'h1fff ? 17'd0:stat_count9+17'd9;
 end else if(load_start)begin stat_count3<=0;stat_count9<=0;end
end
wire [1:0] loaded_gain=stat_sum<(count_ext<<6) ? 2'd3:
 stat_sum<{1'b0,stat_count3,5'd0} ? 2'd2:
 stat_sum<{stat_count9,4'd0} ? 2'd1:2'd0;
reg [20:0] words;
wire pack_aligned;
wire [20:0] frame_words=FRAME_WORDS;
photo_color_pack packing(.clk(clk),.rst(rst),.clear(load_start || write_req),
 .valid(scaler_pixel && loading),.rgb(pixel),.word_valid(write_en),.word_data(write_data),.aligned(pack_aligned));

assign write_slot=load_slot;
assign write_award=load_is_dlt;
assign write_relief=load_is_dlt && load_image==7;
assign directory_ready=scanned && (image_count!=0 || award_available || relief_available);
assign award_scan_complete=scan_complete;
function [15:0] rgb565;
 input [23:0] rgb;begin rgb565={rgb[23:19],rgb[15:10],rgb[7:3]};end
endfunction
function [2:0] next_id;
 input [2:0] id,count;begin next_id=(count==0 || id>=count-1) ? 0:id+1'b1;end
endfunction
function [2:0] prev_id;
 input [2:0] id,count;begin prev_id=id==0 ? count-1:id-1'b1;end
endfunction
// Pin only while adjusting settings. Playback keeps current and next;
// never replace the locked transmit slot or the actual HDMI settings image.
wire pin_active=DISPLAY_PIN && display_valid && prefetch_pause;
reg pin_hit,current_hit;
reg hit,next_hit;reg [1:0] hit_slot,victim;
reg victim_ok;integer i;
always @*begin
 current_hit=0;pin_hit=0;hit=0;hit_slot=0;next_hit=0;victim=0;victim_ok=0;
 for(i=0;i<2;i=i+1)begin
  if(cache_valid[i] && cache_id[i]==display_image)pin_hit=1;
  if(cache_valid[i] && cache_id[i]==current_image)current_hit=1;
  if(cache_valid[i] && (!loading || load_slot!=i) && cache_id[i]==wanted)begin hit=1;hit_slot=i;end
  if(cache_valid[i] && cache_id[i]==next_id(current_image,image_count))next_hit=1;
 end
 // Prefer invalid slots; otherwise evict a non-current, non-locked slot
 // which is not the other neighbour we intend to preserve.
 for(i=1;i>=0;i=i-1)begin
  if((!pin_active || !cache_valid[i] || cache_id[i]!=display_image) && (!ready || ready_slot!=i) && (!loading || load_slot!=i) && (!demand || !hit || hit_slot!=i) &&
    (!cache_valid[i] || (cache_id[i]!=current_image &&
     (demand || cache_id[i]!=next_id(current_image,image_count)))))begin victim=i;victim_ok=1;end
 end
 for(i=1;i>=0;i=i-1)
  if(!cache_valid[i] && (!ready || ready_slot!=i) && (!loading || load_slot!=i))begin victim=i;victim_ok=1;end
end
wire audio_sd_req,audio_pcm_we,audio_found;
wire [31:0] audio_sd_addr,audio_pcm_word,audio_found_sector,audio_found_bytes;
reg [31:0] audio_sectors[0:4],audio_lengths[0:4];
reg change_pending;reg [7:0] pending_epoch;reg [2:0] pending_track,flush_count;
wire audio_empty,audio_full;
assign audio_switching=change_pending || flush_count!=0;
assign audio_scan_state=!initialized ? 4'd1:scanning ? 4'd2:!scan_complete ? 4'd6:audio_count==0 ? 4'd3:audio_fifo_used<128 ? 4'd4:4'd5;
wire audio_reset=rst || abort_op || flush_count!=0 || scan_start;
assign audio_stream_reset=audio_reset;
wire audio_enable=initialized && audio_count!=0 && active_audio_track<audio_count && !audio_switching;
// Refill starts at <=4096 frames and one sector adds <=128 frames.
// One registered PCM write may still be pending: legal occupancy <=4225.
// Keep the same refill waterline with a 4352-frame physical ring, including
// 127 frames of extra headroom. The upper 3968 old slots were unreachable.
photo_audio_fifo_compact audio_fifo(.clk(clk),.rst(audio_reset),.write_en(audio_pcm_we && !audio_switching),.write_data(audio_pcm_word),
 .read_en(audio_fifo_read && !audio_switching),.data(audio_fifo_data),.used(audio_fifo_used),.empty(audio_empty),.full(audio_full));
photo_sd_audio_stream audio_stream(.clk(clk),.rst(audio_reset),.enable(audio_enable),
 .start_sector(audio_sectors[active_audio_track]),.data_bytes(audio_lengths[active_audio_track]),.fifo_wrusedw(audio_fifo_used),
 .sd_sec_read(audio_sd_req),.sd_sec_read_addr(audio_sd_addr),.sd_sec_read_data(byte_data),
 .sd_sec_read_data_valid(byte_valid && read_owner==2),.sd_sec_read_end(sector_end && read_owner==2),.pcm_we(audio_pcm_we),.pcm_word(audio_pcm_word));
always @(posedge clk or posedge rst)begin
 if(rst)begin audio_count<=0;active_audio_track<=0;active_audio_epoch<=0;change_pending<=0;pending_epoch<=0;pending_track<=0;flush_count<=0;end
 else begin
  if(scan_start)audio_count<=0;
  else if(audio_found && audio_count<5)begin audio_sectors[audio_count]<=audio_found_sector;audio_lengths[audio_count]<=audio_found_bytes;audio_count<=audio_count+1'b1;end
  if(flush_count!=0)flush_count<=flush_count-1'b1;
  if(audio_request_valid && (requested_audio_epoch!=active_audio_epoch || requested_audio_track!=active_audio_track))begin
   pending_epoch<=requested_audio_epoch;pending_track<=requested_audio_track<audio_count ? requested_audio_track:3'd0;change_pending<=1;
  end else if(change_pending && read_owner!=2 && !read_settle && !audio_packet_active)begin
   // Finish any old audio sector before flushing; never reset the TF card.
   active_audio_track<=pending_track;active_audio_epoch<=pending_epoch;
   if(pending_track!=active_audio_track)flush_count<=4;
   change_pending<=0;
  end
 end
end
always @(posedge clk or posedge rst)begin
 if(rst)begin read_owner<=0;read_settle<=0;read_address<=0;end
 else if(abort_op)begin read_owner<=0;read_settle<=0;end
 else if(sector_end)begin read_owner<=0;read_settle<=1;end
 else if(read_settle)read_settle<=0;
 else if(read_owner==0)begin
  // Sector-granular arbitration: refill music before the next picture sector.
  if(audio_sd_req && !audio_switching)begin read_owner<=2;read_address<=audio_sd_addr;end
  else if(bmp_read_req)begin read_owner<=1;read_address<=bmp_read_addr;end
  else if(dlt_req)begin read_owner<=3;read_address<=dlt_sector;end
 end
end
sd_card_top #(.SPI_LOW_SPEED_DIV(248),.SPI_HIGH_SPEED_DIV(2),.READ_MULTIBLOCK(1),.FAST_READ_STREAM(1)) sd(
 .clk(clk),.rst(rst || abort_op),.SD_nCS(sd_ncs),.SD_DCLK(sd_dclk),.SD_MOSI(sd_mosi),.SD_MISO(sd_miso),
 .sd_init_done(initialized),.init_stage(),.sd_sec_read(read_owner!=0),.sd_sec_read_addr(read_address),
 .sd_sec_read_data(byte_data),.sd_sec_read_data_valid(byte_valid),.sd_sec_read_end(sector_end),
 .sd_sec_write(1'b0),.sd_sec_write_addr(32'd0),.sd_sec_write_data(8'd0),.sd_sec_write_data_req(),.sd_sec_write_end());
// The FIFO's full input provides backpressure. Four clocks retain pipeline
// headroom without the old sixteen-clock delay between decoded halfwords.
photo_dlt_reader #(.PIXEL_GAP(4)) dlt(.clk(clk),.rst(rst || abort_op),.start(load_launch && directory_dlt[load_image]),
 .start_sector(load_sector),.ready(dlt_ready),.done(dlt_done),.error(dlt_error),
 .write_req(dlt_write_req),.write_ack(write_ack),.full(full),.pixel_valid(dlt_pixel_valid),.pixel(dlt_pixel),
 .req(dlt_req),.sector(dlt_sector),.byte_valid(byte_valid && read_owner==3),.byte_data(byte_data),.block_end(sector_end && read_owner==3));
bmp_read bmp(.clk(clk),.rst(rst),.op_abort(abort_op),.ready(bmp_ready),
 .scan_start(scan_start),.scan_resume(scan_resume),.scan_exhausted(scan_exhausted),
 .scan_stop(scan_stop_q),.scan_start_sector(32'd0),.scan_max_sector(SCAN_MAX_SECTOR),
 .scan_target_count(3'd6),.scan_done(scan_done),.scan_found_valid(found),.scan_found_sector(sector),
 .scan_found_total(),.scan_found_width(width),.scan_found_height(height),.scan_found_sprint(),.scan_found_dlt(found_dlt),
 .audio_found_valid(audio_found),.audio_found_index(),.audio_found_sector(audio_found_sector),.audio_found_bytes(audio_found_bytes),
 .load_start(load_launch && !directory_dlt[load_image]),.load_sector(load_sector),.sd_init_done(initialized),.state_code(bmp_state),
 .bmp_width(16'd1280),.bmp_height(16'd720),.write_req(bmp_write_req),.write_req_ack(write_ack),
 .sd_sec_read(bmp_read_req),.sd_sec_read_addr(bmp_read_addr),.sd_sec_read_data(byte_data),
 .sd_sec_read_data_valid(byte_valid && read_owner==1),.sd_sec_read_end(sector_end && read_owner==1),
 .bmp_data_wr_en(bmp_pixel_valid),.bmp_data(bmp_pixel),.scaler_fault_o(bmp_fault));
always @(posedge clk or posedge rst)begin
 if(rst)load_launch<=0;else load_launch<=load_start && !abort_op;
end
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
  directory_dlt<=0;load_is_dlt<=0;award_available<=0;relief_available<=0;award_decode_error<=0;
  current_image<=0;playback_image<=0;wanted<=0;demand<=0;scanned<=0;scanning<=0;loading<=0;load_started<=0;
  scan_start<=0;scan_resume<=0;scan_complete<=0;scan_yield<=0;load_start<=0;abort_op<=0;load_sector<=0;timer<=0;due_scan<=SCAN_LIMIT==0;due_load<=LOAD_LIMIT==0;init_timer<=0;fin_seen<=0;
 end else begin
  scan_start<=0;scan_resume<=0;load_start<=0;abort_op<=0;
  if(!initialized)begin
   if(init_timer>=CLK_HZ*8)begin abort_op<=1;init_timer<=0;scanning<=0;end
   else init_timer<=init_timer+1'b1;
  end else init_timer<=0;
  if(initialized && !scanned && !scanning && bmp_ready)begin scan_start<=1;scanning<=1;image_count<=0;timer<=0;due_scan<=SCAN_LIMIT==0;due_load<=LOAD_LIMIT==0;end
  if(scanning)begin
   timer<=timer+1'b1;due_scan<=SCAN_LIMIT==0 || (timer!=32'hffffffff && timer>=SCAN_LIMIT-1'b1);due_load<=LOAD_LIMIT==0 || (timer!=32'hffffffff && {32'd0,timer}>=LOAD_LIMIT-1'b1);
   if(audio_found || sector_end)begin timer<=0;due_scan<=SCAN_LIMIT==0;due_load<=LOAD_LIMIT==0;end
   if(found && found_dlt && !width[14] && !award_available)begin
    directory[6]<=sector;directory_width[6]<=16'h8500;directory_height[6]<=720;
    directory_dlt[6]<=1;award_available<=1;timer<=0;due_scan<=SCAN_LIMIT==0;due_load<=LOAD_LIMIT==0;
   end
   if(found && found_dlt && width[14] && !relief_available)begin
    directory[7]<=sector;directory_width[7]<=16'hc500;directory_height[7]<=720;
    directory_dlt[7]<=1;relief_available<=1;timer<=0;due_scan<=SCAN_LIMIT==0;due_load<=LOAD_LIMIT==0;
   end
   if(found && !found_dlt && image_count<6)begin
    directory[image_count]<=sector;directory_width[image_count]<=width;directory_height[image_count]<=height;
    directory_dlt[image_count]<=found_dlt;
    image_count<=image_count+1'b1;timer<=0;due_scan<=SCAN_LIMIT==0;due_load<=LOAD_LIMIT==0;
   end
   if(scan_done && !scan_start && !scan_resume)begin
    scanning<=0;scanned<=1;scan_yield<=0;
    scan_complete<=scan_exhausted || (image_count==6 && audio_count==5 && award_available && relief_available && (!TITLE_SD || title_ready));
    if(image_count==0 && !award_available && !relief_available && !found)error<=1;
   end
   if(scanned && (request || demand || release_slot || found))scan_yield<=1;
   // Watchdog measures absence of SD progress, not absence of new headers.
   // Search the configured sector range even after six photos are found.
   if(due_scan)begin scanning<=0;scanned<=1;scan_complete<=1;abort_op<=1;if(image_count==0 && !award_available && !relief_available)error<=1;end
  end
  if(request && scanned && (target<image_count || (target==6 && award_available) || (target==7 && relief_available)))begin wanted<=target;demand<=1;ready<=0;error<=0;end
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
    // A owns the displayed copy. Once the complete sender slot is locked,
    // its predecessor may be replaced while the link reads the locked slot.
    // Advance the raw prefetch window now instead of waiting for link COMMIT.
    // Settings pin/pause and award transfers retain the original policy.
    if(EARLY_PREFETCH && !pin_active && !prefetch_pause && wanted<image_count)
     playback_image<=wanted;
   end
   else if(!loading && !scanning && bmp_ready && (!DISPLAY_PIN || current_image==(pin_active ? display_image:playback_image)))begin
   if(demand && !hit && victim_ok)begin
    load_slot<=victim;load_image<=wanted;load_start<=1;loading<=1;
    cache_valid[victim]<=0;load_started<=0;fin_seen<=fin_sync;timer<=0;due_scan<=SCAN_LIMIT==0;due_load<=LOAD_LIMIT==0;
   end else if(!demand && pin_active && !pin_hit && victim_ok)begin
    // Restore the actual HDMI image before any speculative SD read.
    load_slot<=victim;load_image<=display_image;load_start<=1;loading<=1;
    cache_valid[victim]<=0;load_started<=0;fin_seen<=fin_sync;timer<=0;due_scan<=SCAN_LIMIT==0;due_load<=LOAD_LIMIT==0;
   end else if(!demand && (!DISPLAY_PIN || !prefetch_pause) && current_image<6 && image_count>1 && !next_hit && victim_ok)begin
    load_slot<=victim;load_image<=next_id(current_image,image_count);
    load_start<=1;loading<=1;
    cache_valid[victim]<=0;load_started<=0;fin_seen<=fin_sync;timer<=0;due_scan<=SCAN_LIMIT==0;due_load<=LOAD_LIMIT==0;
   end else if(!scan_complete && !demand && !ready && current_hit &&
               (prefetch_pause || current_image>=6 || image_count<=1 || next_hit))begin
    // Continue directory discovery while a selection waits for its header.
    // prefetch_pause still blocks speculative photo loading above.
    scan_resume<=1;scanning<=1;scan_yield<=0;timer<=0;due_scan<=SCAN_LIMIT==0;due_load<=LOAD_LIMIT==0;
   end
   end
  end
  if(load_start)load_sector<=directory[load_image];
  if(load_start)award_decode_error<=0;
  else if(loading && load_is_dlt && dlt_error!=0)award_decode_error<=dlt_error;
  if(load_start)begin stat_x<=0;stat_y<=0;stat_sum<=0;stat_count<=0;load_is_dlt<=directory_dlt[load_image];end
  if(loading)begin
   timer<=timer+1'b1;due_scan<=SCAN_LIMIT==0 || (timer!=32'hffffffff && timer>=SCAN_LIMIT-1'b1);due_load<=LOAD_LIMIT==0 || (timer!=32'hffffffff && {32'd0,timer}>=LOAD_LIMIT-1'b1);
   if(write_req)load_started<=1;
   if(scaler_pixel)begin
    if(stat_x[3:0]==0 && stat_y[3:0]==0)begin stat_sum<=stat_sum+raw_luma[9:2];stat_count<=stat_count+1'b1;end
    if(stat_x==1279)begin stat_x<=0;stat_y<=stat_y+1'b1;end else stat_x<=stat_x+1'b1;
   end
   
   if(load_started && load_ready && fin_sync!=fin_seen)begin
    loading<=0;fin_seen<=fin_sync;
    if(words==(load_is_dlt ? (load_image==7 ? 21'd985088:21'd691200):frame_words) && pack_aligned)begin cache_valid[load_slot]<=1;cache_id[load_slot]<=load_image;cache_gain[load_slot]<=loaded_gain;end
    else begin error<=3;abort_op<=1;end
   end
   if((write_en && full) || scaler_fault || due_load)begin
    error<=write_en && full ? 4'd4:load_is_dlt && dlt_error!=0 ? 4'd8:4'd2;loading<=0;abort_op<=1;
   end
  end
 end
end
endmodule

// Specialized ring: 2048 frames in RAM32K, 2304 in spare RAM9K.
// Two large macros are released as well as the unreachable upper capacity. The generic FIFO and every A-board/transport queue stay unchanged.
module photo_audio_fifo_compact(input clk,rst,write_en,input[31:0] write_data,
 input read_en,output[31:0] data,output empty,full,output reg[13:0] used);
reg[12:0] wp,rp;reg[1:0] read_bank;
wire push=write_en && !full,pop=read_en && !empty;
wire[31:0] head_q,middle_q,tail_q;
assign empty=used==0;assign full=used==14'd4352;
photo_audio_word_ram #(.ADDR(11),.IMPLEMENT("32K")) head(
 .clk(clk),.we(push && wp[12:11]==0),.wa(wp[10:0]),.wd(write_data),
 .re(pop && rp[12:11]==0),.ra(rp[10:0]),.rd(head_q));
photo_audio_word_ram #(.ADDR(11),.IMPLEMENT("9K")) middle(
 .clk(clk),.we(push && wp[12:11]==1),.wa(wp[10:0]),.wd(write_data),
 .re(pop && rp[12:11]==1),.ra(rp[10:0]),.rd(middle_q));
photo_audio_word_ram #(.ADDR(8),.IMPLEMENT("9K")) tail(
 .clk(clk),.we(push && wp[12]),.wa(wp[7:0]),.wd(write_data),
 .re(pop && rp[12]),.ra(rp[7:0]),.rd(tail_q));
assign data=read_bank==0 ? head_q:read_bank==1 ? middle_q:tail_q;
always @(posedge clk or posedge rst)begin
 if(rst)begin wp<=0;rp<=0;used<=0;read_bank<=0;end
 else begin
  if(push)wp<=wp==13'd4351 ? 13'd0:wp+1'b1;
  if(pop)begin rp<=rp==13'd4351 ? 13'd0:rp+1'b1;read_bank<=rp[12:11];end
  case({push,pop})2'b10:used<=used+1'b1;2'b01:used<=used-1'b1;default:;endcase
 end
end
// synthesis translate_off
always @(posedge clk)if(!rst)begin
 if(write_en && full)$fatal(1,"compact raw PCM overflow");
 if(wp>=4352 || rp>=4352)$fatal(1,"compact raw PCM pointer out of range");
end
// synthesis translate_on
endmodule
