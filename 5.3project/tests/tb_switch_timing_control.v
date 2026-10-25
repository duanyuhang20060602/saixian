`timescale 1ns/1ps
module tb_switch_timing_control;
reg clk=0;always #5 clk=~clk;
reg rst=1,next=0,commit=0;
wire ab,ap,ac,ax,ar,av;wire [19:0] atotal;
photo_cached_control_a #(.CLK_HZ(1000000)) a(.clk(clk),.rst(rst),.uart_rx(1'b1),
 .settings_mode(1'b0),.settings_state(19'd0),.award_toggle(1'b0),.previous(1'b0),.next(next),
 .active_slot(2'd0),.new_slot(2'd1),.transition_active(1'b0),.commit_toggle(commit),
 .rx_armed(1'b0),.rx_done(1'b0),.rx_fault(1'b0),.rx_crc(32'd0),
 .timing_begin(ab),.timing_present(ap),.timing_commit(ac),.timing_cancel(ax));
photo_switch_timing #(.CLK_HZ(10000),.PHASES(2)) a_probe(.clk(clk),.rst(rst),.start(ab),.mark1(ap),.mark2(1'b0),
 .finish(ac),.cancel(ax),.running(ar),.valid(av),.first_ms(),.second_ms(),.third_ms(),.total_ms(atotal));
integer a_finishes=0;
always @(posedge clk)if(ac)a_finishes=a_finishes+1;
task click;begin @(negedge clk);next=1;@(negedge clk);next=0;end endtask
task commit_frame;begin @(negedge clk);commit=~commit;repeat(4)@(negedge clk);end endtask
reg b_got=0,b_ready=0,b_done=0;reg [159:0] b_packet=0;
wire bb,br,bs,bd,bx,bvalid,brunning;wire [19:0] btotal;
photo_control_b #(.CLK_HZ(1000000),.FRAME_BYTES(4)) b(.clk(clk),.rst(rst),.uart_rx(1'b1),
 .award_available(1'b0),.award_scan_complete(1'b1),.image_count(3'd3),.media_ready(b_ready),.media_slot(2'd1),.media_error(4'd0),
 .media_source_width(16'd1280),.media_source_height(16'd720),.tx_done(b_done),.tx_crc(32'd0),
 .timing_begin(bb),.timing_ready(br),.timing_send(bs),.timing_done(bd),.timing_cancel(bx));
photo_switch_timing #(.CLK_HZ(10000),.PHASES(3)) b_probe(.clk(clk),.rst(rst),.start(bb),.mark1(br),.mark2(bs),
 .finish(bd),.cancel(bx),.running(brunning),.valid(bvalid),.first_ms(),.second_ms(),.third_ms(),.total_ms(btotal));
task packet;
 input [7:0] kind;
 begin @(negedge clk);b_packet={kind,32'd7,16'd1,8'd1,8'd0,32'd4,32'd0,8'd0,16'd0};
  b_got=1;@(negedge clk);b_got=0;
 end
endtask
initial begin
 force b.got=b_got;force b.incoming=b_packet;
 repeat(5)@(negedge clk);rst=0;
 @(negedge clk);a.state_flags=16'd4;a.have_current=1;a.current_image=0;a.image_count=3;
 a.cache_valid=7;a.cache_id[0]=0;a.cache_id[1]=1;a.cache_id[2]=2;
 a.current_source_width=1280;a.cache_width[0]=1280;a.cache_width[1]=1280;a.cache_width[2]=1280;
 repeat(10)@(negedge clk);
 click();wait(a.display_pending);repeat(30)@(negedge clk);commit_frame();
 if(!av || ar || a_finishes!=1)$fatal(1,"cached A navigation did not finish measurement");
 // A second click during an old transition must wait for its OWN display commit.
 click();wait(a.display_pending);repeat(12)@(negedge clk);click();
 repeat(12)@(negedge clk);commit_frame();
 if(!ar || a_finishes!=1)$fatal(1,"old display commit completed a newer request");
 wait(a.display_pending);repeat(20)@(negedge clk);commit_frame();
 if(ar || a_finishes!=2)$fatal(1,"queued request failed to commit its own sample");
 @(negedge clk);b.state=2;b.session=7;packet(3);
 repeat(25)@(negedge clk);b_ready=1;wait(b.state==5);
 repeat(30)@(negedge clk);packet(5);wait(b.state==6);
 repeat(40)@(negedge clk);b_done=1;@(negedge clk);b_done=0;repeat(3)@(negedge clk);
 if(!bvalid || brunning || btotal<20'h00009)$fatal(1,"B phase events did not publish timing: %h",btotal);
 $display("PASS A/B timing integration: cache hit, queued clicks, old-commit exclusion, B load/handshake/transfer milestones");
 $finish;
end
initial begin #1000000;$fatal(1,"control timing test timeout");end
endmodule
