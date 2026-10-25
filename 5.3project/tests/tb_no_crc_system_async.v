`timescale 1ns/1ps
// Asynchronous A/B clocks: A 14ns, B 10ns, link 160ns; UART bit times 98ns/100ns.
// Real UART codecs, both transaction controllers, both link adapters and
// the real transition controller. SDRAM application interfaces are modeled.
module tb_no_crc_system_async;
reg clk=0,b_clk=0,link_clk=0;always #7 clk=~clk;always #5 b_clk=~b_clk;always #80 link_clk=~link_clk;
reg rst_a=1,rst_b=1,previous=0,next=0;
wire a_tx,b_tx,arm_t,abort_a_t,start_t,abort_b_t;
wire [1:0] receive_slot,active_slot,new_slot,ready_slot,transmit_slot;
wire transition_active,commit_toggle,ready_toggle,ready_right;
wire [2:0] image_count,current;wire busy_a,busy_b;wire [3:0] error_a,error_b;
wire armed,done_link,fault;wire [31:0] rx_crc,tx_crc;
wire arm,abort_a,start,abort_b,done_a,done_b;
reg done_a_t=0,done_b_t=0;
reg [31:0] golden_crc[0:5];
initial $readmemh("tests/crc_reference.hex",golden_crc);
photo_event_sync aarm(link_clk,rst_a,arm_t,arm);
photo_event_sync aabort(link_clk,rst_a,abort_a_t,abort_a);
photo_event_sync bstart(link_clk,rst_b,start_t,start);
photo_event_sync babort(link_clk,rst_b,abort_b_t,abort_b);
photo_event_sync adone(clk,rst_a,done_a_t,done_a);
photo_event_sync bdone(b_clk,rst_b,done_b_t,done_b);
wire media_request,media_release,media_cancel;wire [2:0] target;
reg media_ready=0;reg [1:0] media_slot=0;reg [7:0] media_delay=0;reg pending_media=0;
reg [2:0] locked_image=0;
always @(posedge b_clk)begin
 if(rst_b || media_cancel)begin media_ready<=0;pending_media<=0;end
 else begin
  if(media_release)media_ready<=0;
  if(media_request)begin
   if(media_ready)$fatal(1,"request overwrites locked media slot");
   pending_media<=1;media_delay<=20;locked_image<=target;
  end
  if(pending_media)begin
   if(media_delay!=0)media_delay<=media_delay-1'b1;
   else begin media_ready<=1;pending_media<=0;media_slot<=locked_image%3;end
  end
 end
end
photo_control_a #(.CLK_HZ(806400),.TIMER_SCALE(100),.FRAME_BYTES(64)) a(.clk(clk),.rst(rst_a),.uart_rx(b_tx),.uart_tx(a_tx),
 .previous(previous),.next(next),.active_slot(active_slot),.new_slot(new_slot),.transition_active(transition_active),.commit_toggle(commit_toggle),
 .receive_slot(receive_slot),.arm_toggle(arm_t),.abort_toggle(abort_a_t),.rx_armed(armed),.rx_done(done_a),
 .rx_fault(fault),.rx_crc(rx_crc),.ready_toggle(ready_toggle),.ready_slot(ready_slot),.ready_right(ready_right),
 .image_count(image_count),.current_image(current),.busy(busy_a),.error(error_a));
photo_control_b #(.CLK_HZ(1152000),.TIMER_SCALE(100),.FRAME_BYTES(64)) b(.clk(b_clk),.rst(rst_b),.uart_rx(a_tx),.uart_tx(b_tx),
 .image_count(3'd6),.media_ready(media_ready),.media_slot(media_slot),.media_error(4'd0),
 .media_request(media_request),.media_target(target),.media_release(media_release),.media_cancel(media_cancel),
 .transmit_slot(transmit_slot),.start_toggle(start_t),.abort_toggle(abort_b_t),.tx_done(done_b),.tx_crc(tx_crc),.busy(busy_b),.error(error_b));
reg [8:0] frame_div=0;wire frame_tick=frame_div==399;
always @(posedge clk)if(rst_a)frame_div<=0;else frame_div<=frame_tick ? 0:frame_div+1'b1;
wire display_valid;wire [2:0] effect;wire [10:0] offset;wire [5:0] darkness;
saixian_transition transition(.clk(clk),.rst(rst_a),.frame_tick(frame_tick),.frame_ready_toggle(ready_toggle),
 .ready_buf_idx(ready_slot),.ready_slide_right(ready_right),.active_buf_idx(active_slot),.slide_new_buf_idx(new_slot),
 .frame_commit_toggle(commit_toggle),.display_valid(display_valid),.transition_active(transition_active),
 .transition_mode(effect),.slide_offset(offset),.slide_right(),.transition_level(darkness));
wire read_req,read_en,link_valid,link_sof,link_eof,ready,sent,tx_busy;
wire [15:0] link_data;reg [31:0] read_data=0;reg [1:0] rd_ack_pipe=0;
reg [4:0] word_index=0;
function [15:0] pattern;
 input integer p;input [2:0] image;
 begin pattern=((p*16'h1237)^(16'h8291+image*16'h317));end
endfunction
always @(posedge link_clk)begin
 if(rst_b)begin rd_ack_pipe<=0;word_index<=0;read_data<=0;end
 else begin
  rd_ack_pipe<={rd_ack_pipe[0],read_req};
  if(read_req)word_index<=0;
  if(read_en)begin read_data<={pattern(word_index*2,locked_image),pattern(word_index*2+1,locked_image)};word_index<=word_index+1'b1;end
 end
end
photo_link_sender #(.FRAME_PIXELS(32)) sender(.clk(link_clk),.rst(rst_b),.start(start),.abort(abort_b),
 .data(read_data),.empty(1'b0),.read_ack(rd_ack_pipe[1]),.link_ready(ready),.read_req(read_req),.read_en(read_en),
 .link_data(link_data),.link_valid(link_valid),.link_sof(link_sof),.link_eof(link_eof),.done(sent),.busy(tx_busy),.frame_crc(tx_crc));
wire write_req,write_en;wire [31:0] write_data;reg [1:0] wr_ack_pipe=0;reg full=0,finish_t=0;
integer write_index=0,transfers=0,corrupt_attempts=0;
reg [4:0] stall_count=0;reg corrupt=0;
wire [15:0] rx_data=link_data ^ (corrupt && link_valid && link_sof ? 16'h0001:16'h0000);
always @(posedge link_clk)begin
 if(rst_a)begin wr_ack_pipe<=0;write_index<=0;finish_t<=0;stall_count<=0;full<=0;done_a_t<=0;end
 else begin
  stall_count<=stall_count+1'b1;full<=stall_count[2:0]==3;
  wr_ack_pipe<={wr_ack_pipe[0],write_req};
  if(write_req)write_index<=0;
  if(write_en && !full)begin
   if(receive_slot==active_slot && display_valid)$fatal(1,"write into active display slot");
   if(write_data!={pattern(write_index*2,locked_image) ^ (corrupt && write_index==0 ? 16'h1:16'h0),pattern(write_index*2+1,locked_image)})$fatal(1,"word/pixel order mismatch");
   write_index<=write_index+1;
   if(write_index==15)begin finish_t<=~finish_t;transfers<=transfers+1;end
  end
  if(done_link)done_a_t<=~done_a_t;
 end
 if(rst_b)done_b_t<=0;else if(sent)begin
  if(tx_crc!==32'd0)$fatal(1,"CRC32 differs from independent Python/zlib reference");
  done_b_t<=~done_b_t;
 end
end
photo_link_receiver #(.FRAME_PIXELS(32)) receiver(.clk(link_clk),.rst(rst_a),.arm(arm),.abort(abort_a),
 .data(rx_data),.valid(link_valid),.sof(link_sof),.eof(link_eof),.ready(ready),.armed(armed),.busy(),
 .write_req(write_req),.write_ack(wr_ack_pipe[1]),.full(full),.write_en(write_en),.write_data(write_data),
 .finish_toggle(finish_t),.done(done_link),.fault(fault),.frame_crc(rx_crc));
integer n,expected;
`ifdef TRACE
initial forever begin #1000000;$display("TRACE t=%t A=%d B=%d rx=%d tx=%d current=%d target=%d writes=%d crc=%h/%h err=%d/%d n=%d",$time,a.state,b.state,receiver.state,sender.state,current,target,write_index,rx_crc,tx_crc,error_a,error_b,n);$fflush();end
`endif
task settle;
 begin wait(a.state==2 && b.state==2);repeat(5)@(posedge clk);if(error_a!=0 || error_b!=0)$fatal(1,"transaction errors A=%d B=%d",error_a,error_b);end
endtask
task press;
 input right;
 begin @(negedge clk);previous=!right;next=right;@(negedge clk);previous=0;next=0;end
endtask
initial begin
 repeat(12)@(posedge clk);rst_b=0;repeat(50)@(posedge clk);rst_a=0;
 settle;if(current!=0 || image_count!=6)$fatal(1,"startup image/directory");
 expected=0;
 for(n=0;n<100;n=n+1)begin
  press(n%3!=0);expected=n%3!=0 ? (expected+1)%6:(expected+5)%6;
  wait(a.state!=2);settle;
  if(current!=expected)$fatal(1,"navigation %d expected=%d got=%d",n,expected,current);
 end
 $display("PASS 100 manual switches, six-image wrapping, real UART/link, backpressure and slot protection");
 // Merge three busy inputs into the latest direction, rather than cancelling
 // five toggles or accumulating a queue.
 press(1);wait(a.state==7);press(1);press(0);press(1);
 expected=(expected+2)%6;wait(current==expected);settle;
 $display("PASS latest-direction merge during receive/transition");
 // User-requested no-CRC mode accepts a complete frame with modified pixels.
 corrupt=1;press(1);wait(a.state!=2);settle;
 expected=(expected+1)%6;
 if(current!=expected || error_a!=0 || a.retries!=0)$fatal(1,"frame CRC still blocks commit");
 corrupt=0;
 $display("PASS no frame CRC: complete modified frame committed without CRC rejection/retry");
 // B reset while A displays an image: old display remains valid until boot
 // image is re-received through a new session.
 @(negedge clk);rst_b=1;repeat(8)@(posedge clk);rst_b=0;wait(b.state==0);wait(a.state==0);settle;
 if(!display_valid || current!=0)$fatal(1,"B reset recovery");
 @(negedge clk);rst_a=1;repeat(8)@(posedge clk);rst_a=0;settle;
 if(current!=0)$fatal(1,"A reset recovery");
 $display("PASS independent A/B resets and rediscovery");$finish;
end
initial begin #50000000;$display("A state %d B state %d current %d rx %d",a.state,b.state,current,receiver.state);$fatal(1,"system timeout");end
endmodule
