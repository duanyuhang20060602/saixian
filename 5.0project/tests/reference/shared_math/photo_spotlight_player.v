// Exact accepted spotlight interpolation, fed by a lossless sparse row cache.
module photo_spotlight_player_before #(parameter SHARED_CACHE=0,FRAMES=120,PERIOD=6,PLAYBACK_SPEED=2,INITIAL_HOLD_FRAMES=0)(
 input mem_clk,mem_rst,enable,input [20:0] base,
 output reg stream_start,output reg [20:0] stream_offset,input stream_ack,
 input [31:0] data,input data_valid,output reg [3:0] error,
 input video_clk,video_rst,display_valid,pause,
 input [23:0] rgb_in,input de_in,vs_in,
 output reg [23:0] rgb_out,output reg de_out,vs_out,
 output reg [6:0] frame_index,output reg initialized,
 output cache_write_en,output [8:0] cache_write_address,output [31:0] cache_write_data,
 output [8:0] cache_read_address,input [31:0] cache_read_data
);

localparam DISPLAY_PERIOD=PERIOD/PLAYBACK_SPEED;
reg [31:0] row_bank[0:511]; /* fehdl force_ram=1, ram_style="bram" */
reg request_toggle,done_toggle;
reg [6:0] request_frame,request_row;reg request_initial;
(* async_reg="true" *)reg [2:0] request_sync,done_sync;
(* async_reg="true" *)reg [6:0] request_frame_meta,request_row_meta;
reg [6:0] request_frame_sync,request_row_sync;
(* async_reg="true" *)reg request_initial_meta;
reg request_initial_sync,request_seen,done_seen;
(* async_reg="true" *)reg [2:0] startup_sync,video_error_sync;
reg request_pending,job_initial;reg next_ready,video_error;
wire current_bank=1'b0;reg [4:0] step;reg [6:0] initial_hold;
reg vs_previous,de_previous;reg [10:0] pixel_x;reg [9:0] pixel_y;
(* async_reg="true" *)reg pause_meta,pause_sync;
reg [3:0] row_valid;reg [6:0] row_tag[0:3];reg [6:0] last_requested_upper;
reg [6:0] line_upper,line_lower;reg line_upper_good,line_lower_good;
(* async_reg="true" *)reg enable_meta,enable_mem;
always @(posedge mem_clk or posedge mem_rst)
 if(mem_rst)begin enable_meta<=0;enable_mem<=0;end
 else begin enable_meta<=enable;enable_mem<=enable_meta;end
wire startup_done=enable_mem && error==0;
localparam IDLE=0,TABLE_REQUEST=1,TABLE_READ=2,ROW_REQUEST=3,ROW_READ=4,EMIT=5,NEXT_ROW=6,REFILL=7,TABLE_CHECK=8;
reg [3:0] state;reg [6:0] load_frame,load_row,last_row;
reg load_bank;reg [1:0] lane;reg [20:0] table_word,payload;
reg table_good;
reg [31:0] buffer[0:3];reg [2:0] buffered,index;
reg [39:0] bitmap;reg [5:0] column;reg [1:0] header_words;
wire [6:0] field=load_bank ? (load_frame==FRAMES-1 ? 7'd0:load_frame+1'b1):load_frame;
wire [20:0] table_index=field*68+load_row;
always @(posedge mem_clk)begin
 table_good<=table_word>=8160 && table_word<=230356 && table_word[1:0]==0;
 request_sync<={request_sync[1:0],request_toggle};
 request_frame_meta<=request_frame;request_frame_sync<=request_frame_meta;
 request_row_meta<=request_row;request_row_sync<=request_row_meta;
 request_initial_meta<=request_initial;request_initial_sync<=request_initial_meta;
 video_error_sync<={video_error_sync[1:0],video_error};
 if(mem_rst || !enable_mem)begin
  state<=IDLE;error<=0;done_toggle<=0;request_seen<=0;request_sync<=0;
  request_frame_meta<=0;request_frame_sync<=0;request_row_meta<=0;request_row_sync<=0;
  request_initial_meta<=0;request_initial_sync<=0;video_error_sync<=0;
  stream_start<=0;stream_offset<=0;load_frame<=0;load_row<=0;last_row<=0;load_bank<=0;
  lane<=0;table_word<=0;payload<=0;buffered<=0;index<=0;bitmap<=0;column<=0;header_words<=0;
 end else if(video_error_sync[2])error<=7;
 else if(error==0)case(state)
  IDLE:if(request_sync[2]!=request_seen)begin
   request_seen<=request_sync[2];load_frame<=request_frame_sync;load_row<=request_row_sync;
   last_row<=request_initial_sync ? 7'd2:request_row_sync;load_bank<=0;state<=TABLE_REQUEST;
  end
  TABLE_REQUEST:begin
   stream_start<=1;stream_offset<=base+{table_index[20:2],2'b00};lane<=0;
   if(stream_ack)begin stream_start<=0;state<=TABLE_READ;end
  end
  TABLE_READ:if(data_valid)begin
   if(lane==table_index[1:0])table_word<=data;
   lane<=lane+1'b1;if(lane==3)state<=TABLE_CHECK;
  end
  TABLE_CHECK:state<=ROW_REQUEST;
  ROW_REQUEST:begin
   if(!table_good)error<=2;
   else begin
    stream_start<=1;stream_offset<=base+table_word;buffered<=0;index<=0;header_words<=0;column<=0;bitmap<=0;payload<=table_word+4;
    if(stream_ack)begin stream_start<=0;state<=ROW_READ;end
   end
  end
  ROW_READ:if(data_valid)begin
   buffer[buffered[1:0]]<=data;buffered<=buffered+1'b1;
   if(buffered==3)begin index<=0;state<=EMIT;end
  end
  EMIT:begin
   if(header_words<2)begin
    if(header_words==0)bitmap[31:0]<=buffer[index[1:0]];
    else begin bitmap[39:32]<=buffer[index[1:0]][7:0];if(buffer[index[1:0]][31:8]!=0)error<=3;end
    header_words<=header_words+1'b1;index<=index+1'b1;
   end else if(!bitmap[0] || index<4)begin
    // The row write port is shared with the relief palette in the renderer.
    if(bitmap[0])index<=index+1'b1;
    bitmap<={1'b0,bitmap[39:1]};column<=column+1'b1;if(column==39)state<=NEXT_ROW;
   end else begin state<=REFILL;stream_offset<=base+payload;end
  end
  REFILL:begin
   stream_start<=1;buffered<=0;
   if(stream_ack)begin stream_start<=0;state<=ROW_READ;payload<=payload+4;end
  end
  NEXT_ROW:begin
   if(!load_bank)begin load_bank<=1;state<=TABLE_REQUEST;end
   else if(load_row!=last_row)begin load_row<=load_row+1'b1;load_bank<=0;state<=TABLE_REQUEST;end
   else begin done_toggle<=~done_toggle;state<=IDLE;end
  end
  default:error<=4;
 endcase
end
// Identical write predicate to the original EMIT branch, before state updates.
assign cache_write_en=!mem_rst && enable_mem && !video_error_sync[2] && error==0 &&
 state==EMIT && header_words>=2 && (!bitmap[0] || index<4);
assign cache_write_address={load_row[1:0],load_bank,column};
assign cache_write_data=bitmap[0] ? buffer[index[1:0]]:32'd0;
always @(posedge mem_clk)
 if(!SHARED_CACHE && cache_write_en)row_bank[cache_write_address]<=cache_write_data;
wire frame_tick=vs_in && !vs_previous;
wire advance=initialized && next_ready && display_valid && !pause_sync && initial_hold>=INITIAL_HOLD_FRAMES;
wire field_advance=advance && step==DISPLAY_PERIOD-1;
wire [6:0] scheduled_frame=field_advance ? (frame_index==FRAMES-1 ? 7'd0 : frame_index+1'b1) : frame_index;
wire [9:0] line_shift=pixel_y>=4 ? pixel_y-10'd4:10'd0;
wire [6:0] next_line_upper=line_shift[9:3]>89 ? 7'd89:line_shift[9:3];
wire [6:0] next_line_lower=next_line_upper==89 ? next_line_upper:next_line_upper+1'b1;
// Horizontal blanking provides 370 clocks. Resolve source-row geometry
// there, then register row ownership before the first active pixel.
always @(posedge video_clk)begin
 if(video_rst)begin line_upper<=0;line_lower<=0;line_upper_good<=0;line_lower_good<=0;end
 else begin
  if(!de_in)begin line_upper<=next_line_upper;line_lower<=next_line_lower;end
  line_upper_good<=line_upper>=68 || (row_valid[line_upper[1:0]] && row_tag[line_upper[1:0]]==line_upper);
  line_lower_good<=line_lower>=68 || (row_valid[line_lower[1:0]] && row_tag[line_lower[1:0]]==line_lower);
 end
end
integer r;
always @(posedge video_clk)begin
 if(video_rst)begin
  done_sync<=0;done_seen<=0;startup_sync<=0;initialized<=0;next_ready<=0;video_error<=0;
  frame_index<=0;step<=0;initial_hold<=0;request_toggle<=0;request_frame<=0;request_row<=0;request_initial<=0;
  request_pending<=0;job_initial<=0;row_valid<=0;last_requested_upper<=0;
  for(r=0;r<4;r=r+1)row_tag[r]<=0;
  vs_previous<=0;pause_meta<=0;pause_sync<=0;pixel_x<=0;pixel_y<=0;de_previous<=0;
 end else begin
  done_sync<={done_sync[1:0],done_toggle};startup_sync<={startup_sync[1:0],startup_done};
  pause_meta<=pause;pause_sync<=pause_meta;
  vs_previous<=vs_in;de_previous<=de_in;
  if(vs_in)pixel_y<=0;else if(de_previous && !de_in)pixel_y<=pixel_y+1'b1;
  if(de_in)pixel_x<=pixel_x+1'b1;else pixel_x<=0;
  if(done_sync[2]!=done_seen)begin
   done_seen<=done_sync[2];request_pending<=0;
   if(job_initial)begin
    next_ready<=1;row_valid<=4'b0111;row_tag[0]<=0;row_tag[1]<=1;row_tag[2]<=2;
   end else begin row_valid[request_row[1:0]]<=1;row_tag[request_row[1:0]]<=request_row;end
  end
  if(frame_tick)begin
   initialized<=startup_sync[2];
   if(display_valid && !pause_sync && initial_hold<INITIAL_HOLD_FRAMES)initial_hold<=initial_hold+1'b1;
   if(advance)begin
    if(field_advance)begin step<=0;frame_index<=scheduled_frame;end
    else step<=step+1'b1;
   end
   if(startup_sync[2] && display_valid && !video_error)begin
    if(request_pending)video_error<=1;
    else begin
     request_frame<=scheduled_frame;request_row<=0;request_initial<=1;job_initial<=1;
     request_toggle<=~request_toggle;request_pending<=1;next_ready<=0;row_valid<=0;last_requested_upper<=0;
    end
   end
  end else if(!de_in && initialized && next_ready && !video_error && line_upper!=last_requested_upper)begin
   last_requested_upper<=line_upper;
   if(line_upper+2<68)begin
    if(request_pending)video_error<=1;
    else begin
     request_frame<=frame_index;request_row<=line_upper+7'd2;request_initial<=0;job_initial<=0;
     request_toggle<=~request_toggle;request_pending<=1;row_valid[(line_upper[1:0]+2'd2)]<=0;
    end
   end
  end
  // HDMI cannot stall. Missing rows are a diagnosed failure, never silently
  // mixed with stale data. Row prefetch normally has eight scanlines' lead.
  if(de_in && !de_previous && initialized && display_valid)begin
   if(!next_ready || !line_upper_good || !line_lower_good)video_error<=1;
  end
 end
end
// Precompute each source-grid point's vertical interpolation once per eight
// pixels. Across a grid cell the exact unrounded bilinear numerator changes
// by a constant signed difference; no intermediate rounding is introduced.
// These are the same x-4 grid cells as the reference, advanced from the
// three raster phase bits. Avoid a wide subtract/clamp/compare feedback path.
reg [7:0] grid_point;reg grid_started,grid_boundary,head_hold;
always @(posedge video_clk)begin
 if(video_rst || !de_in)begin grid_point<=0;grid_started<=0;grid_boundary<=0;head_hold<=1;end
 else begin
  grid_boundary<=0;
  if(pixel_x[2:0]==4)head_hold<=0;
  if(pixel_x[2:0]==3)begin
   grid_started<=1;
   if(grid_started && grid_point!=159)begin grid_point<=grid_point+1'b1;grid_boundary<=1;end
  end
 end
end
wire [2:0] line_fy=pixel_y>=4 ? line_shift[2:0]:3'd0;
reg [3:0] blank_index;
reg fetch_active,read_valid_d,read_zero;reg [1:0] fetch_phase,read_lane,read_point;
reg [7:0] fetch_point;reg [31:0] internal_read0;
wire [31:0] read0=SHARED_CACHE ? cache_read_data:internal_read0;
wire [1:0] fetch_lane=de_in ? fetch_phase:blank_index[1:0];
wire [7:0] fetch_x=de_in ? fetch_point:{6'd0,blank_index[3:2]};
wire [6:0] fetch_y=fetch_lane[1] ? line_lower:line_upper;
wire [8:0] row_address={fetch_y[1:0],fetch_lane[0],fetch_x[7:2]};
assign cache_read_address=row_address;
wire source_valid=!de_in || fetch_active;
wire [7:0] source_byte=read_zero ? 8'd0:(read0>>{read_point,3'b000});
reg [7:0] top_a,top_b;
wire [7:0] top_selected=read_lane[0] ? top_b:top_a;
wire signed [8:0] vertical_difference=$signed({1'b0,source_byte})-$signed({1'b0,top_selected});
// The fraction is only three bits: keep the product local to the row cache.
// Explicit signed shift/add avoids a RAM -> distant DSP -> register route.
wire signed [12:0] vertical_term0=line_fy[0] ? {{4{vertical_difference[8]}},vertical_difference}:13'sd0;
wire signed [12:0] vertical_term1=line_fy[1] ? {{3{vertical_difference[8]}},vertical_difference,1'b0}:13'sd0;
wire signed [12:0] vertical_term2=line_fy[2] ? {{2{vertical_difference[8]}},vertical_difference,2'b0}:13'sd0;
reg signed [12:0] vertical_product;
reg [10:0] vertical_base,point_a;
reg vertical_valid,vertical_field;reg [1:0] vertical_slot;
wire signed [13:0] vertical_sum=$signed({3'd0,vertical_base})+vertical_product;
wire [21:0] point_data;
reg [1:0] point_read;
// Look ahead by one cell. Only the grid boundary consumes this point; the
// register provides a full clock before the distributed-RAM/subtract path.
always @(posedge video_clk)begin
 if(video_rst)point_read<=0;
 else point_read<=de_in ? (grid_point>=158 ? 2'd3:grid_point[1:0]+2'd2):{1'b0,~blank_index[0]};
end
photo_award_tile_cache tiles(.clk(video_clk),.we(vertical_valid && vertical_field && !video_rst),
 .wa(vertical_slot),.wd({vertical_sum[10:0],point_a}),.address(point_read),.data(point_data));
always @(posedge video_clk)begin
 if(!SHARED_CACHE)internal_read0<=row_bank[row_address];
 read_zero<=fetch_y>=68;
 if(video_rst)begin
  blank_index<=0;fetch_active<=0;read_valid_d<=0;read_lane<=0;read_point<=0;
  fetch_phase<=0;fetch_point<=0;top_a<=0;top_b<=0;
  vertical_product<=0;vertical_base<=0;vertical_valid<=0;vertical_field<=0;vertical_slot<=0;point_a<=0;
 end else begin
  read_valid_d<=source_valid;read_lane<=fetch_lane;read_point<=fetch_x[1:0];
  vertical_valid<=read_valid_d && read_lane[1];
  vertical_field<=read_lane[0];vertical_slot<=read_point;
  vertical_product<=vertical_term0+vertical_term1+vertical_term2;
  vertical_base<={top_selected,3'b000};
  if(read_valid_d && !read_lane[1])begin
   if(read_lane[0])top_b<=source_byte;else top_a<=source_byte;
  end
  if(vertical_valid && !vertical_field)point_a<=vertical_sum[10:0];
  if(!de_in)begin
   blank_index<=blank_index+1'b1;fetch_active<=0;
  end else begin
   blank_index<=0;
   if(grid_boundary)begin
    fetch_point<=grid_point>=156 ? 8'd159:grid_point+8'd3;
    fetch_phase<=0;fetch_active<=1;
   end else if(fetch_active)begin
    if(fetch_phase==3)fetch_active<=0;else fetch_phase<=fetch_phase+1'b1;
   end
  end
 end
end
reg [21:0] first_point,right_point;
reg signed [11:0] difference_a,difference_b;
reg [13:0] accumulator_a,accumulator_b;
wire new_cell=grid_boundary;
wire [13:0] numerator_a=head_hold ? {first_point[10:0],3'b000}:
 new_cell ? {right_point[10:0],3'b000}:accumulator_a+{{2{difference_a[11]}},difference_a};
wire [13:0] numerator_b=head_hold ? {first_point[21:11],3'b000}:
 new_cell ? {right_point[21:11],3'b000}:accumulator_b+{{2{difference_b[11]}},difference_b};
always @(posedge video_clk)begin
 if(video_rst)begin first_point<=0;right_point<=0;difference_a<=0;difference_b<=0;accumulator_a<=0;accumulator_b<=0;end
 else if(!de_in)begin
  accumulator_a<=0;accumulator_b<=0;
  if(!blank_index[0])first_point<=point_data;
  else begin
   right_point<=point_data;
   difference_a<=$signed({1'b0,point_data[10:0]})-$signed({1'b0,first_point[10:0]});
   difference_b<=$signed({1'b0,point_data[21:11]})-$signed({1'b0,first_point[21:11]});
  end
 end else begin
  accumulator_a<=numerator_a;accumulator_b<=numerator_b;
  if(new_cell)begin
   right_point<=point_data;
   difference_a<=$signed({1'b0,point_data[10:0]})-$signed({1'b0,right_point[10:0]});
   difference_b<=$signed({1'b0,point_data[21:11]})-$signed({1'b0,right_point[21:11]});
  end
 end
end
reg [7:0] phase_address;reg coord_valid,coord_de,coord_vs;reg [23:0] coord_rgb;
reg [13:0] numerator0a,numerator0b;
reg [7:0] spatial1a,spatial1b,spatial2a,spatial2b;
reg [7:0] phase0,phase1,phase2,field4;
reg [7:0] a2_field,b2_field;reg [15:0] product3a,product3b;
reg [4:0] valid_pipe,de_pipe,vs_pipe;
reg [23:0] rgb_pipe[0:4];reg [7:0] quant_coord,quant_pipe[0:4];integer pipeline_i;
wire [7:0] quant={pixel_x[0]^pixel_y[0],pixel_y[0],pixel_x[1]^pixel_y[1],pixel_y[1],4'd8};
function [7:0] screen;
 input [7:0] channel,target,light;reg [15:0] product;
 begin product=(target>channel ? target-channel : 8'd0)*light;screen=channel+product[15:8];end
endfunction
always @(posedge video_clk)begin
 if(video_rst)begin
  phase_address<=0;coord_valid<=0;coord_de<=0;coord_vs<=0;coord_rgb<=0;
  numerator0a<=0;numerator0b<=0;spatial1a<=0;spatial1b<=0;spatial2a<=0;spatial2b<=0;
  phase0<=0;phase1<=0;phase2<=0;field4<=0;
  a2_field<=0;b2_field<=0;product3a<=0;product3b<=0;
  valid_pipe<=0;de_pipe<=0;vs_pipe<=0;rgb_out<=0;de_out<=0;vs_out<=0;
  for(pipeline_i=0;pipeline_i<5;pipeline_i=pipeline_i+1)begin rgb_pipe[pipeline_i]<=0;quant_pipe[pipeline_i]<=0;end
  quant_coord<=0;
 end else begin
  numerator0a<=numerator_a;numerator0b<=numerator_b;
  phase_address<=next_ready ? ((step*256+DISPLAY_PERIOD/2)/DISPLAY_PERIOD) : 8'd0;
  quant_coord<=quant;
  coord_valid<=initialized && next_ready && !video_error && display_valid && de_in && pixel_y<548;coord_de<=de_in;coord_vs<=vs_in;coord_rgb<=rgb_in;
  spatial1a<=(numerator0a+quant_coord[7:2])>>6;
  spatial1b<=(numerator0b+quant_coord[7:2])>>6;
  spatial2a<=spatial1a;spatial2b<=spatial1b;
  a2_field<=spatial2a;b2_field<=spatial2b;
  phase0<=phase_address;phase1<=phase0;phase2<=phase1;
  product3a<=valid_pipe[2] ? a2_field*(9'd256-{1'b0,phase2}) : 16'd0;
  product3b<=valid_pipe[2] && phase2!=0 ? b2_field*phase2 : 16'd0;
  field4<=(product3a+product3b+quant_pipe[3])>>8;
  valid_pipe<={valid_pipe[3:0],coord_valid};
  de_pipe<={de_pipe[3:0],coord_de};vs_pipe<={vs_pipe[3:0],coord_vs};
  rgb_pipe[0]<=coord_rgb;quant_pipe[0]<=quant_coord;
  for(pipeline_i=1;pipeline_i<5;pipeline_i=pipeline_i+1)begin rgb_pipe[pipeline_i]<=rgb_pipe[pipeline_i-1];quant_pipe[pipeline_i]<=quant_pipe[pipeline_i-1];end
  rgb_out<={screen(rgb_pipe[4][23:16],8'd255,field4),screen(rgb_pipe[4][15:8],8'd235,field4),screen(rgb_pipe[4][7:0],8'd200,field4)};
  de_out<=de_pipe[4];vs_out<=vs_pipe[4];
 end
end
endmodule
