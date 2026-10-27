`timescale 1ns/1ps
module tb_b_deadlines;
reg clk=0;always #5 clk=~clk;reg rst=1,got=0;
reg [159:0] incoming=0;reg media_ready=0,tx_done=0,media_error=0;
wire [31:0] session;
photo_control_b #(.CLK_HZ(1000000),.TIMER_SCALE(10000),.TITLE_SD(1),.CHECK_FRAME_CRC(1),.SEND_SOURCE_SIZE(1),.SETTINGS_LINK(1),.AWARD_CONTROL(1),.FLUID(1),.AWARD_LIGHTS(1),.RELIEF_CONTROL(1)) dut(
 .clk(clk),.rst(rst),.uart_rx(1'b1),.uart_tx(),.title_ready(1'b0),.title_length(5'd0),.title_data(32'd0),.title_address(),
 .image_count(3'd6),.award_available(1'b1),.award_scan_complete(1'b1),.relief_available(1'b1),.display_valid(),.display_image(),.prefetch_pause(),.settings_state(),
 .media_ready(media_ready),.media_slot(2'd1),.media_error({3'd0,media_error}),.media_source_width(16'd1280),.media_source_height(16'd720),.media_request(),.media_target(),.media_release(),.media_cancel(),
 .transmit_slot(),.start_toggle(),.abort_toggle(),.tx_done(tx_done),.tx_crc(32'h12345678),.busy(),.error(),.debug_state(),.timing_begin(),.timing_ready(),.timing_send(),.timing_done(),.timing_cancel(),.hmi_session(session));
photo_control_b_before #(.CLK_HZ(1000000),.TIMER_SCALE(10000),.TITLE_SD(1),.CHECK_FRAME_CRC(1),.SEND_SOURCE_SIZE(1),.SETTINGS_LINK(1),.AWARD_CONTROL(1),.FLUID(1),.AWARD_LIGHTS(1),.RELIEF_CONTROL(1)) reference(
 .clk(clk),.rst(rst),.uart_rx(1'b1),.uart_tx(),.title_ready(1'b0),.title_length(5'd0),.title_data(32'd0),.title_address(),
 .image_count(3'd6),.award_available(1'b1),.award_scan_complete(1'b1),.relief_available(1'b1),.display_valid(),.display_image(),.prefetch_pause(),.settings_state(),
 .media_ready(media_ready),.media_slot(2'd1),.media_error({3'd0,media_error}),.media_source_width(16'd1280),.media_source_height(16'd720),.media_request(),.media_target(),.media_release(),.media_cancel(),
 .transmit_slot(),.start_toggle(),.abort_toggle(),.tx_done(tx_done),.tx_crc(32'h12345678),.busy(),.error(),.debug_state(),.timing_begin(),.timing_ready(),.timing_send(),.timing_done(),.timing_cancel());
integer n=0,checks=0;reg [31:0] rng=32'had332bb5;
initial begin force dut.got=got;force reference.got=got;force dut.incoming=incoming;force reference.incoming=incoming;end
always @(posedge clk)if(!rst)begin
 if({dut.due_one,dut.due_five,dut.due_load,dut.due_catalog}!=={dut.timer>=100,dut.timer>=500,dut.timer>=3500,dut.timer>=10})$fatal(1,"timeout prediction timer=%h",dut.timer);
 #1;
 if({dut.state,dut.timer,dut.session,dut.request_seq,dut.send,dut.message,dut.error,dut.media_request,dut.media_cancel,dut.start_toggle,dut.abort_toggle}!==
    {reference.state,reference.timer,reference.session,reference.request_seq,reference.send,reference.message,reference.error,reference.media_request,reference.media_cancel,reference.start_toggle,reference.abort_toggle})$fatal(1,"B controller changed cycle %d timer=%h/%h state=%h/%h",n,dut.timer,reference.timer,dut.state,reference.state);
 checks=checks+1;
end
task send;
 input [7:0] kind,flags;input [31:0] value;
 begin
  @(negedge clk);incoming={kind,(kind==1 ? 32'h87654321:session),dut.request_seq,{5'd0,dut.media_target},flags,32'd2764800,value,8'd0,16'd0};
  repeat(3)@(negedge clk);got=1;@(negedge clk);got=0;
 end
endtask
initial begin
 repeat(20)@(negedge clk);rst=0;send(1,0,0);
 for(n=0;n<50000;n=n+1)begin
  @(negedge clk);rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
  media_ready=rng[3:0]==0;tx_done=rng[5:4]==0;media_error=rng[9:0]==0;
  if(n%397==0)send(1,0,0);
  else if(n%31==0)send(12,0,{13'd0,rng[18:0]&19'h3ffff});
  else if(n%41==0)send(14,0,0);
  else if(n%59==0)send(3,8'h20,0);
  else if(n%61==0)send(5,0,0);
  else if(n%67==0)send(7,0,32'h12345678);
  else if(n%71==0)send(8,0,32'h12345678);
  else if(n%79==0)send(9,0,0);
  else if(n%83==0)send(16,0,0);
 end
 // Keep LOAD pending long enough to cross all four threshold boundaries.
 @(negedge clk);dut.state_flags=11'd1<<3;reference.state=3;dut.timer_count=0;dut.timer_reset=1;reference.timer=0;
 dut.due_one=0;dut.due_five=0;dut.due_load=0;dut.due_catalog=0;
 media_ready=0;tx_done=0;media_error=0;got=0;repeat(3600)@(negedge clk);
 // Coherently seed the counter/predicates near rollover, then let the real
 // controller advance through ffffffff -> 0 without any forced clock edges.
 @(negedge clk);force dut.tx_idle_q=0;force reference.tx_idle_q=0;
 dut.timer_count=32'hfffffffc;dut.timer_reset=0;reference.timer=32'hfffffffc;
 dut.due_one=1;dut.due_five=1;dut.due_load=1;dut.due_catalog=1;
 repeat(12)@(negedge clk);release dut.tx_idle_q;release reference.tx_idle_q;
 repeat(5000)@(negedge clk);
 $display("PASS B deadline pipeline: %0d clocks exactly match accepted UART controller, all threshold predicates, timeout/reset priority, transaction/settings/cancel traffic and 32-bit wrap",checks);$finish;
end
initial begin #2000000;$fatal(1,"timeout");end
endmodule
