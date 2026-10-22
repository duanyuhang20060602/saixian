`timescale 1ns/1ps
// Packet fields: type, session, request_seq, image, flags, byte length, CRC32,
// status, reserved. CRC16 framing lives in photo_uart.
module photo_control_a #(parameter CLK_HZ=75000000,TIMER_SCALE=1,FRAME_BYTES=1843200,CHECK_FRAME_CRC=0)(
 input clk,rst,uart_rx,output uart_tx,input previous,next,
 input [1:0] active_slot,new_slot,input transition_active,commit_toggle,
 output reg [1:0] receive_slot,output reg arm_toggle,abort_toggle,
 input rx_armed,rx_done,rx_fault,input [31:0] rx_crc,
 output reg ready_toggle,output reg [1:0] ready_slot,output reg ready_right,
 output reg [2:0] image_count,current_image,output busy,output reg [3:0] error,output [3:0] debug_state,
 output reg [31:0] debug_local_crc,debug_remote_crc
);
localparam TIME_HZ=CLK_HZ/TIMER_SCALE;
function [159:0] packet;
 input [7:0] kind;input [31:0] session;input [15:0] request_seq;
 input [7:0] image,flags;input [31:0] length,crc;input [7:0] status;
 begin packet={kind,session,request_seq,image,flags,length,crc,status,16'd0};end
endfunction
localparam HELLO_SEND=0,HELLO_WAIT=1,IDLE=2,GET=3,WAIT_BEGIN=4,ARM=5,
 READY=6,RECEIVE=7,ACCEPT=8,TRANSITION=9,COMMIT=10,NACK=11,FAILED=12;
reg [3:0] state;reg send;reg [159:0] message;
assign debug_state=state;
wire tx_busy,got,bad;wire [159:0] incoming;
photo_uart #(.CLK_HZ(CLK_HZ),.PULSE_PAYLOAD(1)) port(.clk(clk),.rst(rst),.rx(uart_rx),.tx(uart_tx),
 .send(send),.message(message),.busy(tx_busy),.received(got),.received_message(incoming),.bad_packet(bad));
wire [7:0] kind=incoming[159:152];wire [31:0] msg_session=incoming[151:120];
wire [15:0] msg_seq=incoming[119:104];
reg [31:0] session,uptime,timer;reg [15:0] request_seq;
reg [2:0] target;reg direction,pending,pending_right;
reg done_seen,end_seen,commit_seen;reg [31:0] expected_crc,received_crc;reg [1:0] retries;
wire matching=msg_session==session && msg_seq==request_seq && incoming[103:96]=={5'd0,target};
assign busy=state!=IDLE && state!=FAILED;
function [2:0] adjacent;
 input [2:0] image,count;input right;
 begin if(count<2)adjacent=0;else if(right)adjacent=image==count-1 ? 0:image+1'b1;
 else adjacent=image==0 ? count-1:image-1'b1;end
endfunction
always @(posedge clk or posedge rst)begin
 if(rst)begin state<=HELLO_SEND;send<=0;message<=0;session<=1;uptime<=1;timer<=0;request_seq<=0;
  target<=0;direction<=1;pending<=0;pending_right<=1;done_seen<=0;end_seen<=0;expected_crc<=0;
  receive_slot<=1;arm_toggle<=0;abort_toggle<=0;ready_toggle<=0;ready_slot<=0;ready_right<=1;
  image_count<=0;current_image<=0;error<=0;retries<=0;commit_seen<=0;
  received_crc<=0;debug_local_crc<=0;debug_remote_crc<=0;end
 else begin
  uptime<=uptime+1'b1;timer<=timer+1'b1;send<=0;
  if(previous || next)begin pending<=1;pending_right<=next;end
  if(got && kind==10)begin
   abort_toggle<=~abort_toggle;state<=HELLO_SEND;session<=uptime;timer<=0;error<=0;
  end else case(state)
   HELLO_SEND:if(!tx_busy && !transition_active)begin
    message<=packet(1,session,0,0,0,FRAME_BYTES,0,0);send<=1;state<=HELLO_WAIT;timer<=0;
   end
   HELLO_WAIT:begin
    if(got && kind==2 && msg_session==session && incoming[23:16]>0 && incoming[23:16]<=6)begin
     image_count<=incoming[18:16];target<=0;direction<=1;request_seq<=request_seq+1'b1;state<=GET;timer<=0;retries<=0;
    end else if(timer>=TIME_HZ)begin state<=HELLO_SEND;timer<=0;end
   end
   IDLE,FAILED:if((pending || previous || next) && image_count!=0)begin
    direction<=(previous || next) ? next:pending_right;
    target<=adjacent(current_image,image_count,(previous || next) ? next:pending_right);
    pending<=0;request_seq<=request_seq+1'b1;retries<=0;error<=0;state<=GET;timer<=0;
   end
   GET:if(!tx_busy)begin
    message<=packet(3,session,request_seq,{5'd0,target},{7'd0,direction},FRAME_BYTES,0,0);
    send<=1;state<=WAIT_BEGIN;timer<=0;done_seen<=0;end_seen<=0;
   end
   WAIT_BEGIN:begin
    if(got && matching && kind==4 && incoming[87:56]==FRAME_BYTES)begin
     // Slot 3 is unused; the current and new transition slots remain locked.
     if(active_slot!=0 && (!transition_active || new_slot!=0))receive_slot<=0;
     else if(active_slot!=1 && (!transition_active || new_slot!=1))receive_slot<=1;
     else receive_slot<=2;
     arm_toggle<=~arm_toggle;state<=ARM;timer<=0;
    end else if(got && matching && kind==11)begin error<=incoming[19:16];state<=FAILED;end
    else if(timer>=64'd45*TIME_HZ)begin error<=1;abort_toggle<=~abort_toggle;session<=uptime;state<=HELLO_SEND;timer<=0;end
   end
   ARM:if(rx_armed)begin state<=READY;timer<=0;end
       else if(timer>=TIME_HZ*2)begin state<=NACK;error<=2;end
   READY:if(!tx_busy)begin
    message<=packet(5,session,request_seq,{5'd0,target},0,FRAME_BYTES,0,0);send<=1;state<=RECEIVE;timer<=0;
   end
   RECEIVE:begin
    if(rx_done)begin done_seen<=1;received_crc<=rx_crc;end
    if(got && matching && kind==6)begin expected_crc<=incoming[55:24];end_seen<=1;end
    if(rx_fault)begin error<=3;state<=NACK;end
    else if(done_seen && end_seen)begin
     // Keep the completed pair across retries and rediscovery for diagnosis.
     debug_local_crc<=received_crc;debug_remote_crc<=expected_crc;
     if(CHECK_FRAME_CRC && received_crc!=expected_crc)begin error<=4;state<=NACK;end
     else begin ready_slot<=receive_slot;ready_right<=direction;ready_toggle<=~ready_toggle;
      commit_seen<=commit_toggle;state<=ACCEPT;timer<=0;end
    end else if(timer>=64'd5*TIME_HZ)begin error<=5;state<=NACK;end
   end
   ACCEPT:if(!tx_busy)begin
    message<=packet(7,session,request_seq,{5'd0,target},0,FRAME_BYTES,received_crc,0);send<=1;state<=TRANSITION;timer<=0;
   end
   TRANSITION:if(commit_toggle!=commit_seen)begin current_image<=target;state<=COMMIT;end
   COMMIT:if(!tx_busy)begin
    message<=packet(8,session,request_seq,{5'd0,target},0,FRAME_BYTES,received_crc,0);send<=1;state<=IDLE;error<=0;timer<=0;
   end
   NACK:if(!tx_busy)begin
    abort_toggle<=~abort_toggle;
    message<=packet(9,session,request_seq,{5'd0,target},0,FRAME_BYTES,received_crc,{4'd0,error});send<=1;
    done_seen<=0;end_seen<=0;timer<=0;
    if(retries<2)begin retries<=retries+1'b1;state<=WAIT_BEGIN;end else state<=FAILED;
   end
   default:state<=HELLO_SEND;
  endcase
 end
end
endmodule

module photo_control_b #(parameter CLK_HZ=100000000,TIMER_SCALE=1,FRAME_BYTES=1843200,CHECK_FRAME_CRC=0,SEND_SOURCE_SIZE=0,SETTINGS_LINK=0,AWARD_CONTROL=0,FLUID=0,AWARD_LIGHTS=0)(
 input award_available,award_scan_complete,
 input clk,rst,uart_rx,output uart_tx,input [2:0] image_count,input media_ready,
 input [1:0] media_slot,input [3:0] media_error,
 input [15:0] media_source_width,media_source_height,
 output reg media_request,output reg [2:0] media_target,output reg media_release,media_cancel,
 output reg [1:0] transmit_slot,output reg start_toggle,abort_toggle,
 output reg display_valid,prefetch_pause,output reg [2:0] display_image,
 output reg [18:0] settings_state,input tx_done,input [31:0] tx_crc,output busy,output reg [3:0] error,output [3:0] debug_state
);

wire tx_busy,got,bad;wire [159:0] incoming;
wire fluid_frame=FLUID && media_target!=6;
wire [31:0] frame_bytes=(AWARD_LIGHTS && media_target==6) || fluid_frame ? 32'd2764800:FRAME_BYTES;
wire request_fluid=FLUID && incoming[98:96]!=6;
wire [31:0] request_bytes=(AWARD_LIGHTS && incoming[98:96]==6) || request_fluid ? 32'd2764800:FRAME_BYTES;
localparam TIME_HZ=CLK_HZ/TIMER_SCALE;
function [159:0] packet;
 input [7:0] kind;input [31:0] session;input [15:0] request_seq;
 input [7:0] image,flags;input [31:0] length,crc;input [7:0] status;
 begin packet={kind,session,request_seq,image,flags,length,crc,status,16'd0};end
endfunction
localparam DISCOVER=0,HELLO_ACK=1,IDLE=2,LOAD=3,BEGIN_SEND=4,WAIT_READY=5,
 SENDING=6,END_SEND=7,WAIT_ACCEPT=8,WAIT_COMMIT=9,ERROR_SEND=10;
reg [3:0] state;reg [31:0] session,timer;reg [15:0] request_seq;
assign debug_state=state;
reg settings_reply,context_reply,cancel_reply;reg [7:0] announced_count;
wire [7:0] catalog=AWARD_CONTROL ? {award_available,award_scan_complete,3'd0,image_count}:{5'd0,image_count};
wire valid_target=incoming[103:96]<image_count || (AWARD_CONTROL && award_available && incoming[103:96]==6);
reg direction;reg [1:0] retries;reg send;reg [159:0] message;reg [31:0] completed_crc;
reg [15:0] source_width,source_height;

photo_uart #(.CLK_HZ(CLK_HZ),.PULSE_PAYLOAD(1)) port(.clk(clk),.rst(rst),.rx(uart_rx),.tx(uart_tx),
 .send(send),.message(message),.busy(tx_busy),.received(got),.received_message(incoming),.bad_packet(bad));
wire [7:0] kind=incoming[159:152];
wire matching=incoming[151:120]==session && incoming[119:104]==request_seq && incoming[103:96]=={5'd0,media_target};
assign busy=state!=IDLE && state!=DISCOVER;
always @(posedge clk or posedge rst)begin
 if(rst)begin announced_count<=0;display_valid<=0;display_image<=0;prefetch_pause<=0;context_reply<=0;cancel_reply<=0;settings_state<={4'd4,4'd4,4'd4,2'd1,2'd1,1'b0,1'b0};settings_reply<=0;state<=DISCOVER;session<=0;request_seq<=0;timer<=0;direction<=1;retries<=0;send<=0;message<=0;
  media_request<=0;media_target<=0;media_release<=0;media_cancel<=0;transmit_slot<=0;start_toggle<=0;abort_toggle<=0;error<=0;completed_crc<=0;
  source_width<=0;source_height<=0;end
 else begin
  timer<=timer+1'b1;send<=0;media_request<=0;
  if(got && kind==19 && incoming[151:120]==session && incoming[23:16]==catalog)announced_count<=incoming[23:16];media_release<=0;media_cancel<=0;
  if(got && kind==1 && incoming[87:56]==FRAME_BYTES && (image_count>0 || (AWARD_CONTROL && award_available)))begin
   session<=incoming[151:120];abort_toggle<=~abort_toggle;media_cancel<=1;state<=HELLO_ACK;timer<=0;error<=0;
  end else if(got && matching && kind==9 && (state==WAIT_READY || state==SENDING || state==WAIT_ACCEPT || state==WAIT_COMMIT))begin
   abort_toggle<=~abort_toggle;timer<=0;
   if(retries<2)begin retries<=retries+1'b1;state<=BEGIN_SEND;end
   else begin media_cancel<=1;error<=4;state<=ERROR_SEND;end
  end else if(SETTINGS_LINK && got && kind==12 && !incoming[42] && incoming[151:120]==session)begin
   settings_state<=incoming[42:24];settings_reply<=1;
  end else if(SETTINGS_LINK && got && incoming[151:120]==session && kind==14)begin
   display_valid<=incoming[89] && (incoming[98:96]<image_count || (AWARD_CONTROL && award_available && incoming[98:96]==6));display_image<=incoming[98:96];
   prefetch_pause<=incoming[88];context_reply<=1;
  end else if(SETTINGS_LINK && got && incoming[151:120]==session && kind==16)begin
   // Cancel only the link transaction; preserve raw SDRAM caches and SD init.
   abort_toggle<=~abort_toggle;media_cancel<=1;state<=IDLE;cancel_reply<=1;timer<=0;
  end else case(state)
   DISCOVER:if(timer>=TIME_HZ && !tx_busy && !send)begin
    message<=packet(10,0,0,0,0,FRAME_BYTES,0,0);send<=1;timer<=0;
   end
   HELLO_ACK:if(!tx_busy && !send)begin
    message<=packet(2,session,0,0,0,FRAME_BYTES,0,catalog);send<=1;announced_count<=catalog;state<=IDLE;timer<=0;
   end
   IDLE:if(SETTINGS_LINK && cancel_reply && !tx_busy && !send)begin
    message<=packet(17,session,0,0,0,0,0,0);send<=1;cancel_reply<=0;
   end else if(SETTINGS_LINK && context_reply && !tx_busy && !send)begin
    message<=packet(15,session,0,{5'd0,display_image},{6'd0,display_valid,prefetch_pause},0,0,0);send<=1;context_reply<=0;
   end else if(SETTINGS_LINK && settings_reply && settings_state[18]==1'b0 && !tx_busy && !send)begin
    message<=packet(13,session,0,0,0,0,{13'd0,settings_state},0);send<=1;settings_reply<=0;
   end else if(got && kind==3 && incoming[151:120]==session && valid_target && incoming[87:56]==request_bytes && incoming[93]==request_fluid && incoming[94]==1'b0 && settings_state[18]==1'b0)begin
    request_seq<=incoming[119:104];media_target<=incoming[98:96];direction<=incoming[88];retries<=0;
    media_request<=1;state<=LOAD;timer<=0;error<=0;
   end else if(catalog!=announced_count && (image_count>0 || (AWARD_CONTROL && award_available)) && timer>=TIME_HZ/10 && !tx_busy && !send)begin
    // Reliable count growth notification; acknowledgement never resets caches.
    message<=packet(18,session,0,0,0,FRAME_BYTES,0,catalog);send<=1;timer<=0;
   end
   LOAD:begin
    if(media_ready)begin
     transmit_slot<=media_slot;source_width<=media_source_width;source_height<=media_source_height;
     state<=BEGIN_SEND;timer<=0;
    end
    else if(media_error!=0)begin error<=media_error;state<=ERROR_SEND;end
    else if(timer>=64'd35*TIME_HZ)begin error<=1;state<=ERROR_SEND;end
   end
   BEGIN_SEND:if(!tx_busy && !send)begin
    // BEGIN does not carry a frame CRC. Flag 7 selects source-size metadata
    // in that field; END/ACCEPT/COMMIT retain their existing CRC semantics.
    message<=packet(4,session,request_seq,{5'd0,media_target},{SEND_SOURCE_SIZE!=0,1'b0,fluid_frame,4'd0,direction},frame_bytes,
      SEND_SOURCE_SIZE ? {source_width,source_height}:32'd0,0);
    send<=1;state<=WAIT_READY;timer<=0;
   end
   WAIT_READY:if(got && matching && kind==5)begin start_toggle<=~start_toggle;state<=SENDING;timer<=0;end
              else if(timer>=64'd5*TIME_HZ)begin error<=2;state<=ERROR_SEND;end
   SENDING:if(tx_done)begin completed_crc<=tx_crc;state<=END_SEND;timer<=0;end
           else if(timer>=64'd5*TIME_HZ)begin abort_toggle<=~abort_toggle;error<=5;state<=ERROR_SEND;end
   END_SEND:if(!tx_busy && !send)begin
    message<=packet(6,session,request_seq,{5'd0,media_target},0,frame_bytes,completed_crc,0);send<=1;state<=WAIT_ACCEPT;timer<=0;
   end
   WAIT_ACCEPT:if(got && matching && kind==7 && (!CHECK_FRAME_CRC || incoming[55:24]==completed_crc))begin state<=WAIT_COMMIT;timer<=0;end
               else if(timer>=64'd5*TIME_HZ)begin error<=6;state<=ERROR_SEND;end
   WAIT_COMMIT:if(got && matching && kind==8 && (!CHECK_FRAME_CRC || incoming[55:24]==completed_crc))begin media_release<=1;state<=IDLE;timer<=0;end
               else if(timer>=64'd5*TIME_HZ)begin error<=7;state<=ERROR_SEND;end
   ERROR_SEND:if(!tx_busy && !send)begin
    message<=packet(11,session,request_seq,{5'd0,media_target},0,frame_bytes,0,{4'd0,error});send<=1;
    media_cancel<=1;abort_toggle<=~abort_toggle;state<=AWARD_CONTROL ? IDLE:DISCOVER;timer<=0;
   end
   default:state<=DISCOVER;
  endcase
 end
end
endmodule
