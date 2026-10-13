`timescale 1ns/1ps
// A keeps current, next, next+1 and next+2 in four independent SDRAM slots.
// Link transactions finish when stored; display commits run independently.
module photo_cached_control_a #(
 parameter CLK_HZ=75000000,TIMER_SCALE=1,FRAME_BYTES=1843200,CHECK_FRAME_CRC=0
)(
 input clk,rst,uart_rx,output uart_tx,input previous,next,
 input [1:0] active_slot,new_slot,input transition_active,commit_toggle,
 output reg [1:0] receive_slot,output reg arm_toggle,abort_toggle,
 input rx_armed,rx_done,rx_fault,input [31:0] rx_crc,
 output reg ready_toggle,output reg [1:0] ready_slot,output reg ready_right,
 output reg [2:0] image_count,current_image,output busy,output reg [3:0] error,
 output [3:0] debug_state,output reg [31:0] debug_local_crc,debug_remote_crc,
 output cache_window_ready,output [2:0] cached_count,
 output reg [15:0] current_source_width,current_source_height
);
localparam TIME_HZ=CLK_HZ/TIMER_SCALE;
localparam HELLO_SEND=0,HELLO_WAIT=1,IDLE=2,GET=3,WAIT_BEGIN=4,ARM=5,
 READY=6,RECEIVE=7,ACCEPT=8,STORE=9,COMMIT=10,NACK=11,FAILED=12;
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
function [2:0] lookup;
 input [2:0] image;integer j;
 begin lookup=0;for(j=3;j>=0;j=j-1)
  if(cache_valid[j] && cache_id[j]==image)lookup={1'b1,j[1:0]};end
endfunction
wire [2:0] nav_hit=lookup(nav_target);
wire [2:0] center=display_pending ? display_target:
                  (nav_pending && nav_hit[2] ? nav_target:current_image);
wire [2:0] window_next=adjacent(center,image_count,1'b1);
wire [2:0] window_next2=adjacent(window_next,image_count,1'b1);
wire [2:0] window_next3=adjacent(window_next2,image_count,1'b1);
wire [2:0] center_hit=lookup(center),next_hit=lookup(window_next),
           next2_hit=lookup(window_next2),next3_hit=lookup(window_next3);
assign cache_window_ready=have_current && center_hit[2] && next_hit[2] && next2_hit[2] && next3_hit[2];
reg fetch_needed,demand_fetch,victim_ok;reg [2:0] fetch_target;
reg [1:0] victim;integer i,reset_index;
always @*begin
 fetch_needed=0;demand_fetch=0;fetch_target=0;victim_ok=0;victim=0;
 if(nav_pending && !nav_hit[2])begin fetch_needed=1;demand_fetch=1;fetch_target=nav_target;end
 else if(have_current && image_count>1)begin
  // Prefetch the following three images in order.
  if(!next_hit[2])begin fetch_needed=1;fetch_target=window_next;end
  else if(!next2_hit[2])begin fetch_needed=1;fetch_target=window_next2;end
  else if(!next3_hit[2])begin fetch_needed=1;fetch_target=window_next3;end
 end
 for(i=3;i>=0;i=i-1)begin
  if(i!=active_slot && (!transition_active || i!=new_slot) &&
     (!display_pending || i!=ready_slot) && (!nav_pending || !nav_hit[2] || i!=nav_hit[1:0]) &&
     (demand_fetch || (cache_id[i]!=center && cache_id[i]!=window_next &&
                       cache_id[i]!=window_next2 && cache_id[i]!=window_next3)))begin
   victim_ok=1;victim=i[1:0];
  end
 end
 // Prefer an empty slot, including a slot invalidated by a failed receive.
 for(i=3;i>=0;i=i-1)begin
  if(!cache_valid[i] && i!=active_slot && (!transition_active || i!=new_slot) &&
     (!display_pending || i!=ready_slot))begin victim_ok=1;victim=i[1:0];end
 end
end
always @(posedge clk or posedge rst)begin
 if(rst)begin
  state<=HELLO_SEND;send<=0;message<=0;session<=1;uptime<=1;timer<=0;request_seq<=0;
  target<=0;direction<=1;done_seen<=0;end_seen<=0;expected_crc<=0;received_crc<=0;retries<=0;
  receive_slot<=1;arm_toggle<=0;abort_toggle<=0;ready_toggle<=0;ready_slot<=0;ready_right<=1;
  image_count<=0;current_image<=0;error<=0;debug_local_crc<=0;debug_remote_crc<=0;
  cache_valid<=0;have_current<=0;nav_pending<=0;nav_target<=0;nav_right<=1;
  display_pending<=0;display_target<=0;commit_seen<=0;
  current_source_width<=0;current_source_height<=0;target_width<=0;target_height<=0;display_width<=0;display_height<=0;
  for(reset_index=0;reset_index<4;reset_index=reset_index+1)cache_id[reset_index]<=0;
 end else begin
  uptime<=uptime+1'b1;timer<=timer+1'b1;send<=0;
  if(display_pending && commit_toggle!=commit_seen)begin
   current_image<=display_target;have_current<=1;display_pending<=0;
   current_source_width<=display_width;current_source_height<=display_height;
  end
  if(!display_pending && !transition_active && nav_pending && nav_hit[2])begin
   ready_slot<=nav_hit[1:0];ready_right<=nav_right;ready_toggle<=~ready_toggle;
   display_target<=nav_target;display_pending<=1;commit_seen<=commit_toggle;nav_pending<=0;
   display_width<=cache_width[nav_hit[1:0]];display_height<=cache_height[nav_hit[1:0]];
  end
  if(got && kind==10)begin
   abort_toggle<=~abort_toggle;state<=HELLO_SEND;session<=uptime;timer<=0;error<=0;
   cache_valid<=0;have_current<=0;nav_pending<=0;
  end else case(state)
   HELLO_SEND:if(!tx_busy && !send && !transition_active && !display_pending)begin
    message<=packet(1,session,0,0,0,FRAME_BYTES,0,0);send<=1;state<=HELLO_WAIT;timer<=0;
   end
   HELLO_WAIT:begin
    if(got && kind==2 && incoming[151:120]==session && incoming[23:16]>0 && incoming[23:16]<=6)begin
     image_count<=incoming[18:16];nav_target<=0;nav_right<=1;nav_pending<=1;
     state<=IDLE;timer<=0;error<=0;
    end else if(timer>=TIME_HZ)begin state<=HELLO_SEND;timer<=0;end
   end
   IDLE:if(fetch_needed && victim_ok)begin
    target<=fetch_target;direction<=nav_right;receive_slot<=victim;cache_valid[victim]<=0;
    request_seq<=request_seq+1'b1;retries<=0;error<=0;state<=GET;timer<=0;
   end
   GET:if(!tx_busy && !send)begin
    message<=packet(3,session,request_seq,{5'd0,target},{6'd0,1'b1,direction},FRAME_BYTES,0,0);
    send<=1;state<=WAIT_BEGIN;timer<=0;done_seen<=0;end_seen<=0;
   end
   WAIT_BEGIN:begin
    if(got && matching && kind==4 && incoming[87:56]==FRAME_BYTES)begin
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
    message<=packet(5,session,request_seq,{5'd0,target},2,FRAME_BYTES,0,0);send<=1;state<=RECEIVE;timer<=0;
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
    message<=packet(7,session,request_seq,{5'd0,target},2,FRAME_BYTES,received_crc,0);send<=1;state<=COMMIT;timer<=0;
   end
   COMMIT:if(!tx_busy && !send)begin
    message<=packet(8,session,request_seq,{5'd0,target},2,FRAME_BYTES,received_crc,0);send<=1;state<=IDLE;error<=0;timer<=0;
   end
   NACK:if(!tx_busy && !send)begin
    abort_toggle<=~abort_toggle;
    message<=packet(9,session,request_seq,{5'd0,target},2,FRAME_BYTES,received_crc,{4'd0,error});send<=1;
    done_seen<=0;end_seen<=0;timer<=0;
    if(retries<2)begin retries<=retries+1'b1;state<=WAIT_BEGIN;end else state<=FAILED;
   end
   FAILED:if(timer>=TIME_HZ && !transition_active && !display_pending)begin
    abort_toggle<=~abort_toggle;session<=uptime;state<=HELLO_SEND;timer<=0;
    cache_valid<=0;have_current<=0;nav_pending<=0;
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
