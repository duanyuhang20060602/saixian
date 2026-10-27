`timescale 1ns/1ps
module tb;
parameter BAUD=115200;
reg clk=0,rst=1,next=0;always #5 clk=~clk;
wire at,bt,arm,req,start;reg armed=0,done=0,tdone=0;wire tbeg,tpres;time t0,t1;
photo_cached_control_a #(.CLK_HZ(9216000),.CONTROL_BAUD(BAUD),.FRAME_BYTES(4)) a(
 .clk(clk),.rst(rst),.uart_rx(bt),.uart_tx(at),.settings_mode(1'b0),.settings_state(19'd0),
 .award_toggle(1'b0),.relief_toggle(1'b0),.previous(1'b0),.next(next),.active_slot(2'd0),.new_slot(2'd1),
 .transition_active(1'b0),.commit_toggle(1'b0),.arm_toggle(arm),.rx_armed(armed),.rx_done(done),.rx_fault(1'b0),.rx_crc(32'd0),
 .thumbnail_read_busy(1'b0),.thumbnail_read_slot(2'd0),.timing_begin(tbeg),.timing_present(tpres));
photo_control_b #(.CLK_HZ(9216000),.CONTROL_BAUD(BAUD),.FRAME_BYTES(4)) b(
 .clk(clk),.rst(rst),.uart_rx(at),.uart_tx(bt),.award_available(1'b0),.award_scan_complete(1'b1),.image_count(3'd3),
 .media_ready(req),.media_slot(2'd1),.media_error(4'd0),.media_source_width(16'd1280),.media_source_height(16'd720),
 .tx_done(tdone),.tx_crc(32'd0),.media_request(req),.start_toggle(start));
reg oldarm=0,oldstart=0;integer transfer=0;
always @(posedge clk)begin
 oldarm<=arm;oldstart<=start;
 if(arm!=oldarm)armed<=1;
 if(start!=oldstart)transfer<=1;
 if(transfer>0)begin
  transfer<=transfer+1;
  if(transfer==100)begin done<=1;tdone<=1;end
  if(transfer==101)begin done<=0;tdone<=0;end
 end
end
always @(posedge clk)if(tbeg)t0=$time;
initial begin
 repeat(8)@(negedge clk);rst=0;repeat(8)@(negedge clk);
 a.state_flags=4;a.have_current=1;a.current_image=0;a.image_count=3;a.session=1;
 a.cache_valid=1;a.cache_id[0]=0;a.current_source_width=1280;
 b.state_flags=4;b.session=1;b.announced_count=3;
 // Let the real demand-fetch planner choose its slot.
 @(negedge clk);next=1;@(negedge clk);next=0;
 wait(tpres);t1=$time;
 if(a.error || b.error || a.display_target!=1)$fatal(1,"switch protocol failed");
 $display("SWITCH_CYCLES %0d",(t1-t0)/10);
 $display("PASS uncached switch GET/BEGIN/READY/frame/END/display-ready, fixed media-ready and 100-cycle frame stub");$finish;
end
initial begin #10000000;$fatal(1,"timeout A=%d B=%d",a.state,b.state);end
endmodule
