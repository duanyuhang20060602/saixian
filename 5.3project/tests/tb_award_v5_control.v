`timescale 1ns/1ps
module tb;
reg ac=0,bc=0;always #7 ac=~ac;always #5 bc=~bc;
reg rst=1,award_toggle=0;reg [18:0] settings={1'b0,4'd4,4'd4,4'd4,2'd1,2'd1,1'b0,1'b0};
wire at,bt,high_color,format_changed,arm_t,abort_t,start_t,abort_b,ready_t,immediate,fluid,receive_award,updating;
wire [1:0] receive_slot,ready_slot,transmit_slot;reg [1:0] active_slot=0;reg commit=0,seen_ready=0;
wire [2:0] current,count,target;wire [15:0] width,height;wire [3:0] ae,be;wire abusy,bbusy;
wire request,release_media,cancel;reg media_ready=0;reg [2:0] locked=0;integer load_delay=0;
wire [18:0] b_settings;wire tx_done,rx_done;reg finished_toggle=0;reg previous_start=0;integer transfer_delay=0,transfers=0,award_requests=0,begins=0;
photo_event_sync finish_a(.clk(ac),.rst(rst),.toggle(finished_toggle),.pulse(rx_done));
photo_event_sync finish_b(.clk(bc),.rst(rst),.toggle(finished_toggle),.pulse(tx_done));
always @(posedge bc)begin
 if(rst)begin media_ready<=0;load_delay<=0;previous_start<=0;finished_toggle<=0;transfer_delay<=0;end
 else begin
  if(request)begin locked<=target;load_delay<=8;media_ready<=0;end
  if(load_delay>0)begin load_delay<=load_delay-1;if(load_delay==1)media_ready<=1;end
  if(release_media || cancel)media_ready<=0;
  previous_start<=start_t;
  if(start_t!=previous_start)transfer_delay<=20;
  if(transfer_delay>0)begin transfer_delay<=transfer_delay-1;if(transfer_delay==1)begin finished_toggle<=~finished_toggle;transfers<=transfers+1;end end
  if(b.got && b.kind==3 && b.incoming[98:96]==6)begin
   if(b.incoming[87:56]!=2764800 || b.incoming[93]!=0)$fatal(1,"award request still uses legacy plate length/plane");
   award_requests=award_requests+1;
  end
 end
end
always @(posedge ac)begin
 if(rst)begin active_slot<=0;commit<=0;seen_ready<=0;end
 else begin
  if(ready_t!=seen_ready)begin seen_ready<=ready_t;active_slot<=ready_slot;commit<=~commit;end
  if(a.got && a.kind==4 && a.incoming[98:96]==6)begin
   if(a.incoming[87:56]!=2764800 || a.incoming[93]!=0 || !a.incoming[55])$fatal(1,"award BEGIN metadata is incompatible");
   begins=begins+1;
  end
 end
end
photo_cached_control_a #(.CLK_HZ(806400),.SETTINGS_LINK(1),.AWARD_CONTROL(1),.FLUID(1),.AWARD_LIGHTS(1),.CHECK_FRAME_CRC(1)) a(
 .receive_award(receive_award),.receive_fluid(fluid),.settings_mode(1'b1),.settings_state(settings),.settings_updating(updating),
 .award_toggle(award_toggle),.clk(ac),.rst(rst),.uart_rx(bt),.uart_tx(at),.previous(1'b0),.next(1'b0),
 .active_slot(active_slot),.new_slot(2'd0),.transition_active(1'b0),.commit_toggle(commit),.receive_slot(receive_slot),.arm_toggle(arm_t),.abort_toggle(abort_t),
 .rx_armed(1'b1),.rx_done(rx_done),.rx_fault(1'b0),.rx_crc(32'hacbd1234),.ready_immediate(immediate),.ready_toggle(ready_t),.ready_slot(ready_slot),
 .image_count(count),.current_image(current),.busy(abusy),.error(ae),.current_source_width(width),.current_source_height(height));
photo_control_b #(.CLK_HZ(1152000),.SETTINGS_LINK(1),.SEND_SOURCE_SIZE(1),.AWARD_CONTROL(1),.FLUID(1),.AWARD_LIGHTS(1),.CHECK_FRAME_CRC(1)) b(
 .award_available(1'b1),.award_scan_complete(1'b1),.clk(bc),.rst(rst),.uart_rx(at),.uart_tx(bt),.image_count(3'd1),.media_ready(media_ready),
 .media_slot(2'd0),.media_error(4'd0),.media_source_width(locked==6 ? 16'h8500:16'd1280),.media_source_height(16'd720),
 .media_request(request),.media_target(target),.media_release(release_media),.media_cancel(cancel),.transmit_slot(transmit_slot),.start_toggle(start_t),
 .abort_toggle(abort_b),.settings_state(b_settings),.tx_done(tx_done),.tx_crc(32'hacbd1234),.busy(bbusy),.error(be));
task toggle_award;begin @(negedge ac);award_toggle=1;@(negedge ac);award_toggle=0;end endtask
initial begin
 repeat(20)@(negedge ac);rst=0;
 wait(a.have_current && current==0 && !abusy && !bbusy);toggle_award;
 wait(current==6 && !abusy && !bbusy);if(!width[15] || !immediate || fluid)$fatal(1,"normal-mode award entry");
 // Refresh picture settings while retaining the fixed RGB565 award payload.
 settings[14]=!settings[14];
 wait(updating);wait(transfers>=3 && !updating && !abusy && !bbusy);
 wait(a.have_current && current==6 && !updating && !abusy && !bbusy);
 if(!width[15] || fluid || !receive_award)$fatal(1,"refreshed award lost 565 metadata");
 toggle_award;wait(current==0 && !abusy && !bbusy);
 if(width!=1280)$fatal(1,"photo not restored after award");
 toggle_award;wait(current==6 && !abusy && !bbusy);
 toggle_award;wait(current==0 && !abusy && !bbusy);
 if(ae || be || award_requests<2 || begins<2 || transfers!=4)$fatal(1,"incomplete award control coverage %0d/%0d/%0d errors=%0d/%0d",award_requests,begins,transfers,ae,be);
 $display("PASS real A/B UART: extended award length, RGB565 and settings refresh, tagged metadata, immediate entry/exit, settings refresh, CRC and cache-hit photo/award restoration");$finish;
end
initial begin #50000000;$fatal(1,"award control timeout current=%0d state=%0d/%0d err=%0d/%0d",current,a.state,b.state,ae,be);end
endmodule
