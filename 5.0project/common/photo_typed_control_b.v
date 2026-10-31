`timescale 1ns/1ps
// Based on the f6 B controller; legacy shared control stays unchanged for A.
module photo_typed_control_b #(parameter TYPED_TEXT=0,CLK_HZ=100000000,TIMER_SCALE=1,FRAME_BYTES=1843200,CHECK_FRAME_CRC=0,SEND_SOURCE_SIZE=0,SETTINGS_LINK=0,AWARD_CONTROL=0,FLUID=0,AWARD_LIGHTS=0,RELIEF_CONTROL=0,TITLE_SD=0,INDEPENDENT_TEXT=0,BOOT_STATUS=0,CONTROL_BAUD=115200)(
 input title_ready,input [4:0] title_length,input [31:0] title_data,output [6+INDEPENDENT_TEXT:0] title_address,
 input award_available,award_scan_complete,relief_available,
 input clk,rst,uart_rx,output uart_tx,input [2:0] image_count,input media_ready,
 input [1:0] media_slot,input [3:0] media_error,
 input [15:0] media_source_width,media_source_height,
 output reg media_request,output reg [2:0] media_target,output reg media_release,media_cancel,
 output reg [1:0] transmit_slot,output reg start_toggle,abort_toggle,
 output reg display_valid,prefetch_pause,output reg [2:0] display_image,
 output reg [18:0] settings_state,input tx_done,input [31:0] tx_crc,output busy,output reg [3:0] error,output [3:0] debug_state,
 output reg timing_begin,timing_ready,timing_send,timing_done,output timing_cancel
,input text_pending,input[159:0] text_message,output reg text_sent,output text_received,output[159:0] text_incoming,output text_boot_ready
,output [31:0] hmi_session
);

reg [6+INDEPENDENT_TEXT:0] title_index;reg title_wait,title_complete,title_read_settle;
assign title_address=title_index;
wire tx_busy,uart_got,bad;reg got;wire [159:0] incoming;
always @(posedge clk or posedge rst)if(rst)got<=0;else got<=uart_got;
wire has_relief=RELIEF_CONTROL && relief_available;
wire fluid_frame=FLUID && media_target<6;
wire [31:0] frame_bytes=(AWARD_LIGHTS && RELIEF_CONTROL && media_target==7) ? 32'd3940352:(AWARD_LIGHTS && media_target>=6) || fluid_frame ? 32'd2764800:FRAME_BYTES;
wire request_fluid=FLUID && incoming[98:96]<6;
wire [31:0] request_bytes=(AWARD_LIGHTS && RELIEF_CONTROL && incoming[103:96]==7) ? 32'd3940352:(AWARD_LIGHTS && incoming[98:96]>=6) || request_fluid ? 32'd2764800:FRAME_BYTES;
localparam TIME_HZ=CLK_HZ/TIMER_SCALE;
function [159:0] packet;
 input [7:0] kind;input [31:0] session;input [15:0] request_seq;
 input [7:0] image,flags;input [31:0] length,crc;input [7:0] status;
 begin packet={kind,session,request_seq,image,flags,length,crc,status,16'd0};end
endfunction
localparam DISCOVER=0,HELLO_ACK=1,IDLE=2,LOAD=3,BEGIN_SEND=4,WAIT_READY=5,
 SENDING=6,END_SEND=7,WAIT_ACCEPT=8,WAIT_COMMIT=9,ERROR_SEND=10;
// One-hot scheduling avoids binary state decoding in the 100MHz packet mux.
reg [10:0] state_flags;
wire [3:0] state={|(state_flags & 11'h700),|(state_flags & 11'h0f0),
                  |(state_flags & 11'h4cc),|(state_flags & 11'h2aa)};
reg [31:0] session,timer_count;reg timer_reset;
wire [31:0] timer=timer_reset ? 32'd0:timer_count;
always @(posedge clk or posedge rst)
 if(rst)timer_count<=0;else if(timer_reset)timer_count<=1;else timer_count<=timer_count+1'b1;
// Predict the next timer value's predicates. Reset flags on exactly the
// same edges as the counter, so no timeout or state transition moves a clock.
// Explicit wrap handling preserves the original 32-bit counter semantics.
reg due_one,due_five,due_load,due_catalog;

assign text_boot_ready=title_complete || (award_scan_complete && !title_ready);
assign text_received=TYPED_TEXT && got;assign text_incoming=incoming;
assign hmi_session=session;reg [15:0] request_seq;
assign debug_state=state;
reg settings_reply,context_reply,cancel_reply;reg [7:0] announced_count;
wire [7:0] catalog=AWARD_CONTROL ? {award_available,award_scan_complete,has_relief,(BOOT_STATUS && title_ready),(BOOT_STATUS && title_complete),image_count}:{5'd0,image_count};
wire valid_target_d=incoming[103:96]<image_count || (AWARD_CONTROL && ((award_available && incoming[103:96]==6) || (has_relief && incoming[103:96]==7)));
wire catalog_present=image_count>0 || (AWARD_CONTROL && (award_available || has_relief)) || (BOOT_STATUS && award_scan_complete);
reg valid_target,display_target_q,catalog_changed_q,hello_allowed_q;
reg hello_command_q,settings_command_q,context_command_q,cancel_command_q;
reg send;reg tx_idle_q;
always @(posedge clk or posedge rst)if(rst)tx_idle_q<=0;else tx_idle_q<=!tx_busy && !send;
reg direction;reg [1:0] retries;reg [159:0] message;reg [31:0] completed_crc;
reg [15:0] source_width,source_height;

photo_uart #(.PAYLOAD_BYTES(18),.BAUD(CONTROL_BAUD),.CLK_HZ(CLK_HZ),.PULSE_PAYLOAD(1)) port(.clk(clk),.rst(rst),.rx(uart_rx),.tx(uart_tx),
 .send(send),.message(message),.busy(tx_busy),.received(uart_got),.received_message(incoming),.bad_packet(bad));
wire [7:0] kind=incoming[159:152];
// Decode the completed payload during the UART's delayed publication strobe
// to shorten the one-hot controller enables.
reg [34:0] kind_match_q;wire[34:0] kind_decode_d;genvar opcode;
generate for(opcode=0;opcode<35;opcode=opcode+1)begin:kind_decode
 assign kind_decode_d[opcode]=kind==opcode;
end endgenerate
always @(posedge clk or posedge rst)
 if(rst)kind_match_q<=0;else kind_match_q<=kind_decode_d;

// Payload settles before the delayed received strobe. Compare once,
// then fan out the registered predicates instead of repeating 32-bit trees.
reg session_match_q,matching_q,hello_match_q;
wire session_matches=session_match_q;
wire matching=1'b1;
always @(posedge clk or posedge rst)begin
 if(rst)begin session_match_q<=0;matching_q<=0;hello_match_q<=0;end
 else begin
  session_match_q<=incoming[151:120]==session;
  matching_q<=incoming[151:120]==session && incoming[119:104]==request_seq && incoming[103:96]=={5'd0,media_target};
  // PULSE_PAYLOAD settles before the delayed received strobe.
  // Keep the wide HELLO-size decode out of every FSM destination enable.
  hello_match_q<=kind_match_q[1] && incoming[87:56]==FRAME_BYTES;
 end
end
// Consume UART publication one clock later, using predicates sampled with
// its original strobe. This preserves the packet's catalogue snapshot while
// cutting live count/availability comparisons out of the packet-RAM enables.
always @(posedge clk or posedge rst)begin
 if(rst)begin valid_target<=0;display_target_q<=0;catalog_changed_q<=0;hello_allowed_q<=0;
  hello_command_q<=0;settings_command_q<=0;context_command_q<=0;cancel_command_q<=0;end
 else begin
  valid_target<=valid_target_d;
  display_target_q<=incoming[89] && (incoming[98:96]<image_count || (AWARD_CONTROL && ((award_available && incoming[98:96]==6) || (has_relief && incoming[98:96]==7))));
  catalog_changed_q<=catalog!=announced_count && catalog_present;
  hello_allowed_q<=hello_match_q && catalog_present;
  hello_command_q<=uart_got && hello_match_q && catalog_present;
  settings_command_q<=SETTINGS_LINK && uart_got && kind_match_q[12] && !incoming[42] && session_matches;
  context_command_q<=SETTINGS_LINK && uart_got && session_matches && kind_match_q[14];
  cancel_command_q<=SETTINGS_LINK && uart_got && session_matches && kind_match_q[16];
 end
end
assign timing_cancel=media_cancel || error!=0 || (got && matching && kind_match_q[9]);
assign busy=!state_flags[IDLE] && !state_flags[DISCOVER];
always @(posedge clk or posedge rst)begin
 if(rst)begin text_sent<=0;title_index<=0;title_wait<=0;title_complete<=0;title_read_settle<=0;announced_count<=0;display_valid<=0;display_image<=0;prefetch_pause<=0;context_reply<=0;cancel_reply<=0;settings_state<={4'd4,4'd4,4'd4,2'd1,2'd1,1'b0,1'b0};settings_reply<=0;state_flags<=11'd1<<DISCOVER;session<=0;request_seq<=0;timer_reset<=1;due_one<=TIME_HZ==0;due_five<=0;due_load<=0;due_catalog<=TIME_HZ/10==0;direction<=1;retries<=0;send<=0;message<=0;
  media_request<=0;media_target<=0;media_release<=0;media_cancel<=0;transmit_slot<=0;start_toggle<=0;abort_toggle<=0;error<=0;completed_crc<=0;
  source_width<=0;source_height<=0;timing_begin<=0;timing_ready<=0;timing_send<=0;timing_done<=0;end
 else begin
  
  due_one<=timer_reset ? TIME_HZ<=1:TIME_HZ==0 || (timer_count>=TIME_HZ-1 && !(&timer_count));
  due_five<=0;
  due_load<=0;
  due_catalog<=timer_reset ? TIME_HZ/10<=1:TIME_HZ/10==0 || (timer_count>=TIME_HZ/10-1 && !(&timer_count));
  text_sent<=0;timer_reset<=0;send<=0;media_request<=0;title_read_settle<=0;
  if(TITLE_SD && got && kind_match_q[34] && session_matches &&
     incoming[119:112]==title_index && title_wait)begin
   title_wait<=0;title_read_settle<=1;if(title_index==(INDEPENDENT_TEXT ? 255:127))title_complete<=1;else title_index<=title_index+1'b1;
  end
  timing_begin<=0;timing_ready<=0;timing_send<=0;timing_done<=0;
  if(got && kind_match_q[19] && session_matches && incoming[23:16]==catalog)announced_count<=incoming[23:16];media_release<=0;media_cancel<=0;
  if(hello_command_q)begin
   title_index<=0;title_wait<=0;title_complete<=0;session<=incoming[151:120];abort_toggle<=~abort_toggle;media_cancel<=1;state_flags<=11'd1<<HELLO_ACK;timer_reset<=1;due_one<=TIME_HZ==0;due_five<=0;due_load<=0;due_catalog<=TIME_HZ/10==0;error<=0;
  end else if(1'b0 && (state_flags[WAIT_READY] || state_flags[SENDING] || state_flags[WAIT_ACCEPT] || state_flags[WAIT_COMMIT]))begin
   abort_toggle<=~abort_toggle;timer_reset<=1;due_one<=TIME_HZ==0;due_five<=0;due_load<=0;due_catalog<=TIME_HZ/10==0;
   if(retries<2)begin retries<=0;state_flags<=11'd1<<BEGIN_SEND;end
   else begin media_cancel<=1;error<=4;state_flags<=11'd1<<ERROR_SEND;end
  end else if(settings_command_q)begin
   // The accepted command requires bit 18 to be zero. Express that
   // invariant explicitly so it does not become a programmable mode flop.
   settings_state<={1'b0,incoming[41:24]};settings_reply<=1;
  end else if(context_command_q)begin
   display_valid<=display_target_q;display_image<=incoming[98:96];
   prefetch_pause<=incoming[88];context_reply<=1;
  end else if(cancel_command_q)begin
   // Cancel only the link transaction; preserve raw SDRAM caches and SD init.
   abort_toggle<=~abort_toggle;media_cancel<=1;state_flags<=11'd1<<IDLE;cancel_reply<=1;timer_reset<=1;due_one<=TIME_HZ==0;due_five<=0;due_load<=0;due_catalog<=TIME_HZ/10==0;
  end else (* parallel_case *) case(1'b1)
   state_flags[DISCOVER]:if(due_one && tx_idle_q && !send)begin
    message<=packet(10,0,0,0,0,FRAME_BYTES,0,0);send<=1;timer_reset<=1;due_one<=TIME_HZ==0;due_five<=0;due_load<=0;due_catalog<=TIME_HZ/10==0;
   end
   state_flags[HELLO_ACK]:if(tx_idle_q && !send)begin
    message<=packet(2,session,0,0,0,FRAME_BYTES,0,catalog);send<=1;announced_count<=catalog;state_flags<=11'd1<<IDLE;timer_reset<=1;due_one<=TIME_HZ==0;due_five<=0;due_load<=0;due_catalog<=TIME_HZ/10==0;
   end
   state_flags[IDLE]:if(SETTINGS_LINK && cancel_reply && tx_idle_q && !send)begin
    message<=packet(17,session,0,0,0,0,0,0);send<=1;cancel_reply<=0;
   end else if(SETTINGS_LINK && context_reply && tx_idle_q && !send)begin
    message<=packet(15,session,0,{5'd0,display_image},{6'd0,display_valid,prefetch_pause},0,0,0);send<=1;context_reply<=0;
   end else if(SETTINGS_LINK && settings_reply && settings_state[18]==1'b0 && tx_idle_q && !send)begin
    message<=packet(13,session,0,0,0,0,{13'd0,settings_state},0);send<=1;settings_reply<=0;
   end else if(TYPED_TEXT && text_pending && tx_idle_q && !send && !got)begin
    message<=text_message;send<=1;text_sent<=1;
   end else if(got && kind_match_q[3] && session_matches && valid_target && incoming[87:56]==request_bytes && incoming[93]==request_fluid && incoming[94]==1'b0 && settings_state[18]==1'b0)begin
    request_seq<=incoming[119:104];media_target<=incoming[98:96];direction<=incoming[88];retries<=0;
    media_request<=1;state_flags<=11'd1<<LOAD;timer_reset<=1;due_one<=TIME_HZ==0;due_five<=0;due_load<=0;due_catalog<=TIME_HZ/10==0;error<=0;timing_begin<=1;
   end else if(catalog_changed_q && due_catalog && tx_idle_q && !send)begin
    // Reliable count growth notification; acknowledgement never resets caches.
    message<=packet(18,session,0,0,0,FRAME_BYTES,0,catalog);send<=1;timer_reset<=1;due_one<=TIME_HZ==0;due_five<=0;due_load<=0;due_catalog<=TIME_HZ/10==0;
   end else if(TITLE_SD && title_ready && !title_complete && !title_read_settle && !(got && kind_match_q[34]) && (!title_wait || due_one) && tx_idle_q && !send)begin
    message<={8'd33,session,{{(1-INDEPENDENT_TEXT){1'b0}},title_index},{3'd0,title_length},title_data,72'd0};
    send<=1;title_wait<=1;timer_reset<=1;due_one<=TIME_HZ==0;due_five<=0;due_load<=0;due_catalog<=TIME_HZ/10==0;
   end
   state_flags[LOAD]:begin
    if(media_ready)begin
     timing_ready<=1;
     transmit_slot<=media_slot;source_width<=media_source_width;source_height<=media_source_height;
     state_flags<=11'd1<<BEGIN_SEND;timer_reset<=1;due_one<=TIME_HZ==0;due_five<=0;due_load<=0;due_catalog<=TIME_HZ/10==0;
    end
    else if(1'b0)begin error<=media_error;state_flags<=11'd1<<ERROR_SEND;end
    else if(due_load)begin error<=1;state_flags<=11'd1<<ERROR_SEND;end
   end
   state_flags[BEGIN_SEND]:if(tx_idle_q && !send)begin
    // BEGIN does not carry a frame CRC. Flag 7 selects source-size metadata
    // in that field; END/ACCEPT/COMMIT retain their existing CRC semantics.
    message<=packet(4,session,request_seq,{5'd0,media_target},{SEND_SOURCE_SIZE!=0,1'b0,fluid_frame,4'd0,direction},frame_bytes,
      SEND_SOURCE_SIZE ? {source_width,source_height}:32'd0,0);
    send<=1;state_flags<=11'd1<<WAIT_READY;timer_reset<=1;due_one<=TIME_HZ==0;due_five<=0;due_load<=0;due_catalog<=TIME_HZ/10==0;
   end
   state_flags[WAIT_READY]:if(got && matching && kind_match_q[5])begin start_toggle<=~start_toggle;state_flags<=11'd1<<SENDING;timer_reset<=1;due_one<=TIME_HZ==0;due_five<=0;due_load<=0;due_catalog<=TIME_HZ/10==0;timing_send<=1;end
              else if(due_five)begin error<=2;state_flags<=11'd1<<ERROR_SEND;end
   state_flags[SENDING]:if(tx_done)begin completed_crc<=tx_crc;state_flags<=11'd1<<END_SEND;timer_reset<=1;due_one<=TIME_HZ==0;due_five<=0;due_load<=0;due_catalog<=TIME_HZ/10==0;timing_done<=1;end
           else if(due_five)begin abort_toggle<=~abort_toggle;error<=5;state_flags<=11'd1<<ERROR_SEND;end
   state_flags[END_SEND]:if(tx_idle_q && !send)begin
    message<=packet(6,session,request_seq,{5'd0,media_target},0,frame_bytes,completed_crc,0);send<=1;state_flags<=11'd1<<WAIT_ACCEPT;timer_reset<=1;due_one<=TIME_HZ==0;due_five<=0;due_load<=0;due_catalog<=TIME_HZ/10==0;
   end
   state_flags[WAIT_ACCEPT]:if(got && matching && kind_match_q[7] && (!CHECK_FRAME_CRC || incoming[55:24]==completed_crc))begin state_flags<=11'd1<<WAIT_COMMIT;timer_reset<=1;due_one<=TIME_HZ==0;due_five<=0;due_load<=0;due_catalog<=TIME_HZ/10==0;end
               else if(due_five)begin error<=6;state_flags<=11'd1<<ERROR_SEND;end
   state_flags[WAIT_COMMIT]:if(got && matching && kind_match_q[8] && (!CHECK_FRAME_CRC || incoming[55:24]==completed_crc))begin media_release<=1;state_flags<=11'd1<<IDLE;timer_reset<=1;due_one<=TIME_HZ==0;due_five<=0;due_load<=0;due_catalog<=TIME_HZ/10==0;end
               else if(due_five)begin error<=7;state_flags<=11'd1<<ERROR_SEND;end
   state_flags[ERROR_SEND]:if(tx_idle_q && !send)begin
    message<=packet(11,session,request_seq,{5'd0,media_target},0,frame_bytes,0,{4'd0,error});send<=1;
    media_cancel<=1;abort_toggle<=~abort_toggle;state_flags<=11'd1<<(AWARD_CONTROL ? IDLE:DISCOVER);timer_reset<=1;due_one<=TIME_HZ==0;due_five<=0;due_load<=0;due_catalog<=TIME_HZ/10==0;
   end
   default:state_flags<=11'd1<<DISCOVER;
  endcase
 end
end
endmodule
