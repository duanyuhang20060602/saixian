// Input follows frame_pixels (two clocks from the raster). The original
// award effect takes five clocks; nineteen more align with HDMI's 26 clocks.
module photo_award_render_before #(parameter RELIEF_ENABLE=0,SHARED_ENABLE=1,REMOTE_RELIEF=0)(
 input relief_mode,touch_contact,input [10:0] cursor_x,input [9:0] cursor_y,
 input mem_clk,mem_rst,input [20:0] light_base,
 output light_wide,output light_request,output [20:0] light_address,input light_ack,input [31:0] light_data,input light_valid,
 input de_in,input clk,rst,enable,pause,frame_tick,
 input [10:0] x,input [9:0] y,input [23:0] tagged_rgb,
 output [23:0] rgb,output [23:0] menu_rgb,
 output [3:0] light_error,output [6:0] light_frame,
 output [31:0] relief_descriptor,input relief_sent,input [31:0] relief_sent_descriptor,
 output relief_available,input relief_begin,relief_word_valid,relief_finish,relief_commit,
 input [8:0] relief_word_index,input [31:0] relief_word,
 output wall_we,output [7:0] wall_wa,wall_ra,output [23:0] wall_wd,input [23:0] wall_rgb
);
wire relief=RELIEF_ENABLE && relief_mode;
// Mode originates in the pixel clock. SDRAM routing and response enables
// must use its memory-clock copy, just like each player's enable input.
(* async_reg="true" *)reg relief_meta,relief_mem;
reg route_d,burst_relief;
always @(posedge mem_clk or posedge mem_rst)
 if(mem_rst)begin relief_meta<=0;relief_mem<=0;route_d<=0;burst_relief<=0;end
 else begin
  relief_meta<=relief;relief_mem<=relief_meta;route_d<=relief_mem;
  // The arbiter registers ACK. Retain that grant's owner until all four
  // response words return, even if the visible mode changes meanwhile.
  if(light_ack)burst_relief<=route_d;
 end
wire old_request;wire [20:0] old_address;wire [3:0] old_error;wire [6:0] old_frame;
wire new_request,new_wide;wire [20:0] new_address;wire [3:0] new_error;wire [4:0] new_frame;wire [23:0] new_rgb;
assign light_wide=relief_mem && new_wide;
assign light_request=relief_mem ? new_request:old_request;
assign light_address=relief_mem ? new_address:old_address;
assign light_error=relief ? new_error:old_error;
assign light_frame=relief ? {2'd0,new_frame}:old_frame;
// The two award modes are mutually exclusive. Reuse the old 512x32 row
// cache for the new 256x32 material palette, with the same synchronous read.
wire remote_valid,remote_bank,remote_palette_we;wire [8:0] remote_palette_wa;wire [31:0] remote_palette_wd;
wire [4:0] desired_angle,remote_angle;wire signed [5:0] desired_light_x,desired_light_y,remote_light_x,remote_light_y;
wire [6:0] wall_address;
assign wall_ra={remote_bank,wall_address};
generate if(REMOTE_RELIEF)begin:remote_tables
 photo_relief_tables_compact_a control(.clk(clk),.rst(rst),.enable(enable && relief),.frame_tick(frame_tick),
  .desired_angle(desired_angle),.desired_light_x(desired_light_x),.desired_light_y(desired_light_y),
  .request_descriptor(relief_descriptor),.request_sent(relief_sent),.sent_descriptor(relief_sent_descriptor),
  .available(relief_available),.begin_packet(relief_begin),.word_valid(relief_word_valid),.finish_packet(relief_finish),.commit_packet(relief_commit),
  .word_index(relief_word_index),.word_data(relief_word),.active_valid(remote_valid),.active_bank(remote_bank),
  .display_angle(remote_angle),.display_light_x(remote_light_x),.display_light_y(remote_light_y),
  .wall_we(wall_we),.wall_wa(wall_wa),.wall_wd(wall_wd),
  .mem_clk(mem_clk),.mem_rst(mem_rst),.mem_enable(relief_mem),
  .palette_we(remote_palette_we),.palette_wa(remote_palette_wa),.palette_wd(remote_palette_wd),.rejected());
end else begin
 assign relief_descriptor=0;assign relief_available=0;assign wall_we=0;assign wall_wa=0;assign wall_wd=0;
 assign remote_valid=0;assign remote_bank=0;assign remote_angle=0;assign remote_light_x=0;assign remote_light_y=0;
 assign remote_palette_we=0;assign remote_palette_wa=0;assign remote_palette_wd=0;
end endgenerate
wire old_cache_we,new_cache_we;wire [8:0] old_cache_wa,old_cache_ra;
wire [7:0] new_cache_wa,new_cache_ra;wire [31:0] old_cache_wd,new_cache_wd,shared_cache_data;
generate if(RELIEF_ENABLE && SHARED_ENABLE)begin:shared_award_cache
 photo_relief_ram #(.ADDRESS_BITS(9),.DEPTH(512)) memory(
 .wc(mem_clk),.we(relief_mem ? (REMOTE_RELIEF ? remote_palette_we:new_cache_we):old_cache_we),
 .wa(relief_mem ? (REMOTE_RELIEF ? remote_palette_wa:{1'b0,new_cache_wa}):old_cache_wa),.wd(relief_mem ? (REMOTE_RELIEF ? remote_palette_wd:new_cache_wd):old_cache_wd),
 .rc(clk),.ra(relief ? {REMOTE_RELIEF && remote_bank,new_cache_ra}:old_cache_ra),.rd(shared_cache_data));
end else begin
 assign shared_cache_data=0;
end endgenerate
generate if(RELIEF_ENABLE)begin:gold
 photo_relief_player_before #(.REMOTE_RELIEF(REMOTE_RELIEF),.SHARED_PALETTE(SHARED_ENABLE)) player(
 .remote_valid(remote_valid),.remote_angle(remote_angle),.remote_light_x(remote_light_x),.remote_light_y(remote_light_y),
 .desired_angle(desired_angle),.desired_light_x(desired_light_x),.desired_light_y(desired_light_y),.wall_address(wall_address),.wall_rgb(wall_rgb),.mem_clk(mem_clk),.mem_rst(mem_rst),.enable(enable && relief),.base(light_base),
 .wide_request(new_wide),.request(new_request),.address(new_address),.ack(light_ack && route_d),.data(light_data),.valid(light_valid && burst_relief),
 .clk(clk),.rst(rst),.pause(pause),.frame_tick(frame_tick),.de(de_in),.x(x),.y(y),.rgb_in(tagged_rgb),
 .touch_contact(touch_contact),.cursor_x(cursor_x),.cursor_y(cursor_y),.rgb_out(new_rgb),.error(new_error),.angle(new_frame),
 .cache_write_en(new_cache_we),.cache_write_address(new_cache_wa),.cache_write_data(new_cache_wd),
 .cache_read_address(new_cache_ra),.cache_read_data(shared_cache_data));
end else begin
 assign new_cache_we=0;assign new_cache_wa=0;assign new_cache_wd=0;assign new_cache_ra=0;
 assign new_wide=0;assign new_request=0;assign new_address=0;assign new_error=0;assign new_frame=0;assign new_rgb=0;
end endgenerate
wire [15:0] pixel={tagged_rgb[23:19],tagged_rgb[15:10],tagged_rgb[7:3]};
wire [4:0] blue=pixel[0] ? {1'b0,pixel[10:7]} : {pixel[4:1],1'b0};
wire [5:0] green=pixel[0] ? {pixel[10:6],1'b0} : pixel[10:5];
wire [23:0] base={pixel[15:11],pixel[15:13],green,green[5:4],blue,blue[4:2]};
wire [23:0] effect_rgb;
award_fx_before #(.INITIAL_HOLD_FRAMES(0)) effect(.clk(clk),.rst(rst),.enable(enable && !relief),.pause(pause),.frame_tick(frame_tick),
 .x(x),.y(y),.base_rgb(base),.tag(pixel[5:0]),.rgb(effect_rgb));
wire [23:0] light_rgb;
reg [4:0] light_de,light_vs;
always @(posedge clk)if(rst)begin light_de<=0;light_vs<=0;end
 else begin light_de<={light_de[3:0],de_in};light_vs<={light_vs[3:0],frame_tick};end
photo_spotlight_player_before #(.SHARED_CACHE(RELIEF_ENABLE && SHARED_ENABLE)) lights(.mem_clk(mem_clk),.mem_rst(mem_rst),.enable(enable && !relief),.base(light_base),
 .stream_start(old_request),.stream_offset(old_address),.stream_ack(light_ack && !route_d),.data(light_data),.data_valid(light_valid && !burst_relief),.error(old_error),
 .video_clk(clk),.video_rst(rst || !enable || relief),.display_valid(enable),.pause(pause),
 .rgb_in(effect_rgb),.de_in(light_de[4]),.vs_in(light_vs[4]),.rgb_out(light_rgb),.de_out(),.vs_out(),.frame_index(old_frame),.initialized(),
 .cache_write_en(old_cache_we),.cache_write_address(old_cache_wa),.cache_write_data(old_cache_wd),
 .cache_read_address(old_cache_ra),.cache_read_data(shared_cache_data));
generate if(REMOTE_RELIEF)begin:compact_delay
 photo_award_delay_lut video_delay(.clk(clk),.rst(rst),.rgb_in(relief ? new_rgb:light_rgb),.rgb(rgb),.menu_rgb(menu_rgb));
end else begin:legacy_delay
 photo_award_delay video_delay(.clk(clk),.rst(rst),.rgb_in(relief ? new_rgb:light_rgb),.rgb(rgb),.menu_rgb(menu_rgb));
end endgenerate
endmodule
