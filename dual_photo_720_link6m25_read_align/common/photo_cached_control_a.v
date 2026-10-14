`timescale 1ns/1ps
// A keeps current, next, next+1 and next+2 in four independent SDRAM slots.
// Link transactions finish when stored; display commits run independently.
module photo_cached_control_a #(
 parameter CLK_HZ=75000000,TIMER_SCALE=1,FRAME_BYTES=1843200,CHECK_FRAME_CRC=0,SETTINGS_LINK=0
)(
 input settings_mode,input [18:0] settings_state,output settings_updating,
 output reg high_color,output reg format_changed,
 input clk,rst,uart_rx,output uart_tx,input previous,next,
 input [1:0] active_slot,new_slot,input transition_active,commit_toggle,
 output reg [1:0] receive_slot,output reg arm_toggle,abort_toggle,
 input rx_armed,rx_done,rx_fault,input [31:0] rx_crc,
 output reg ready_immediate,output reg ready_toggle,output reg [1:0] ready_slot,output reg ready_right,
 output reg [2:0] image_count,current_image,output busy,output reg [3:0] error,
 output [3:0] debug_state,output reg [31:0] debug_local_crc,debug_remote_crc,
 output cache_window_ready,output [2:0] cached_count,
 output reg [15:0] current_source_width,current_source_height
);
localparam TIME_HZ=CLK_HZ/TIMER_SCALE;
localparam HELLO_SEND=0,HELLO_WAIT=1,IDLE=2,GET=3,WAIT_BEGIN=4,ARM=5,
 READY=6,RECEIVE=7,ACCEPT=8,STORE=9,COMMIT=10,NACK=11,FAILED=12,WAIT_SETTINGS=13,WAIT_CONTEXT=14,WAIT_CANCEL=15;
reg refresh_display,background_transaction;reg count_reply;
reg [4:0] applied_context,sent_context;
wire settings_focus=settings_mode || settings_dirty || refresh_pending || refresh_display || (display_pending && ready_immediate);
// Playback needs no per-image context handshake. Send the HDMI id only
// while pinning it for settings; mode entry/exit still use acknowledged UART.
wire [4:0] live_context={have_current && settings_focus,(settings_focus ? current_image:3'd0),settings_focus};
wire context_dirty=SETTINGS_LINK && live_context!=applied_context;
localparam SETTLE_CYCLES=CLK_HZ/20; // 50 ms quiet interval coalesces bursts.
reg [18:0] observed_settings;reg [31:0] settings_settle;reg settings_quiet;
always @(posedge clk or posedge rst)begin
 if(rst)begin observed_settings<=0;settings_settle<=0;settings_quiet<=0;end
 else if(settings_state!=observed_settings)begin observed_settings<=settings_state;settings_settle<=0;settings_quiet<=0;end
 else begin
  if(settings_settle<SETTLE_CYCLES)settings_settle<=settings_settle+1'b1;
  if(settings_settle>=SETTLE_CYCLES-1)settings_quiet<=1;
 end
end
reg [18:0] applied_settings,sent_settings;reg refresh_pending;
wire [31:0] frame_bytes=high_color ? 32'd2764800:FRAME_BYTES;
wire settings_dirty=SETTINGS_LINK && settings_state!=applied_settings;
assign settings_updating=settings_dirty || refresh_pending || (SETTINGS_LINK && (nav_pending || display_pending));
reg [3:0] state;reg send;reg [159:0] message;
wire tx_busy,got,bad;wire [159:0] incoming;
photo_uart #(.CLK_HZ(CLK_HZ)) port(.clk(clk),.rst(rst),.rx(uart_rx),.tx(uart_tx),
 .send(send),.message(message),.busy(tx_busy),.received(got),.received_message(incoming),.bad_packet(bad));
wire [7:0] kind=incoming[159:152];
reg [31:0] session,uptime,timer;reg [15:0] request_seq;
reg [2:0] target;reg direction,done_seen,end_seen;reg [1:0] retries;
reg [31:0] expected_crc,received_crc;
reg [3:0] cache_valid;reg [2:0] cache_id[0:3];
reg [15:0] cache_width[0:3],cache_height[0:3];
reg [15:0] target_width,target_height,display_width,display_height;
reg have_current,nav_pending,nav_right,display_pending,commit_seen;
reg [2:0] nav_target,display_target;
wire matching=incoming[151:120]==session && incoming[119:104]==request_seq &&
              incoming[103:96]=={5'd0,target};
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
 else if(right)adjacent=image==count-1 ? 0:image+1'b1;
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
 input [2:0] image;integer j;
 begin lookup=0;for(j=3;j>=0;j=j-1)
  if((!high_color || j<2) && cache_valid[j] && cache_id[j]==image)lookup={1'b1,j[1:0]};end
endfunction
wire [2:0] nav_hit=lookup(nav_target);
wire [2:0] center=display_pending ? display_target:
                  (nav_pending && nav_hit[2] ? nav_target:current_image);
wire [2:0] window_next=adjacent(center,image_count,1'b1);
wire [2:0] window_next2=forward_by(center,image_count,2'd2);
wire [2:0] window_next3=forward_by(center,image_count,2'd3);
reg [2:0] window_center_q,window_next_q,window_next2_q,window_next3_q;
reg [25:0] window_context;
wire [2:0] center_hit=lookup(window_center_q),next_hit=lookup(window_next_q),
           next2_hit=lookup(window_next2_q),next3_hit=lookup(window_next3_q);
assign cache_window_ready=window_context==fetch_context && have_current && center_hit[2] && next_hit[2] && (high_color || (next2_hit[2] && next3_hit[2]));
reg fetch_needed,demand_fetch,victim_ok;reg [2:0] fetch_target;
reg [1:0] victim;integer i,reset_index;
always @*begin
 fetch_needed=0;demand_fetch=0;fetch_target=0;victim_ok=0;victim=0;
 if(nav_pending && !nav_hit[2])begin fetch_needed=1;demand_fetch=1;fetch_target=nav_target;end
 else if(have_current && image_count>1)begin
  // Prefetch the following three images in order.
  if(!next_hit[2])begin fetch_needed=1;fetch_target=window_next_q;end
  else if(!high_color && !next2_hit[2])begin fetch_needed=1;fetch_target=window_next2_q;end
  else if(!high_color && !next3_hit[2])begin fetch_needed=1;fetch_target=window_next3_q;end
 end
 for(i=3;i>=0;i=i-1)begin
  if((!high_color || i<2) && i!=active_slot && (!transition_active || i!=new_slot) &&
     (!display_pending || i!=ready_slot) && (!nav_pending || !nav_hit[2] || i!=nav_hit[1:0]) &&
     (demand_fetch || (cache_id[i]!=window_center_q && cache_id[i]!=window_next_q &&
                       (high_color || (cache_id[i]!=window_next2_q && cache_id[i]!=window_next3_q)))))begin
   victim_ok=1;victim=i[1:0];
  end
 end
 // Prefer an empty slot, including a slot invalidated by a failed receive.
 for(i=3;i>=0;i=i-1)begin
  if((!high_color || i<2) && !cache_valid[i] && i!=active_slot && (!transition_active || i!=new_slot) &&
     (!display_pending || i!=ready_slot))begin victim_ok=1;victim=i[1:0];end
 end
end
reg plan_needed,plan_ok;reg [2:0] plan_target;reg [1:0] plan_victim;
wire [25:0] fetch_context={cache_valid,active_slot,new_slot,transition_active,display_pending,ready_slot,
 nav_pending,nav_target,current_image,image_count,display_target,have_current};
reg [25:0] plan_context;
// Stage one computes the window, stage two chooses the cache victim. Both
// stages retain their context; stale decisions cannot launch a transfer.
always @(posedge clk or posedge rst)begin
 if(rst)begin window_center_q<=0;window_next_q<=0;window_next2_q<=0;window_next3_q<=0;window_context<=0;end
 else begin window_center_q<=center;window_next_q<=window_next;window_next2_q<=window_next2;
  window_next3_q<=window_next3;window_context<=fetch_context;end
end
always @(posedge clk or posedge rst)begin
 if(rst)begin plan_needed<=0;plan_ok<=0;plan_target<=0;plan_victim<=0;plan_context<=0;end
 else begin plan_needed<=fetch_needed;plan_ok<=victim_ok && window_context==fetch_context;plan_target<=fetch_target;plan_victim<=victim;plan_context<=fetch_context;end
end
always @(posedge clk or posedge rst)begin
 if(rst)begin
  high_color<=0;format_changed<=0;count_reply<=0;applied_settings<={4'd4,4'd4,4'd4,2'd1,2'd1,1'b0,1'b0};sent_settings<=0;refresh_pending<=0;
  applied_context<=31;sent_context<=0;background_transaction<=0;refresh_display<=0;ready_immediate<=0;state<=HELLO_SEND;send<=0;message<=0;session<=1;uptime<=1;timer<=0;request_seq<=0;
  target<=0;direction<=1;done_seen<=0;end_seen<=0;expected_crc<=0;received_crc<=0;retries<=0;
  receive_slot<=1;arm_toggle<=0;abort_toggle<=0;ready_toggle<=0;ready_slot<=0;ready_right<=1;
  image_count<=0;current_image<=0;error<=0;debug_local_crc<=0;debug_remote_crc<=0;
  cache_valid<=0;have_current<=0;nav_pending<=0;nav_target<=0;nav_right<=1;
  display_pending<=0;display_target<=0;commit_seen<=0;
  current_source_width<=0;current_source_height<=0;target_width<=0;target_height<=0;display_width<=0;display_height<=0;
  for(reset_index=0;reset_index<4;reset_index=reset_index+1)cache_id[reset_index]<=0;
 end else begin
  uptime<=uptime+1'b1;timer<=timer+1'b1;send<=0;format_changed<=0;
  if(got && kind==18 && incoming[151:120]==session && incoming[23:16]>=image_count && incoming[23:16]>0 && incoming[23:16]<=6)begin
   image_count<=incoming[18:16];count_reply<=1;
  end
  if(display_pending && commit_toggle!=commit_seen)begin
   current_image<=display_target;have_current<=1;display_pending<=0;
   current_source_width<=display_width;current_source_height<=display_height;
  end
  if(!settings_dirty && !refresh_pending && state!=WAIT_SETTINGS && !display_pending && !transition_active && nav_pending && nav_hit[2])begin
   ready_slot<=nav_hit[1:0];ready_right<=nav_right;ready_immediate<=refresh_display;refresh_display<=0;ready_toggle<=~ready_toggle;
   display_target<=nav_target;display_pending<=1;commit_seen<=commit_toggle;nav_pending<=0;
   display_width<=cache_width[nav_hit[1:0]];display_height<=cache_height[nav_hit[1:0]];
  end
  if(got && kind==10)begin
   count_reply<=0;
   abort_toggle<=~abort_toggle;state<=HELLO_SEND;session<=uptime;timer<=0;error<=0;
   cache_valid<=0;have_current<=0;nav_pending<=0;
   if(SETTINGS_LINK)begin applied_settings<=~settings_state;applied_context<=~live_context;end refresh_pending<=0;
  end else case(state)
   HELLO_SEND:if(!tx_busy && !send && !transition_active && !display_pending)begin
    message<=packet(1,session,0,0,0,FRAME_BYTES,0,0);send<=1;state<=HELLO_WAIT;timer<=0;
   end
   HELLO_WAIT:begin
    if(got && kind==2 && incoming[151:120]==session && incoming[23:16]>0 && incoming[23:16]<=6)begin
     if(SETTINGS_LINK)begin applied_settings<=~settings_state;applied_context<=~live_context;end
     image_count<=incoming[18:16];nav_target<=0;nav_right<=1;nav_pending<=1;
     state<=IDLE;timer<=0;error<=0;
    end else if(timer>=TIME_HZ)begin state<=HELLO_SEND;timer<=0;end
   end
   IDLE:if(count_reply && !tx_busy && !send)begin
    message<=packet(19,session,0,0,0,FRAME_BYTES,0,{5'd0,image_count});send<=1;count_reply<=0;
   end else if(context_dirty)begin
    if(!tx_busy && !send)begin
     sent_context<=live_context;
     message<=packet(14,session,0,{5'd0,live_context[3:1]},{6'd0,live_context[4],live_context[0]},0,0,0);
     send<=1;state<=WAIT_CONTEXT;timer<=0;
    end
   end else if(settings_dirty)begin
    if(settings_quiet && settings_state==observed_settings && !transition_active && !display_pending && !tx_busy && !send)begin
     sent_settings<=settings_state;
     message<=packet(12,session,0,0,0,0,{13'd0,settings_state},0);send<=1;state<=WAIT_SETTINGS;timer<=0;
    end
   end else if(refresh_pending)begin
    if(!display_pending && !transition_active)begin
     refresh_display<=1;cache_valid<=0;nav_target<=have_current ? current_image:nav_target;nav_right<=1;nav_pending<=1;refresh_pending<=0;
    end
   end else if(plan_needed && plan_ok && plan_context==fetch_context && (nav_pending || !settings_focus))begin
    background_transaction<=!nav_pending;target<=plan_target;direction<=nav_right;receive_slot<=plan_victim;cache_valid[plan_victim]<=0;
    request_seq<=request_seq+1'b1;retries<=0;error<=0;state<=GET;timer<=0;
   end
   WAIT_CONTEXT:begin
    if(got && kind==15 && incoming[151:120]==session && {incoming[89],incoming[98:96],incoming[88]}==sent_context)begin
     applied_context<=sent_context;state<=IDLE;timer<=0;
    end else if(timer>=TIME_HZ)begin applied_context<=~live_context;state<=IDLE;timer<=0;end
   end
   WAIT_CANCEL:begin
    if(got && kind==17 && incoming[151:120]==session)begin state<=IDLE;timer<=0;end
    else if(timer>=TIME_HZ && !tx_busy && !send)begin message<=packet(16,session,0,0,0,0,0,0);send<=1;timer<=0;end
   end
   WAIT_SETTINGS:begin
    if(got && kind==13 && incoming[151:120]==session && incoming[42:24]==sent_settings)begin
     applied_settings<=sent_settings;refresh_pending<=1;state<=IDLE;timer<=0;
     if(high_color!=sent_settings[18])begin
      high_color<=sent_settings[18];format_changed<=1;cache_valid<=0;have_current<=0;
      nav_target<=have_current ? current_image:nav_target;nav_right<=1;nav_pending<=0;
      display_pending<=0;ready_toggle<=0;ready_immediate<=1;refresh_display<=1;
     end
    end else if(timer>=(settings_state[18]!=high_color ? 64'd40*TIME_HZ:TIME_HZ))begin applied_settings<=~settings_state;state<=IDLE;timer<=0;end
   end
   GET:if(SETTINGS_LINK && background_transaction && (settings_mode || settings_dirty))state<=IDLE;
       else if(!tx_busy && !send)begin
    message<=packet(3,session,request_seq,{5'd0,target},{1'b0,high_color,4'd0,1'b1,direction},frame_bytes,0,0);
    send<=1;state<=WAIT_BEGIN;timer<=0;done_seen<=0;end_seen<=0;
   end
   WAIT_BEGIN:begin
    if(SETTINGS_LINK && background_transaction && (settings_mode || settings_dirty) && !tx_busy && !send)begin
     message<=packet(16,session,0,0,0,0,0,0);send<=1;state<=WAIT_CANCEL;timer<=0;
    end else if(got && matching && kind==4 && incoming[87:56]==frame_bytes && incoming[94]==high_color)begin
     // Metadata belongs to this transfer, never to a background display.
     target_width<=incoming[95] ? incoming[55:40]:16'd0;
     target_height<=incoming[95] ? incoming[39:24]:16'd0;
     arm_toggle<=~arm_toggle;state<=ARM;timer<=0;
    end else if(got && matching && kind==11)begin error<=incoming[19:16];state<=FAILED;timer<=0;end
    else if(timer>=64'd45*TIME_HZ)begin error<=1;state<=FAILED;timer<=0;end
   end
   ARM:if(rx_armed)begin state<=READY;timer<=0;end
       else if(timer>=TIME_HZ*2)begin state<=NACK;error<=2;end
   READY:if(!tx_busy && !send)begin
    message<=packet(5,session,request_seq,{5'd0,target},2,frame_bytes,0,0);send<=1;state<=RECEIVE;timer<=0;
   end
   RECEIVE:begin
    if(rx_done)begin done_seen<=1;received_crc<=rx_crc;end
    if(got && matching && kind==6)begin expected_crc<=incoming[55:24];end_seen<=1;end
    if(rx_fault)begin error<=3;state<=NACK;end
    else if(done_seen && end_seen)begin
     debug_local_crc<=received_crc;debug_remote_crc<=expected_crc;
     if(CHECK_FRAME_CRC && received_crc!=expected_crc)begin error<=4;state<=NACK;end
     else begin state<=STORE;timer<=0;end
    end else if(timer>=64'd5*TIME_HZ)begin error<=5;state<=NACK;end
   end
   STORE:begin
    cache_id[receive_slot]<=target;cache_width[receive_slot]<=target_width;cache_height[receive_slot]<=target_height;
    cache_valid[receive_slot]<=1;state<=ACCEPT;timer<=0;
   end
   ACCEPT:if(!tx_busy && !send)begin
    message<=packet(7,session,request_seq,{5'd0,target},2,frame_bytes,received_crc,0);send<=1;state<=COMMIT;timer<=0;
   end
   COMMIT:if(!tx_busy && !send)begin
    message<=packet(8,session,request_seq,{5'd0,target},2,frame_bytes,received_crc,0);send<=1;state<=IDLE;error<=0;timer<=0;
   end
   NACK:if(!tx_busy && !send)begin
    abort_toggle<=~abort_toggle;
    message<=packet(9,session,request_seq,{5'd0,target},2,frame_bytes,received_crc,{4'd0,error});send<=1;
    done_seen<=0;end_seen<=0;timer<=0;
    if(retries<2)begin retries<=retries+1'b1;state<=WAIT_BEGIN;end else state<=FAILED;
   end
   FAILED:if(timer>=TIME_HZ && !transition_active && !display_pending)begin
    abort_toggle<=~abort_toggle;session<=uptime;state<=HELLO_SEND;timer<=0;
    cache_valid<=0;have_current<=0;nav_pending<=0;
    if(SETTINGS_LINK)begin applied_settings<=~settings_state;applied_context<=~live_context;end refresh_pending<=0;
   end
   default:state<=HELLO_SEND;
  endcase
  // Forward navigation is queued during transfer/transition; cached navigation
  // can start immediately even while an unrelated background frame is arriving.
  if(next && image_count!=0)begin
   nav_target<=adjacent(center,image_count,1'b1);nav_right<=1'b1;nav_pending<=1;
  end
 end
end
endmodule
