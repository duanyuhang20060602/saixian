`timescale 1ns/1ps
// Real photo_uart on both wire ends. Force only local controller state/timer
// to place a reconnect exactly on the CRC completion edge; RX is never forced.
module tb;
localparam CLK_HZ=806400,DIV=7;
reg clk=0;always #5 clk=~clk;
reg rst=1,peer_send=0;reg [159:0] peer_message=0;
wire dut_tx,peer_tx,peer_busy,peer_received,peer_bad;
wire [159:0] peer_incoming;
wire [2:0] image_count;wire [3:0] error;
photo_uart #(.CLK_HZ(CLK_HZ),.PULSE_PAYLOAD(1)) peer(.clk(clk),.rst(rst),.rx(dut_tx),.tx(peer_tx),.send(peer_send),.message(peer_message),.busy(peer_busy),.received(peer_received),.received_message(peer_incoming),.bad_packet(peer_bad));
photo_cached_control_a #(.CLK_HZ(CLK_HZ),.SETTINGS_LINK(0),.AWARD_CONTROL(0)) dut(
 .clk(clk),.rst(rst),.uart_rx(peer_tx),.uart_tx(dut_tx),.previous(1'b0),.next(1'b0),
 .settings_mode(1'b0),.settings_state(19'd0),.award_toggle(1'b0),.relief_toggle(1'b0),
 .active_slot(2'd0),.new_slot(2'd0),.transition_active(1'b0),.commit_toggle(1'b0),
 .rx_armed(1'b0),.rx_done(1'b0),.rx_fault(1'b0),.rx_crc(32'd0),
 .thumbnail_read_busy(1'b0),.thumbnail_read_slot(2'd0),.image_count(image_count),.error(error));
function [159:0] packet;
 input[7:0]kind;input[31:0]session;input[15:0]seq;input[7:0]image,flags;input[31:0]length;input[7:0]status;
 begin packet={kind,session,seq,image,flags,length,32'd0,status,16'd0};end
endfunction
integer stable_cycles=0,minimum_stable=999999,received_count=0,bad_count=0,epoch_overlap=0;
reg[159:0]previous_payload=0;
always @(posedge clk)begin
 if(rst)begin previous_payload<=0;stable_cycles<=0;received_count<=0;bad_count<=0;epoch_overlap<=0;end
 else begin
  previous_payload<=dut.incoming;
  if(dut.incoming!==previous_payload)stable_cycles<=0;else stable_cycles<=stable_cycles+1;
  if(dut.bad)bad_count<=bad_count+1;
  if(dut.got)begin
   if(dut.kind_match_q!==(dut.kind<19 ? (19'd1<<dut.kind):19'd0))$fatal(1,"packet-kind predicate stale on got");
   received_count<=received_count+1;
   if(stable_cycles<19*DIV)$fatal(1,"payload not stable through CRC: %0d",stable_cycles);
   if(stable_cycles<minimum_stable)minimum_stable=stable_cycles;
   if(dut.session_changed && dut.session_match_q)epoch_overlap<=epoch_overlap+1;
   if(!dut.session_changed)begin
    if(dut.session_match_q!==(dut.incoming[151:120]==dut.session))$fatal(1,"session predicate stale on got");
    if(dut.transaction_match_q!==((dut.incoming[119:104]==dut.request_seq)&&(dut.incoming[103:96]=={5'd0,dut.target})))$fatal(1,"transaction predicate stale on got");
    if(dut.begin_fields_match_q!==((dut.incoming[87:56]==dut.frame_bytes)&&(dut.incoming[94]==0)&&(dut.incoming[93]==dut.receive_fluid)))$fatal(1,"BEGIN fields stale on got");
   end
  end
 end
end
task send_packet;input[159:0]value;input corrupt;begin
 wait(!peer_busy);@(negedge clk);peer_message=value;peer_send=1;
 @(negedge clk);peer_send=0;wait(peer_busy);
 if(corrupt)begin
  wait(peer.tx_pos==21);@(negedge clk);
  if(peer.tx_crc==0)$fatal(1,"bad CRC fixture happens to be valid");
  force peer.tx_crc=16'd0;
 end
 wait(!peer_busy);if(corrupt)release peer.tx_crc;
 repeat(8)@(negedge clk);
end endtask
reg[255:0] kind_coverage=0;
always @(posedge clk)if(rst)kind_coverage<=0;else if(dut.got)kind_coverage[dut.kind]<=1;
reg[31:0]new_session;integer accepted_before,bad_before,test_kind;
initial begin
 repeat(10)@(negedge clk);rst=0;repeat(20)@(negedge clk);
 force dut.state_flags=16'h1000;@(negedge clk);release dut.state_flags;
 // Reconnect is deliberately committed on the same edge RX publishes got.
 fork
  send_packet(packet(18,32'd1,0,0,0,0,1),0);
  begin
   wait(dut.port.rx_pos==23 && dut.port.byte_valid);@(negedge clk);
   // Position the complete derived timer state, as if the counter reached
   // the positioned count naturally. Lookahead equivalence is proved separately.
   force dut.timer_count=32'd806400;
   force dut.timeout1_q=(32'd806400>=dut.TIME_HZ);force dut.timeout2_q=(32'd806400>=dut.TIME_HZ*2);
   force dut.timeout5_q=(32'd806400>=64'd5*dut.TIME_HZ);force dut.timeout40_q=(32'd806400>=64'd40*dut.TIME_HZ);force dut.timeout45_q=(32'd806400>=64'd45*dut.TIME_HZ);
   @(posedge clk);#1;
   if(dut.session==1 || !dut.session_changed)$fatal(1,"reconnect edge not exercised");
   @(negedge clk);release dut.timer_count;
   release dut.timeout1_q;release dut.timeout2_q;release dut.timeout5_q;release dut.timeout40_q;release dut.timeout45_q;
  end
 join
 if(image_count!=0 || epoch_overlap!=1)$fatal(1,"old-session COUNT accepted at reconnect boundary count=%0d overlap=%0d",image_count,epoch_overlap);
 new_session=dut.session;
 send_packet(packet(18,new_session,0,0,0,0,2),0);
 if(image_count!=2)$fatal(1,"new-session COUNT rejected after settling");
 send_packet(packet(18,32'd1,0,0,0,0,3),0);
 if(image_count!=2)$fatal(1,"stale-session COUNT accepted");
 force dut.state_flags=16'h0010;@(negedge clk);release dut.state_flags;
 send_packet(packet(11,new_session,16'd123,0,0,0,9),0);
 if(error!=0 || !dut.state_flags[4])$fatal(1,"wrong-transaction ERROR accepted");
 send_packet(packet(11,new_session,0,1,0,0,9),0);
 if(error!=0 || !dut.state_flags[4])$fatal(1,"wrong-image ERROR accepted");
 send_packet(packet(4,new_session,0,0,8'h40,1843200,0),0);
 if(dut.arm_toggle || !dut.state_flags[4])$fatal(1,"wrong-flags BEGIN accepted");
 send_packet(packet(4,new_session,0,0,0,42,0),0);
 if(dut.arm_toggle || !dut.state_flags[4])$fatal(1,"wrong-length BEGIN accepted");
 accepted_before=received_count;bad_before=bad_count;
 send_packet(packet(4,new_session,0,0,0,1843200,0),1);
 if(received_count!=accepted_before || bad_count!=bad_before+1 || dut.arm_toggle)$fatal(1,"bad CRC bypassed predicate gating");
 send_packet(packet(4,new_session,0,0,0,1843200,0),0);
 if(!dut.arm_toggle || !dut.state_flags[5])$fatal(1,"valid BEGIN rejected");
 for(test_kind=0;test_kind<256;test_kind=test_kind+1)send_packet(packet(test_kind[7:0],32'd0,0,0,0,0,0),0);
 if(kind_coverage!=={256{1'b1}})$fatal(1,"packet-kind coverage incomplete");
 $display("PASS UART contract: all 256 packet kinds, real serial CRC payload stable >=%0d clocks; reconnect/got collision masks stale session; new session, seq/id/length predicates and bad CRC gating",minimum_stable);$finish;
end
initial begin #20000000;$fatal(1,"UART contract timeout state=%0d pos=%0d",dut.state,dut.port.rx_pos);end
endmodule
