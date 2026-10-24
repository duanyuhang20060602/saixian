`timescale 1ns/1ps
// A keeps current, next, next+1 and next+2 in four independent SDRAM slots.
// Link transactions finish when stored; display commits run independently.
module photo_cached_control_a #(
 parameter CLK_HZ=75000000,TIMER_SCALE=1,FRAME_BYTES=1843200,CHECK_FRAME_CRC=0,SETTINGS_LINK=0,AWARD_CONTROL=0,FLUID=0,AWARD_LIGHTS=0,EARLY_THUMBNAIL=0,RELIEF_CONTROL=0
)(
 output receive_award,output receive_fluid,
 input settings_mode,input [18:0] settings_state,output settings_updating,
 input award_toggle,relief_toggle,output reg award_available,award_scan_complete,relief_available,
 output award_loading,output reg [2:0] award_notice,output reg [3:0] last_transfer_error,
 output reg [3:0] first_transfer_origin,first_transfer_error,
 input clk,rst,uart_rx,output uart_tx,input previous,next,
 input [1:0] active_slot,new_slot,input transition_active,commit_toggle,
 output reg [1:0] receive_slot,output reg arm_toggle,abort_toggle,
 input rx_armed,rx_done,rx_fault,input [31:0] rx_crc,
 output reg ready_immediate,output reg ready_toggle,output reg [1:0] ready_slot,output reg ready_right,
 output reg [2:0] image_count,current_image,output busy,output reg [3:0] error,
 output [3:0] debug_state,output reg [31:0] debug_local_crc,debug_remote_crc,
 output cache_window_ready,output [2:0] cached_count,
 output thumbnail_valid,output [1:0] thumbnail_slot,output [2:0] thumbnail_id,
 output reg [15:0] current_source_width,current_source_height,
 output reg timing_begin,timing_present,timing_commit,output timing_cancel,
 input thumbnail_read_busy,input [1:0] thumbnail_read_slot
);
localparam TIME_HZ=CLK_HZ/TIMER_SCALE;
localparam HELLO_SEND=0,HELLO_WAIT=1,IDLE=2,GET=3,WAIT_BEGIN=4,ARM=5,
 READY=6,RECEIVE=7,ACCEPT=8,STORE=9,COMMIT=10,NACK=11,FAILED=12,WAIT_SETTINGS=13,WAIT_CONTEXT=14,WAIT_CANCEL=15;
reg [18:0] applied_settings,sent_settings;reg refresh_pending;
reg have_current,nav_pending,nav_right,display_pending,commit_seen;
reg timing_pending,timing_display;
reg [2:0] target;
wire settings_dirty=SETTINGS_LINK && settings_state!=applied_settings;
reg refresh_display,background_transaction;reg count_reply;
reg [4:0] applied_context,sent_context;
wire settings_focus=settings_mode || settings_dirty || refresh_pending || refresh_display || (display_pending && ready_immediate);
// Playback needs no per-image context handshake. Send the HDMI id only
// while pinning it for settings; mode entry/exit still use acknowledged UART.
wire [4:0] live_context={have_current && settings_focus,(settings_focus ? current_image:3'd0),settings_focus};
// Compare the two possible contexts in parallel, then select the
// one-bit result. Settings changes need not traverse a five-bit context
// mux followed by a comparator before enabling a UART transaction.
wire focus_context_dirty=applied_context!={have_current,current_image,1'b1};
wire idle_context_dirty=|applied_context;
wire context_dirty=SETTINGS_LINK && (settings_focus ? focus_context_dirty:idle_context_dirty);
// Stage only the IDLE scheduler predicates. Immediate cancel, display and
// quiet-time decisions retain their live inputs. An IDLE bubble after each
// timer reset lets these predicates observe ACK updates before resending.
reg idle_settings_dirty_q,idle_context_dirty_q;
always @(posedge clk or posedge rst)begin
 if(rst)begin idle_settings_dirty_q<=0;idle_context_dirty_q<=0;end
 else begin idle_settings_dirty_q<=settings_dirty;idle_context_dirty_q<=context_dirty;end
end
localparam SETTLE_CYCLES=CLK_HZ/20; // 50 ms quiet interval coalesces bursts.
localparam SETTLE_BITS=($clog2(SETTLE_CYCLES+1)>0) ? $clog2(SETTLE_CYCLES+1):1;
reg [18:0] observed_settings;reg [SETTLE_BITS-1:0] settings_settle;reg settings_quiet;
always @(posedge clk or posedge rst)begin
 if(rst)begin observed_settings<=0;settings_settle<=0;settings_quiet<=0;end
 else if(settings_state!=observed_settings)begin observed_settings<=settings_state;settings_settle<=0;settings_quiet<=0;end
 else begin
  if(settings_settle<SETTLE_CYCLES)settings_settle<=settings_settle+1'b1;
  if(settings_settle>=SETTLE_CYCLES-1)settings_quiet<=1;
 end
end

wire relief_command=RELIEF_CONTROL && relief_toggle;
wire [2:0] requested_award=relief_command ? 3'd7:3'd6;
wire requested_available=relief_command ? relief_available:award_available;
assign receive_award=AWARD_CONTROL && target>=6;
assign receive_fluid=FLUID && target<6;
wire [31:0] frame_bytes=(AWARD_LIGHTS && receive_award) || receive_fluid ? 32'd2764800:FRAME_BYTES;

assign settings_updating=settings_dirty || refresh_pending || (SETTINGS_LINK && (nav_pending || display_pending));
// A reverse one-hot case removes binary state decoding from the UART
// response/timeout control path. Every state assignment writes one bit.
reg [15:0] state_flags;
function [3:0] state_number;input [15:0] flags;begin
 // One-hot invariant allows four parallel reductions instead of priority muxes.
 state_number={|(flags & 16'hff00),|(flags & 16'hf0f0),
               |(flags & 16'hcccc),|(flags & 16'haaaa)};
end endfunction
wire [3:0] state=state_number(state_flags);
reg send;reg [159:0] message;
wire tx_busy,got,bad;wire [159:0] incoming;
photo_uart #(.CLK_HZ(CLK_HZ),.PULSE_PAYLOAD(1)) port(.clk(clk),.rst(rst),.rx(uart_rx),.tx(uart_tx),
 .send(send),.message(message),.busy(tx_busy),.received(got),.received_message(incoming),.bad_packet(bad));
wire [7:0] kind=incoming[159:152];
assign timing_cancel=award_toggle || relief_command || settings_dirty || refresh_pending || state_flags[FAILED] || (got && kind==10);
reg [31:0] session,uptime;reg [15:0] request_seq;
// Encode a cleared timer with one registered bit. The control FSM drives
// only this bit instead of a reset mux on all 32 counter bits. Reading
// timer still returns zero in the very cycle that a clear is committed.
// begin RELIEF_TIMER_PIPELINE
reg timer_reset;reg [31:0] timer_count;
wire [31:0] timer=timer_reset ? 32'd0:timer_count;
// Predict the post-increment comparison instead of routing a wide counter
// through the same-cycle FSM enable. Counter wrap and timer clears are exact.
reg timeout1_q,timeout2_q,timeout5_q,timeout40_q,timeout45_q;
wire timeout1=(TIME_HZ==0) || (!timer_reset && timeout1_q);
wire timeout2=(TIME_HZ*2==0) || (!timer_reset && timeout2_q);
wire timeout5=(TIME_HZ==0) || (!timer_reset && timeout5_q);
wire timeout40=(TIME_HZ==0) || (!timer_reset && timeout40_q);
wire timeout45=(TIME_HZ==0) || (!timer_reset && timeout45_q);
localparam FAST_TIMEOUT_LOOKAHEAD=(TIME_HZ>=0 && TIME_HZ<=32'h3fffffff);
localparam [31:0] TIMER_ONE=TIME_HZ,TIMER_TWO=TIME_HZ*2;
wire [31:0] incremented_timer=timer_count+32'd1;
function next_timeout;
 input [31:0] count_value;input [63:0] threshold;
 begin next_timeout=threshold==0 || (count_value!=32'hffffffff && {32'd0,count_value}>=threshold-64'd1);end
endfunction
always @(posedge clk or posedge rst)begin
 if(rst)timer_count<=0;
 else if(timer_reset)timer_count<=1;
 else timer_count<=timer_count+1'b1;
end
always @(posedge clk or posedge rst)begin
 if(rst)begin timeout1_q<=0;timeout2_q<=0;timeout5_q<=0;timeout40_q<=0;timeout45_q<=0;end
 else if(timer_reset)begin
  timeout1_q<=32'd1>=TIME_HZ;timeout2_q<=32'd1>=TIME_HZ*2;
  timeout5_q<=32'd1>=64'd5*TIME_HZ;timeout40_q<=32'd1>=64'd40*TIME_HZ;timeout45_q<=32'd1>=64'd45*TIME_HZ;
 end else if(FAST_TIMEOUT_LOOKAHEAD)begin
  timeout1_q<=next_timeout(timer_count,{32'd0,TIMER_ONE});timeout2_q<=next_timeout(timer_count,{32'd0,TIMER_TWO});
  timeout5_q<=next_timeout(timer_count,64'd5*TIME_HZ);timeout40_q<=next_timeout(timer_count,64'd40*TIME_HZ);timeout45_q<=next_timeout(timer_count,64'd45*TIME_HZ);
 end else begin
  // Preserve expression sizing for unusual simulation parameter overrides.
  timeout1_q<=incremented_timer>=TIME_HZ;timeout2_q<=incremented_timer>=TIME_HZ*2;
  timeout5_q<=incremented_timer>=64'd5*TIME_HZ;timeout40_q<=incremented_timer>=64'd40*TIME_HZ;timeout45_q<=incremented_timer>=64'd45*TIME_HZ;
 end
end
// end RELIEF_TIMER_PIPELINE
reg direction,done_seen,end_seen;reg [1:0] retries;
reg [31:0] expected_crc,received_crc;
reg [3:0] cache_valid;reg [2:0] cache_id[0:3];
reg [15:0] cache_width[0:3],cache_height[0:3];
reg [15:0] target_width,target_height,display_width,display_height;
reg award_selected,award_wait;reg [2:0] return_photo,selected_award;
wire selected_available=selected_award==7 ? relief_available:award_available;
assign award_loading=AWARD_CONTROL && (award_wait || (award_selected && current_image!=selected_award));

reg [2:0] nav_target,display_target;
// PULSE_PAYLOAD exposes the completed payload throughout both CRC bytes.
// Consume only on got; register wide comparisons during that stable interval.
reg session_match_q,transaction_match_q,begin_fields_match_q;
reg session_changed;
// A reconnect may coincide with the final CRC. Mask the old comparison for
// one clock after any local session write; the next sample sees the new id.
wire session_matches=session_match_q && !session_changed;
wire matching=session_matches && transaction_match_q;
always @(posedge clk or posedge rst)begin
 if(rst)begin session_match_q<=0;transaction_match_q<=0;begin_fields_match_q<=0;end
 else begin
  session_match_q<=incoming[151:120]==session;
  transaction_match_q<=incoming[119:104]==request_seq && incoming[103:96]=={5'd0,target};
  begin_fields_match_q<=incoming[87:56]==frame_bytes && incoming[94]==1'b0 && incoming[93]==receive_fluid;
 end
end
// Qualify the first diagnostic independently of the state update mux.
// These events are mutually exclusive in the one-hot FSM. Keep receive
// success/cancel/error priorities identical while removing the long state
// priority chain from the sticky diagnostic registers.
wire response_error=got && matching && kind==11;
wire begin_cancel=SETTINGS_LINK && background_transaction && (settings_mode || settings_dirty) && !tx_busy && !send;
wire begin_ok=got && matching && kind==4 && begin_fields_match_q;
wire first_remote=(state_flags[WAIT_BEGIN] && !begin_cancel || state_flags[RECEIVE]) && response_error;
wire first_begin_timeout=state_flags[WAIT_BEGIN] && !begin_cancel && !begin_ok && !response_error && timeout45;
wire first_arm_timeout=state_flags[ARM] && !rx_armed && timeout2;
wire first_rx_fault=state_flags[RECEIVE] && !response_error && rx_fault;
wire first_crc=state_flags[RECEIVE] && !response_error && !rx_fault && done_seen && end_seen && CHECK_FRAME_CRC && received_crc!=expected_crc;
wire first_rx_timeout=state_flags[RECEIVE] && !response_error && !rx_fault && !(done_seen && end_seen) && timeout5;
wire first_event=first_remote || first_begin_timeout || first_arm_timeout || first_rx_fault || first_crc || first_rx_timeout;
wire [3:0] first_origin_value=({4{first_remote}} & 4'd1) |
 ({4{first_begin_timeout || first_rx_timeout}} & 4'd4) |
 ({4{first_arm_timeout}} & 4'd5) | ({4{first_rx_fault}} & 4'd2) | ({4{first_crc}} & 4'd3);
wire [3:0] first_error_value=({4{first_remote}} & incoming[19:16]) |
 ({4{first_begin_timeout}} & 4'd1) | ({4{first_arm_timeout}} & 4'd2) |
 ({4{first_rx_fault}} & 4'd3) | ({4{first_crc}} & 4'd4) | ({4{first_rx_timeout}} & 4'd5);
always @(posedge clk or posedge rst)begin
 if(rst)begin first_transfer_origin<=0;first_transfer_error<=0;end
 else if(next || award_toggle || relief_command)begin first_transfer_origin<=0;first_transfer_error<=0;end
 else if(!(got && kind==10) && first_transfer_origin==0 && first_event)begin
  first_transfer_origin<=first_origin_value;first_transfer_error<=first_error_value;
 end
end
assign debug_state=state;
// Background filling must not restart the auto-play hold timer.
assign busy=!have_current || nav_pending || display_pending || transition_active;
assign cached_count={2'd0,cache_valid[0]}+{2'd0,cache_valid[1]}+
                    {2'd0,cache_valid[2]}+{2'd0,cache_valid[3]};
function [159:0] packet;
 input [7:0] kind;input [31:0] session;input [15:0] request_seq;
 input [7:0] image,flags;input [31:0] length,crc;input [7:0] status;
 begin packet={kind,session,request_seq,image,flags,length,crc,status,16'd0};end
endfunction
function [2:0] adjacent;
 input [2:0] image,count;input right;
 begin if(count<2)adjacent=0;
 else if(right)adjacent=image>=count-1 ? 0:image+1'b1;
 else adjacent=image==0 ? count-1:image-1'b1;end
endfunction
// Compute neighbours from the same centre instead of cascading three
// variable-count wrap comparators into the cache-victim decoder.
function [2:0] forward_by;
 input [2:0] image,count;input [1:0] amount;reg [3:0] sum;
 begin
  sum={1'b0,image}+{2'd0,amount};
  if(count<2)forward_by=0;
  else if(amount==2 && count==2)forward_by=image;
  else if(amount==3 && count==2)forward_by=adjacent(image,count,1'b1);
  else if(amount==3 && count==3)forward_by=image;
  else forward_by=sum>=count ? sum-{1'b0,count}:sum[2:0];
 end
endfunction
function [2:0] lookup;
 input [2:0] image;input [3:0] valid_bits;input [11:0] image_ids;integer j;
 begin lookup=0;for(j=3;j>=0;j=j-1)
  if((!FLUID || j<3) && valid_bits[j] && image_ids[j*3+:3]==image)lookup={1'b1,j[1:0]};end
endfunction
// Explicit function dependencies keep cache fills/invalidation observable in
// simulation as well as synthesis, even when the requested image is constant.
wire [11:0] cache_ids={cache_id[3],cache_id[2],cache_id[1],cache_id[0]};
wire [2:0] nav_hit=lookup(nav_target,cache_valid,cache_ids);
wire [2:0] center=display_pending ? display_target:
                  (nav_pending && nav_hit[2] ? nav_target:current_image);
wire [2:0] window_next=adjacent(center,image_count,1'b1);
wire [2:0] window_next2=forward_by(center,image_count,2'd2);
wire [2:0] window_next3=forward_by(center,image_count,2'd3);
reg [2:0] window_center_q,window_next_q,window_next2_q,window_next3_q;
reg [25:0] window_context;
wire [2:0] center_hit=lookup(window_center_q,cache_valid,cache_ids),next_hit=lookup(window_next_q,cache_valid,cache_ids),
           next2_hit=lookup(window_next2_q,cache_valid,cache_ids),next3_hit=lookup(window_next3_q,cache_valid,cache_ids);

reg fetch_needed,demand_fetch,victim_ok;reg [2:0] fetch_target;
reg [1:0] victim;integer i,reset_index;
wire preview_locked=EARLY_THUMBNAIL && thumbnail_read_busy;
wire [2:0] preview_context={preview_locked,(preview_locked ? thumbnail_read_slot:2'd0)};
always @*begin
 fetch_needed=0;demand_fetch=0;fetch_target=0;victim_ok=0;victim=0;
 if(nav_pending && !nav_hit[2])begin fetch_needed=1;demand_fetch=1;fetch_target=nav_target;end
 else if(have_current && center<6 && image_count>1)begin
  // Prefetch the following three images in order.
  if(!next_hit[2])begin fetch_needed=1;fetch_target=window_next_q;end
  else if(!next2_hit[2])begin fetch_needed=1;fetch_target=window_next2_q;end
  else if(!FLUID && !next3_hit[2])begin fetch_needed=1;fetch_target=window_next3_q;end
 end
 for(i=3;i>=0;i=i-1)begin
  if((!FLUID || i<3) && (!preview_locked || i!=thumbnail_read_slot) && i!=active_slot && (!transition_active || i!=new_slot) &&
     (!display_pending || i!=ready_slot) && (!nav_pending || !nav_hit[2] || i!=nav_hit[1:0]) &&
     (demand_fetch || (cache_id[i]!=window_center_q && cache_id[i]!=window_next_q &&
                       (cache_id[i]!=window_next2_q && (FLUID || cache_id[i]!=window_next3_q)))))begin
   victim_ok=1;victim=i[1:0];
  end
 end
 // Prefer an empty slot, including a slot invalidated by a failed receive.
 for(i=3;i>=0;i=i-1)begin
  if((!FLUID || i<3) && (!preview_locked || i!=thumbnail_read_slot) && !cache_valid[i] && i!=active_slot && (!transition_active || i!=new_slot) &&
     (!display_pending || i!=ready_slot))begin victim_ok=1;victim=i[1:0];end
 end
end
reg plan_needed,plan_ok;reg [2:0] plan_target;reg [1:0] plan_victim;
wire [25:0] fetch_context={cache_valid,active_slot,new_slot,transition_active,display_pending,ready_slot,
 nav_pending,nav_target,current_image,image_count,display_target,have_current};
assign cache_window_ready=window_context==fetch_context && have_current && center_hit[2] && next_hit[2] && (next2_hit[2] && (FLUID || next3_hit[2]));
// Only accepted, CRC-checked cache entries can be exposed as the next preview.
assign thumbnail_slot=next_hit[1:0];
assign thumbnail_id=window_next_q;
assign thumbnail_valid=have_current && next_hit[2] &&
 current_image<6 && image_count>1 && !settings_dirty && !refresh_pending &&
 (EARLY_THUMBNAIL ? (window_center_q==center && window_next_q==window_next && center<6 && !nav_pending):!busy);
reg [25:0] plan_context;
reg [2:0] plan_preview_context;
// Stage one computes the window, stage two chooses the cache victim. Both
// stages retain their context; stale decisions cannot launch a transfer.
always @(posedge clk or posedge rst)begin
 if(rst)begin window_center_q<=0;window_next_q<=0;window_next2_q<=0;window_next3_q<=0;window_context<=0;end
 else begin window_center_q<=center;window_next_q<=window_next;window_next2_q<=window_next2;
  window_next3_q<=window_next3;window_context<=fetch_context;end
end
always @(posedge clk or posedge rst)begin
 if(rst)begin plan_needed<=0;plan_ok<=0;plan_target<=0;plan_victim<=0;plan_context<=0;plan_preview_context<=0;end
 else begin plan_needed<=fetch_needed;plan_ok<=victim_ok && window_context==fetch_context;plan_target<=fetch_target;plan_victim<=victim;plan_context<=fetch_context;plan_preview_context<=preview_context;end
end
always @(posedge clk or posedge rst)begin
 if(rst)begin
  session_changed<=0;timing_begin<=0;timing_present<=0;timing_commit<=0;timing_pending<=0;timing_display<=0;
  award_available<=0;relief_available<=0;selected_award<=6;award_scan_complete<=0;award_notice<=0;last_transfer_error<=0;award_selected<=0;award_wait<=0;return_photo<=0;
  count_reply<=0;applied_settings<={4'd4,4'd4,4'd4,2'd1,2'd1,1'b0,1'b0};sent_settings<=0;refresh_pending<=0;
  applied_context<=31;sent_context<=0;background_transaction<=0;refresh_display<=0;ready_immediate<=0;state_flags<=(16'd1<<HELLO_SEND);send<=0;message<=0;session<=1;uptime<=1;timer_reset<=1;request_seq<=0;
  target<=0;direction<=1;done_seen<=0;end_seen<=0;expected_crc<=0;received_crc<=0;retries<=0;
  receive_slot<=1;arm_toggle<=0;abort_toggle<=0;ready_toggle<=0;ready_slot<=0;ready_right<=1;
  image_count<=0;current_image<=0;error<=0;debug_local_crc<=0;debug_remote_crc<=0;
  cache_valid<=0;have_current<=0;nav_pending<=0;nav_target<=0;nav_right<=1;
  display_pending<=0;display_target<=0;commit_seen<=0;
  current_source_width<=0;current_source_height<=0;target_width<=0;target_height<=0;display_width<=0;display_height<=0;
  for(reset_index=0;reset_index<4;reset_index=reset_index+1)cache_id[reset_index]<=0;
 end else begin
  session_changed<=0;uptime<=uptime+1'b1;timer_reset<=0;send<=0;
  timing_begin<=0;timing_present<=0;timing_commit<=0;
  if(got && kind==18 && session_matches && incoming[18:16]>=image_count && incoming[18:16]<=6 && (incoming[18:16]>0 || (AWARD_CONTROL && (incoming[23] || (RELIEF_CONTROL && incoming[21])))))begin
   image_count<=incoming[18:16];count_reply<=1;
   if(AWARD_CONTROL)begin award_available<=incoming[23];relief_available<=RELIEF_CONTROL && incoming[21];award_scan_complete<=incoming[22];end
  end
  if(display_pending && commit_toggle!=commit_seen)begin
   timing_commit<=timing_display;timing_display<=0;
   current_image<=display_target;have_current<=1;display_pending<=0;
   if(AWARD_CONTROL && display_target>=6)award_notice<=0;
   current_source_width<=display_width;current_source_height<=display_height;
  end
  if(!settings_dirty && !refresh_pending && !state_flags[WAIT_SETTINGS] && !display_pending && !transition_active && nav_pending && nav_hit[2])begin
   timing_present<=timing_pending;timing_display<=timing_pending;timing_pending<=0;
    // Tagged plates cannot pass through photo spatial/dissolve transitions.
    ready_slot<=nav_hit[1:0];ready_right<=nav_right;ready_immediate<=refresh_display || cache_width[nav_hit[1:0]][15] || current_source_width[15];refresh_display<=0;ready_toggle<=~ready_toggle;
   display_target<=nav_target;display_pending<=1;commit_seen<=commit_toggle;nav_pending<=0;
   display_width<=cache_width[nav_hit[1:0]];display_height<=cache_height[nav_hit[1:0]];
  end
  if(got && kind==10)begin
   count_reply<=0;
   abort_toggle<=~abort_toggle;state_flags<=(16'd1<<HELLO_SEND);session<=uptime;session_changed<=1;timer_reset<=1;error<=0;
   cache_valid<=0;have_current<=0;nav_pending<=0;
   if(SETTINGS_LINK)begin applied_settings<=~settings_state;applied_context<=~live_context;end refresh_pending<=0;
  end else (* parallel_case *) case(1'b1)
   state_flags[HELLO_SEND]:if(!tx_busy && !send && !transition_active && !display_pending)begin
    message<=packet(1,session,0,0,0,FRAME_BYTES,0,0);send<=1;state_flags<=(16'd1<<HELLO_WAIT);timer_reset<=1;
   end
   state_flags[HELLO_WAIT]:begin
    if(got && kind==2 && session_matches && incoming[18:16]<=6 && (incoming[18:16]>0 || (AWARD_CONTROL && (incoming[23] || (RELIEF_CONTROL && incoming[21])))))begin
     if(SETTINGS_LINK)begin applied_settings<=~settings_state;applied_context<=~live_context;end
     image_count<=incoming[18:16];nav_target<=incoming[18:16]==0 ? (incoming[23] ? 3'd6:3'd7):3'd0;selected_award<=incoming[23] ? 3'd6:3'd7;nav_right<=1;nav_pending<=1;
     if(AWARD_CONTROL)begin award_available<=incoming[23];relief_available<=RELIEF_CONTROL && incoming[21];award_scan_complete<=incoming[22];award_selected<=incoming[18:16]==0;end
     state_flags<=(16'd1<<IDLE);timer_reset<=1;error<=0;
    end else if(timeout1)begin state_flags<=(16'd1<<HELLO_SEND);timer_reset<=1;end
   end
   state_flags[IDLE]:if(!timer_reset)begin
    if(count_reply && !tx_busy && !send)begin
    message<=packet(19,session,0,0,0,FRAME_BYTES,0,(AWARD_CONTROL ? {award_available,award_scan_complete,relief_available,2'd0,image_count}:{5'd0,image_count}));send<=1;count_reply<=0;
   end else if(idle_context_dirty_q)begin
    if(!tx_busy && !send)begin
     sent_context<=live_context;
     message<=packet(14,session,0,{5'd0,live_context[3:1]},{6'd0,live_context[4],live_context[0]},0,0,0);
     send<=1;state_flags<=(16'd1<<WAIT_CONTEXT);timer_reset<=1;
    end
   end else if(idle_settings_dirty_q)begin
    if(settings_quiet && settings_state==observed_settings && !transition_active && !display_pending && !tx_busy && !send)begin
     sent_settings<=settings_state;
     message<=packet(12,session,0,0,0,0,{13'd0,settings_state},0);send<=1;state_flags<=(16'd1<<WAIT_SETTINGS);timer_reset<=1;
    end
   end else if(refresh_pending)begin
    if(!display_pending && !transition_active)begin
     refresh_display<=1;cache_valid<=0;nav_target<=have_current ? current_image:nav_target;nav_right<=1;nav_pending<=1;refresh_pending<=0;
    end
   end else if(plan_needed && plan_ok && plan_context==fetch_context && plan_preview_context==preview_context && (nav_pending || !settings_focus))begin
    background_transaction<=!nav_pending;target<=plan_target;direction<=nav_right;receive_slot<=plan_victim;cache_valid[plan_victim]<=0;
    request_seq<=request_seq+1'b1;retries<=0;error<=0;state_flags<=(16'd1<<GET);timer_reset<=1;
   end
   end
   state_flags[WAIT_CONTEXT]:begin
    if(got && kind==15 && session_matches && {incoming[89],incoming[98:96],incoming[88]}==sent_context)begin
     applied_context<=sent_context;state_flags<=(16'd1<<IDLE);timer_reset<=1;
    end else if(timeout1)begin applied_context<=~live_context;state_flags<=(16'd1<<IDLE);timer_reset<=1;end
   end
   state_flags[WAIT_CANCEL]:begin
    if(got && kind==17 && session_matches)begin state_flags<=(16'd1<<IDLE);timer_reset<=1;end
    else if(timeout1 && !tx_busy && !send)begin message<=packet(16,session,0,0,0,0,0,0);send<=1;timer_reset<=1;end
   end
   state_flags[WAIT_SETTINGS]:begin
    if(got && kind==13 && session_matches && incoming[42:24]==sent_settings)begin
     applied_settings<=sent_settings;refresh_pending<=1;state_flags<=(16'd1<<IDLE);timer_reset<=1;
    end else if(timeout1)begin applied_settings<=~settings_state;state_flags<=(16'd1<<IDLE);timer_reset<=1;end
   end
   state_flags[GET]:if(SETTINGS_LINK && background_transaction && (settings_mode || settings_dirty))state_flags<=(16'd1<<IDLE);
       else if(!tx_busy && !send)begin
    message<=packet(3,session,request_seq,{5'd0,target},{1'b0,1'b0,receive_fluid,3'd0,1'b1,direction},frame_bytes,0,0);
    send<=1;state_flags<=(16'd1<<WAIT_BEGIN);timer_reset<=1;done_seen<=0;end_seen<=0;
   end
   state_flags[WAIT_BEGIN]:begin
    if(SETTINGS_LINK && background_transaction && (settings_mode || settings_dirty) && !tx_busy && !send)begin
     message<=packet(16,session,0,0,0,0,0,0);send<=1;state_flags<=(16'd1<<WAIT_CANCEL);timer_reset<=1;
    end else if(begin_ok)begin
     // Metadata belongs to this transfer, never to a background display.
     target_width<=incoming[95] ? incoming[55:40]:16'd0;
     target_height<=incoming[95] ? incoming[39:24]:16'd0;
     arm_toggle<=~arm_toggle;state_flags<=(16'd1<<ARM);timer_reset<=1;
    end else if(response_error)begin
     error<=incoming[19:16];timer_reset<=1;
     if(AWARD_CONTROL && have_current)begin state_flags<=(16'd1<<IDLE);nav_pending<=0;award_wait<=0;award_selected<=current_image>=6;selected_award<=current_image;award_notice<=target>=6 ? 3'd3:3'd4;last_transfer_error<=incoming[19:16];end
     else state_flags<=(16'd1<<FAILED);
    end
    else if(timeout45)begin
     error<=1;state_flags<=(16'd1<<FAILED);timer_reset<=1;
    end
   end
   state_flags[ARM]:if(rx_armed)begin state_flags<=(16'd1<<READY);timer_reset<=1;end
       else if(timeout2)begin
        state_flags<=(16'd1<<NACK);error<=2;
       end
   state_flags[READY]:if(!tx_busy && !send)begin
    message<=packet(5,session,request_seq,{5'd0,target},2,frame_bytes,0,0);send<=1;state_flags<=(16'd1<<RECEIVE);timer_reset<=1;
   end
   state_flags[RECEIVE]:begin
    if(rx_done)begin done_seen<=1;received_crc<=rx_crc;end
    if(got && matching && kind==6)begin expected_crc<=incoming[55:24];end_seen<=1;end
    if(response_error)begin
     error<=incoming[19:16];state_flags<=(16'd1<<FAILED);timer_reset<=1;
    end
    else if(rx_fault)begin
     error<=3;state_flags<=(16'd1<<NACK);
    end
    else if(done_seen && end_seen)begin
     debug_local_crc<=received_crc;debug_remote_crc<=expected_crc;
     if(CHECK_FRAME_CRC && received_crc!=expected_crc)begin
      error<=4;state_flags<=(16'd1<<NACK);
     end
     else begin state_flags<=(16'd1<<STORE);timer_reset<=1;end
    end else if(timeout5)begin
     error<=5;state_flags<=(16'd1<<NACK);
    end
   end
   state_flags[STORE]:begin
    cache_id[receive_slot]<=target;cache_width[receive_slot]<=target_width;cache_height[receive_slot]<=target_height;
    cache_valid[receive_slot]<=1;state_flags<=(16'd1<<ACCEPT);timer_reset<=1;
   end
   state_flags[ACCEPT]:if(!tx_busy && !send)begin
    message<=packet(7,session,request_seq,{5'd0,target},2,frame_bytes,received_crc,0);send<=1;state_flags<=(16'd1<<COMMIT);timer_reset<=1;
   end
   state_flags[COMMIT]:if(!tx_busy && !send)begin
    message<=packet(8,session,request_seq,{5'd0,target},2,frame_bytes,received_crc,0);send<=1;state_flags<=(16'd1<<IDLE);error<=0;timer_reset<=1;
   end
   state_flags[NACK]:if(!tx_busy && !send)begin
    abort_toggle<=~abort_toggle;
    message<=packet(9,session,request_seq,{5'd0,target},2,frame_bytes,received_crc,{4'd0,error});send<=1;
    done_seen<=0;end_seen<=0;timer_reset<=1;
    if(retries<2)begin retries<=retries+1'b1;state_flags<=(16'd1<<WAIT_BEGIN);end else state_flags<=(16'd1<<FAILED);
   end
   state_flags[FAILED]:if(AWARD_CONTROL && have_current && !transition_active && !display_pending && !tx_busy && !send)begin
    abort_toggle<=~abort_toggle;message<=packet(16,session,0,0,0,0,0,0);send<=1;state_flags<=(16'd1<<WAIT_CANCEL);nav_pending<=0;award_wait<=0;award_selected<=current_image>=6;selected_award<=current_image;award_notice<=target>=6 ? 3'd3:3'd4;last_transfer_error<=error;timer_reset<=1;
   end else if(timeout1 && !transition_active && !display_pending)begin
    abort_toggle<=~abort_toggle;session<=uptime;session_changed<=1;state_flags<=(16'd1<<HELLO_SEND);timer_reset<=1;
    cache_valid<=0;have_current<=0;nav_pending<=0;
    if(SETTINGS_LINK)begin applied_settings<=~settings_state;applied_context<=~live_context;end refresh_pending<=0;
   end
   default:state_flags<=(16'd1<<HELLO_SEND);
  endcase
  // Forward navigation is queued during transfer/transition; cached navigation
  // can start immediately even while an unrelated background frame is arriving.
  if(AWARD_CONTROL && award_wait && selected_available)begin
   nav_target<=selected_award;nav_right<=1;nav_pending<=1;award_wait<=0;
  end else if(AWARD_CONTROL && award_wait && award_scan_complete)begin
   award_wait<=0;award_selected<=0;award_notice<=2;
  end
  if(AWARD_CONTROL && (award_toggle || relief_command))begin
   selected_award<=requested_award;
   if((award_selected || award_wait || current_image>=6) && selected_award==requested_award)begin
    award_selected<=0;award_wait<=0;award_notice<=0;
    if(image_count!=0)begin nav_target<=return_photo;nav_right<=1;nav_pending<=1;end
   end else begin
    if(current_image<6)return_photo<=current_image;
    if(requested_available)begin award_selected<=1;award_wait<=0;award_notice<=1;nav_target<=requested_award;nav_right<=1;nav_pending<=1;end
    else if(!award_scan_complete)begin award_selected<=1;award_wait<=1;award_notice<=1;end
    else begin award_selected<=0;award_wait<=0;award_notice<=2;end
   end
  end
  if(next && image_count!=0)begin
   timing_begin<=1;timing_pending<=1;timing_display<=0;
   nav_target<=adjacent(AWARD_CONTROL && (center>=6 || award_selected) ? return_photo:center,image_count,1'b1);
   nav_right<=1'b1;nav_pending<=1;award_selected<=0;award_wait<=0;award_notice<=0;
  end
  if(timing_cancel)begin timing_pending<=0;timing_display<=0;end
 end
end
endmodule
