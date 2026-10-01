`timescale 1ns/1ps
// Use the real transition controller and independently model SD completion
// and frame contents. Exercise repeated wraps, not just cache tag updates.
`ifdef NAV_UART_SIM
module tb_navigation_uart;
`else
module tb_navigation_cycles;
`endif
reg clk=0,video_clk=0; always #5 clk=~clk; always #7 video_clk=~video_clk;
reg rst=1,prev=0,next=0,finish=0,reader_ready=1;
reg tick=0; integer tick_count=0;
`ifdef NAV_UART_SIM
reg serial_rx=1;
wire uart_prev,uart_next,uart_error;
integer received_prev=0,received_next=0;
// Scale baud and clock together while retaining the actual 8N1 receiver.
saixian_hmi_uart #(.CLK_FREQ_HZ(16000000),.BAUD_RATE(1000000)) uart(
 .clk(video_clk),.rst(rst),.uart_rx(serial_rx),
 .prev_pulse(uart_prev),.next_pulse(uart_next),.frame_error_pulse(uart_error));
always @(posedge video_clk) begin
 if(rst) begin prev<=0;next<=0;received_prev<=0;received_next<=0;end
 else begin
  if(uart_error) $fatal(1,"valid navigation UART frame rejected");
  if(uart_prev) begin prev<=~prev;received_prev<=received_prev+1;end
  if(uart_next) begin next<=~next;received_next<=received_next+1;end
 end
end
task send_byte;input [7:0] value;integer bit_index;
begin
 @(negedge video_clk);serial_rx=0;repeat(16) @(negedge video_clk);
 for(bit_index=0;bit_index<8;bit_index=bit_index+1) begin
  serial_rx=value[bit_index];repeat(16) @(negedge video_clk);
 end
 serial_rx=1;repeat(16) @(negedge video_clk);
end
endtask
task send_navigation;input [7:0] command;
begin
 send_byte(8'h55);send_byte(command);send_byte(0);send_byte(0);
 send_byte(8'hff);send_byte(8'hff);send_byte(8'hff);
 repeat(12) @(negedge video_clk);
end
endtask
`endif
always @(posedge video_clk) begin
 if(rst) begin tick<=0;tick_count<=0;end
 else begin tick<=tick_count==22;tick_count<=tick_count==22 ? 0 : tick_count+1;end
end
wire commit,ready_toggle,transition_active,display_valid;
wire [1:0] ready_slot,active_slot,new_slot;
wire ready_right;
sd_card_bmp #(.CLK_FREQ_HZ(1000000)) dut(.clk(clk),.rst(rst),
 .prev_req_toggle(prev),.next_req_toggle(next),.carousel_mode(1'b1),
 .display_commit_toggle(commit),.write_finish_toggle(finish),
 .audio_track_index(3'd0),.audio_track_toggle(1'b0),.audio_fifo_wrusedw(9'd0),
 .bmp_width(16'd1280),.bmp_height(16'd720),.write_req_ack(1'b0),.SD_MISO(1'b0),
 .frame_ready_toggle(ready_toggle),.ready_buf_idx(ready_slot),.ready_slide_right(ready_right));
saixian_transition transition(.clk(video_clk),.rst(rst),.frame_tick(tick),
 .frame_ready_toggle(ready_toggle),.ready_buf_idx(ready_slot),.ready_slide_right(ready_right),
 .active_buf_idx(active_slot),.slide_new_buf_idx(new_slot),
 .frame_commit_toggle(commit),.transition_active(transition_active),.display_valid(display_valid));
integer contents[0:3];integer delay_left=0,load_delay=80,load_image=0,load_slot=0,writes=0;
reg seen_commit=0,seen_ready=0;integer published_image=0,commits=0;
always @(posedge clk) begin
 if(rst) begin
  reader_ready<=1;delay_left<=0;finish<=0;writes<=0;
  contents[0]=-1;contents[1]=-1;contents[2]=-1;contents[3]=-1;
 end else if(dut.load_start_pulse) begin
  if(!reader_ready) $fatal(1,"overlapping SD loads");
  load_image=(dut.load_sector>>12)-1;load_slot=dut.write_buf_idx;
  if(display_valid && (load_slot==active_slot || (transition_active && load_slot==new_slot)))
   $fatal(1,"loader overwrote a displayed/transition frame");
  reader_ready<=0;delay_left<=load_delay;writes<=writes+1;
 end else if(!reader_ready) begin
  if(delay_left==0) begin contents[load_slot]=load_image;reader_ready<=1;finish<=~finish;end
  else delay_left<=delay_left-1;
 end
end
always @(negedge clk) begin
 if(rst) begin seen_commit=0;seen_ready=0;commits=0;end
 else begin
  if(ready_toggle!=seen_ready) begin
   seen_ready=ready_toggle;published_image=dut.pending_image;
   if(contents[ready_slot]!=published_image)
    $fatal(1,"published slot content differs from requested image");
  end
  if(commit!=seen_commit) begin
   seen_commit=commit;commits=commits+1;
   if(contents[active_slot]!=published_image)
    $fatal(1,"visible frame content differs from committed image");
  end
 end
end
task initialize;
begin
 rst=1;prev=0;next=0;
 force dut.sd_init_done=1;force dut.scan_done=1;force dut.bmp_ready=reader_ready;
 force dut.scan_found_valid=0;force dut.audio_scan_found_valid=0;force dut.bmp_data_wr_en=0;
 repeat(4) @(negedge clk);rst=0;
 force dut.scan_kicked=1;force dut.image_count=5;
 force dut.image_sector0=32'h1000;force dut.image_sector1=32'h2000;
 force dut.image_sector2=32'h3000;force dut.image_sector3=32'h4000;force dut.image_sector4=32'h5000;
 wait(dut.display_committed);repeat(6) @(negedge clk);
end
endtask
`ifdef NAV_UART_SIM
task press_next;begin send_navigation(8'h05);end endtask
task press_prev;begin send_navigation(8'h04);end endtask
`else
task press_next;begin next=~next;repeat(5) @(negedge clk);end endtask
task press_prev;begin prev=~prev;repeat(5) @(negedge clk);end endtask
`endif
task settle;input integer image;
begin
 wait(dut.current_image==image && !dut.awaiting_commit);
 repeat(6) @(negedge clk);
 if(contents[active_slot]!=image) $fatal(1,"settled visible image is wrong");
end
endtask
integer i,target;
initial begin
 initialize;target=0;
 for(i=0;i<20;i=i+1) begin target=(target+1)%5;press_next;settle(target);end
 for(i=0;i<20;i=i+1) begin target=(target+4)%5;press_prev;settle(target);end
 $display("INFO 40 settled clicks passed: four forward/backward wraps and actual frame contents");
 @(negedge clk);dut.auto_timer=5000000-1;
 settle(1);press_prev;settle(0);
`ifdef NAV_UART_SIM
 if(received_prev!=21 || received_next!=20)
  $fatal(1,"UART navigation count mismatch prev=%d next=%d",received_prev,received_next);
 $display("PASS UART navigation: actual 8N1 packets, 40 settled clicks across repeated wraps, auto/manual boundary and independent frame contents");
 $finish;
`else
 // Five clicks during one slow load must not cancel the requested direction.
 load_delay=900;initialize;
 wait(dut.load_busy && dut.loading_image==1);
 repeat(5) press_next;
 if(dut.desired_image!=1) $fatal(1,"five next clicks while loading wrapped back to the visible image");
 wait(transition_active);
 repeat(5) press_prev;
 if(dut.desired_image!=0) $fatal(1,"reverse clicks during transition did not target the frame before it");
 settle(0);
 // Recover immediately by another manual click, without an auto timer tick.
 press_next;settle(1);
 initialize;wait(dut.load_busy && dut.loading_image==1);
 repeat(5) press_prev;
 if(dut.desired_image!=4) $fatal(1,"five previous clicks while loading cancelled the target");
 settle(4);press_next;settle(0);
 $display("PASS navigation cycles: 40 settled clicks, auto/manual boundary, slow five-click bursts both directions, transition reversal and immediate manual recovery");
 $finish;
`endif
end
initial begin #2000000;$fatal(1,"navigation cycle timeout current=%d desired=%d pending=%d busy=%b awaiting=%b",dut.current_image,dut.desired_image,dut.pending_image,dut.load_busy,dut.awaiting_commit);end
endmodule
