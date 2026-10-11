// External-SDRAM light fields, four rolling source rows per temporal field.
// Full asset CRC/descriptor validation precedes publication. No frame RAM.
module spotlight_player #(parameter FRAMES=120, MAP_WORDS=3600, PERIOD=6, PLAYBACK_SPEED=2, INITIAL_HOLD_FRAMES=61)(
 input mem_clk,mem_rst,enable,input [20:0] file_words,
 output stream_start,output [20:0] stream_offset,stream_words,input stream_ack,
 input [31:0] data,input data_valid,output pop,output reg [3:0] error,
 input video_clk,video_rst,display_valid,pause,
 input [23:0] rgb_in,input de_in,vs_in,
 output reg [23:0] rgb_out,output reg de_out,vs_out,
 output reg [6:0] frame_index,output reg initialized
);
localparam WAIT=0,REQUEST=1,READ=2,GAP=3,COMPLETE=4,IDLE=5;
localparam HEADER=0,DESC=1,VERIFY=2,ROW=3;
localparam ACTIVE_WORDS=68*40,MAP_STRIDE=((MAP_WORDS+127)/128)*128;
localparam DISPLAY_PERIOD=PERIOD/PLAYBACK_SPEED;
reg [2:0] state;reg [1:0] kind;
reg [20:0] table_base,map_offset,first_map;
reg [12:0] word_index;
reg [6:0] load_frame,load_row,job_last_row;
reg load_bank,startup_done;
reg [31:0] expected_crc,crc;
// Two simple dual-clock RAMs: {row modulo four, word within row}.
// 40 words/row, four rows. Unused 24 slots/row enable cheap addressing.
reg [31:0] row_bank0[0:255],row_bank1[0:255];
reg request_toggle,done_toggle;
reg [6:0] request_frame,request_row;reg request_initial;
(* async_reg="true" *) reg [2:0] request_sync,done_sync;
(* async_reg="true" *) reg [6:0] request_frame_meta,request_row_meta;
reg [6:0] request_frame_sync,request_row_sync;
(* async_reg="true" *) reg request_initial_meta;
reg request_initial_sync,request_seen,done_seen;
(* async_reg="true" *) reg [2:0] startup_sync,video_error_sync;
reg request_pending,job_initial;
reg next_ready,video_error;
wire current_bank=1'b0;
reg [4:0] step;reg [6:0] initial_hold;
reg vs_previous,de_previous;reg [10:0] pixel_x;reg [9:0] pixel_y;
(* async_reg="true" *) reg pause_meta,pause_sync;
reg [3:0] row_valid;reg [6:0] row_tag[0:3];
reg [6:0] last_requested_upper;
function [31:0] crc_word;
 input [31:0] old,word;reg [31:0] c;integer i;
 begin c=old^word;for(i=0;i<32;i=i+1)c=c[0] ? (c>>1)^32'hEDB88320 : c>>1;crc_word=c;end
endfunction
wire [6:0] following_frame=load_frame==FRAMES-1 ? 7'd0 : load_frame+1'b1;
wire [20:0] row_map=first_map+(load_bank ? following_frame : load_frame)*MAP_STRIDE;
assign stream_start=enable && error==0 && state==REQUEST;
assign stream_offset=kind==HEADER ? 21'd64 : kind==DESC ? table_base+{12'd0,load_frame,2'b0} :
 kind==VERIFY ? map_offset : row_map+load_row*40;
assign stream_words=kind==HEADER ? 21'd5 : kind==DESC ? 21'd4 : kind==VERIFY ? MAP_WORDS : 21'd40;
assign pop=enable && error==0 && state==READ && data_valid;
always @(posedge mem_clk)begin
 request_sync<={request_sync[1:0],request_toggle};
 request_frame_meta<=request_frame;request_frame_sync<=request_frame_meta;
 request_row_meta<=request_row;request_row_sync<=request_row_meta;
 request_initial_meta<=request_initial;request_initial_sync<=request_initial_meta;
 video_error_sync<={video_error_sync[1:0],video_error};
 if(mem_rst || !enable)begin
  state<=WAIT;kind<=HEADER;table_base<=0;map_offset<=0;first_map<=0;word_index<=0;
  load_frame<=0;load_row<=0;load_bank<=0;startup_done<=0;job_last_row<=0;
  expected_crc<=0;crc<=32'hffffffff;error<=0;done_toggle<=0;request_seen<=0;
  request_sync<=0;request_frame_meta<=0;request_frame_sync<=0;request_row_meta<=0;request_row_sync<=0;
  request_initial_meta<=0;request_initial_sync<=0;video_error_sync<=0;
 end else if(video_error_sync[2])error<=7;
 else if(error==0)case(state)
  WAIT:begin kind<=HEADER;state<=REQUEST;end
  REQUEST:if(stream_ack)begin word_index<=0;crc<=32'hffffffff;state<=READ;end
  READ:if(data_valid)begin
   word_index<=word_index+1'b1;
   if(kind==HEADER)begin
    case(word_index)
     0:if(data!=FRAMES)error<=1;
     1:begin table_base<=data[20:0];if(data[31:21]!=0 || data<384 || data+FRAMES*4>file_words)error<=1;end
     2:if(data!=MAP_WORDS)error<=1;
     3:if(data!=32'h53504f54)error<=1;
     4:begin if(data!=PERIOD)error<=1;kind<=DESC;state<=GAP;end
    endcase
   end else if(kind==DESC)begin
    case(word_index)
     0:begin
      map_offset<=data[20:0];if(load_frame==0)first_map<=data[20:0];
      if(data[31:21]!=0 || data[6:0]!=0 || data<table_base+FRAMES*4 || data+MAP_WORDS>file_words ||
         (load_frame!=0 && data!=first_map+load_frame*MAP_STRIDE))error<=2;
     end
     1:if(data!=MAP_WORDS)error<=2;
     2:expected_crc<=data;
     3:begin if(data!=load_frame)error<=2;kind<=VERIFY;state<=GAP;end
    endcase
   end else if(kind==VERIFY)begin
    if(word_index>=ACTIVE_WORDS && data!=0)error<=5;
    crc<=crc_word(crc,data);
    if(word_index==MAP_WORDS-1)begin
     if((crc_word(crc,data)^32'hffffffff)!=expected_crc)error<=3;
     state<=COMPLETE;
    end
   end else begin
    if(load_bank)row_bank1[{load_row[1:0],word_index[5:0]}]<=data;
    else row_bank0[{load_row[1:0],word_index[5:0]}]<=data;
    if(word_index==39)state<=COMPLETE;
   end
  end
  GAP:state<=REQUEST;
  COMPLETE:begin
   if(!startup_done)begin
    if(load_frame==FRAMES-1)begin startup_done<=1;state<=IDLE;end
    else begin load_frame<=load_frame+1'b1;kind<=DESC;state<=GAP;end
   end else if(!load_bank)begin load_bank<=1;state<=GAP;end
   else if(load_row!=job_last_row)begin load_row<=load_row+1'b1;load_bank<=0;state<=GAP;end
   else begin done_toggle<=~done_toggle;state<=IDLE;end
  end
  IDLE:if(request_sync[2]!=request_seen)begin
   request_seen<=request_sync[2];load_frame<=request_frame_sync;load_row<=request_row_sync;
   job_last_row<=request_initial_sync ? 7'd2 : request_row_sync;load_bank<=0;kind<=ROW;state<=GAP;
  end
  default:error<=4;
 endcase
end
wire frame_tick=vs_in && !vs_previous;
wire advance=initialized && next_ready && display_valid && !pause_sync && initial_hold>=INITIAL_HOLD_FRAMES;
wire field_advance=advance && step==DISPLAY_PERIOD-1;
wire [6:0] scheduled_frame=field_advance ? (frame_index==FRAMES-1 ? 7'd0 : frame_index+1'b1) : frame_index;
wire [9:0] upcoming_y=vs_in ? 10'd0 : de_previous && !de_in ? pixel_y+1'b1 : pixel_y;
wire [9:0] py_shift=upcoming_y>=4 ? upcoming_y-10'd4 : 10'd0;
wire [6:0] upper_y=py_shift[9:3]>89 ? 7'd89 : py_shift[9:3];
wire [6:0] lower_y=upper_y==89 ? upper_y : upper_y+1'b1;
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
  end else if(!de_in && initialized && next_ready && !video_error && upper_y!=last_requested_upper)begin
   last_requested_upper<=upper_y;
   if(upper_y+2<68)begin
    if(request_pending)video_error<=1;
    else begin
     request_frame<=frame_index;request_row<=upper_y+7'd2;request_initial<=0;job_initial<=0;
     request_toggle<=~request_toggle;request_pending<=1;row_valid[(upper_y+7'd2)&3]<=0;
    end
   end
  end
  // HDMI cannot stall. Missing rows are a diagnosed failure, never silently
  // mixed with stale data. Row prefetch normally has eight scanlines' lead.
  if(de_in && !de_previous && initialized && display_valid)begin
   if(!next_ready || (upper_y<68 && (!row_valid[upper_y[1:0]] || row_tag[upper_y[1:0]]!=upper_y)) ||
      (lower_y<68 && (!row_valid[lower_y[1:0]] || row_tag[lower_y[1:0]]!=lower_y)))video_error<=1;
  end
 end
end
// During horizontal blank, copy the two needed ring rows into the existing
// parallel interpolation registers. Field pixels and pipeline are unchanged.
reg [6:0] prefetch_index,prefetch_d,prefetch_d1;
reg prefetch_valid,prefetch_valid1,read_zero;
reg [31:0] read0,read1;
reg [63:0] top_row[0:39],bottom_row[0:39];
wire [6:0] row_y=prefetch_index<40 ? upper_y : lower_y;
wire [5:0] row_word=prefetch_index<40 ? prefetch_index[5:0] : prefetch_index-7'd40;
wire [7:0] row_address={row_y[1:0],row_word};
always @(posedge video_clk)begin
 read0<=row_bank0[row_address];read1<=row_bank1[row_address];read_zero<=row_y>=68;
 if(video_rst)begin prefetch_index<=0;prefetch_d<=0;prefetch_d1<=0;prefetch_valid<=0;prefetch_valid1<=0;end
 else begin
  prefetch_valid<=!de_in;prefetch_d<=prefetch_index;prefetch_valid1<=prefetch_valid;prefetch_d1<=prefetch_d;
  if(de_in)prefetch_index<=0;else prefetch_index<=prefetch_index==79 ? 7'd0 : prefetch_index+1'b1;
  // read0/read1 correspond to prefetch_d, exactly one synchronous RAM cycle.
  if(prefetch_valid)begin
   if(prefetch_d<40)top_row[prefetch_d]<=read_zero ? 64'd0 : {read1,read0};
   else bottom_row[prefetch_d-7'd40]<=read_zero ? 64'd0 : {read1,read0};
  end
 end
end
wire [10:0] px_shift=pixel_x>=4 ? pixel_x-11'd4 : 11'd0;
wire [7:0] left_x=px_shift[10:3]>159 ? 8'd159 : px_shift[10:3];
wire [7:0] right_x=left_x==159 ? left_x : left_x+1'b1;
wire [5:0] left_word=left_x[7:2],right_word=right_x[7:2];
reg [5:0] left_word_d,right_word_d,lane_l_d,lane_r_d,next_l_d,next_r_d;
reg [2:0] fx_address,fy_address;reg [7:0] phase_address;reg coord_valid,coord_de,coord_vs;reg [23:0] coord_rgb;
wire [63:0] tl=top_row[left_word_d],tr=top_row[right_word_d],bl=bottom_row[left_word_d],br=bottom_row[right_word_d];
wire [5:0] lane_l={current_bank,left_x[1:0],3'b000};
wire [5:0] lane_r={current_bank,right_x[1:0],3'b000};
wire [5:0] next_l={~current_bank,left_x[1:0],3'b000};
wire [5:0] next_r={~current_bank,right_x[1:0],3'b000};
reg [7:0] a0,a1,a2,a3,b0,b1,b2,b3;
reg [2:0] fx0,fy0,fy1;reg [7:0] phase0,phase1,phase2,field4;
reg [10:0] top_a1,bottom_a1,top_b1,bottom_b1;
reg [7:0] a2_field,b2_field;reg [15:0] product3a,product3b;
reg [4:0] valid_pipe,de_pipe,vs_pipe;
reg [23:0] rgb_pipe[0:4];reg [7:0] quant_coord,quant_pipe[0:4];integer pipeline_i;
wire [7:0] quant={pixel_x[0]^pixel_y[0],pixel_y[0],pixel_x[1]^pixel_y[1],pixel_y[1],4'd8};
wire [14:0] vertical_a=top_a1*(4'd8-{1'b0,fy1})+bottom_a1*fy1;
wire [14:0] vertical_b=top_b1*(4'd8-{1'b0,fy1})+bottom_b1*fy1;
function [7:0] screen;
 input [7:0] channel,target,light;reg [15:0] product;
 begin product=(target>channel ? target-channel : 8'd0)*light;screen=channel+product[15:8];end
endfunction
always @(posedge video_clk)begin
 if(video_rst)begin
  left_word_d<=0;right_word_d<=0;lane_l_d<=0;lane_r_d<=0;next_l_d<=0;next_r_d<=0;
  fx_address<=0;fy_address<=0;phase_address<=0;coord_valid<=0;coord_de<=0;coord_vs<=0;coord_rgb<=0;
  a0<=0;a1<=0;a2<=0;a3<=0;b0<=0;b1<=0;b2<=0;b3<=0;
  fx0<=0;fy0<=0;fy1<=0;phase0<=0;phase1<=0;phase2<=0;field4<=0;
  top_a1<=0;bottom_a1<=0;top_b1<=0;bottom_b1<=0;a2_field<=0;b2_field<=0;product3a<=0;product3b<=0;
  valid_pipe<=0;de_pipe<=0;vs_pipe<=0;rgb_out<=0;de_out<=0;vs_out<=0;
  for(pipeline_i=0;pipeline_i<5;pipeline_i=pipeline_i+1)begin rgb_pipe[pipeline_i]<=0;quant_pipe[pipeline_i]<=0;end
  quant_coord<=0;
 end else begin
  left_word_d<=left_word;right_word_d<=right_word;lane_l_d<=lane_l;lane_r_d<=lane_r;next_l_d<=next_l;next_r_d<=next_r;
  fx_address<=pixel_x>=4 ? px_shift[2:0] : 3'd0;fy_address<=pixel_y>=4 ? (pixel_y-10'd4) : 3'd0;
  phase_address<=next_ready ? ((step*256+DISPLAY_PERIOD/2)/DISPLAY_PERIOD) : 8'd0;
  quant_coord<=quant;
  coord_valid<=initialized && next_ready && !video_error && display_valid && de_in && pixel_y<548;coord_de<=de_in;coord_vs<=vs_in;coord_rgb<=rgb_in;
  a0<=tl>>lane_l_d;a1<=tr>>lane_r_d;a2<=bl>>lane_l_d;a3<=br>>lane_r_d;
  b0<=tl>>next_l_d;b1<=tr>>next_r_d;b2<=bl>>next_l_d;b3<=br>>next_r_d;
  fx0<=fx_address;fy0<=fy_address;phase0<=phase_address;
  top_a1<=a0*(4'd8-{1'b0,fx0})+a1*fx0;bottom_a1<=a2*(4'd8-{1'b0,fx0})+a3*fx0;
  top_b1<=b0*(4'd8-{1'b0,fx0})+b1*fx0;bottom_b1<=b2*(4'd8-{1'b0,fx0})+b3*fx0;
  fy1<=fy0;phase1<=phase0;
  a2_field<=(vertical_a+quant_pipe[1][7:2])>>6;
  b2_field<=(vertical_b+quant_pipe[1][7:2])>>6;phase2<=phase1;
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
