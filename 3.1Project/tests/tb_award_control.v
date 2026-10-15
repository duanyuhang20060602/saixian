`timescale 1ns/1ps
// Real cached A controller, B controller, UART, pixel link and transition.
// Memory application interfaces are modeled; image 1 carries the award flag.
module tb_award_control;
reg ac=0,bc=0,lc=0;always #7 ac=~ac;always #5 bc=~bc;always #10 lc=~lc;
reg rst=1,next=0;wire at,bt,arm_t,abort_a_t,start_t,abort_b_t;
reg settings_mode=0;
reg [18:0] settings={1'b0,4'd4,4'd4,4'd4,2'd1,2'd1,1'b0,1'b0};
wire [1:0] receive_slot,active_slot,new_slot,ready_slot,transmit_slot;
wire transition_active,commit,ready_t,ready_right,immediate,visible,armed,rx_done,fault;
wire arm,abort_a,start,abort_b,done_a,done_b;reg da=0,db=0;
wire [2:0] count,current,cached;wire [3:0] ae,be;wire abusy,bbusy;wire [15:0] sw,sh;
photo_event_sync aa(lc,rst,arm_t,arm), ax(lc,rst,abort_a_t,abort_a), bs(lc,rst,start_t,start), bx(lc,rst,abort_b_t,abort_b);
photo_event_sync ad(ac,rst,da,done_a), bd(bc,rst,db,done_b);
wire request,release_media,cancel;wire [2:0] target;
reg media_ready=0;reg [2:0] locked=0;integer pending=0;
always @(posedge bc)begin
 if(rst || cancel)begin media_ready<=0;pending<=0;end
 else begin
  if(release_media)media_ready<=0;
  if(request)begin locked<=target;pending<=16;media_ready<=0;end
  if(pending>0)begin pending<=pending-1;if(pending==1)media_ready<=1;end
 end
end
photo_cached_control_a #(.CLK_HZ(806400),.FRAME_BYTES(64),.SETTINGS_LINK(1)) a(
 .settings_mode(settings_mode),.settings_state(settings),.clk(ac),.rst(rst),.uart_rx(bt),.uart_tx(at),.previous(1'b0),.next(next),
 .active_slot(active_slot),.new_slot(new_slot),.transition_active(transition_active),.commit_toggle(commit),
 .receive_slot(receive_slot),.arm_toggle(arm_t),.abort_toggle(abort_a_t),.rx_armed(armed),.rx_done(done_a),.rx_fault(fault),.rx_crc(32'd0),
 .ready_immediate(immediate),.ready_toggle(ready_t),.ready_slot(ready_slot),.ready_right(ready_right),
 .image_count(count),.current_image(current),.busy(abusy),.error(ae),.cached_count(cached),
 .current_source_width(sw),.current_source_height(sh));
photo_control_b #(.CLK_HZ(1152000),.FRAME_BYTES(64),.SEND_SOURCE_SIZE(1),.SETTINGS_LINK(1)) b(
 .high_color(1'b0),.clk(bc),.rst(rst),.uart_rx(at),.uart_tx(bt),.image_count(3'd3),.media_ready(media_ready),
 .media_slot(2'd0),.media_error(4'd0),.media_source_width(locked==1 ? 16'h8500:16'd1280),.media_source_height(16'd720),
 .media_request(request),.media_target(target),.media_release(release_media),.media_cancel(cancel),
 .transmit_slot(transmit_slot),.start_toggle(start_t),.abort_toggle(abort_b_t),.tx_done(done_b),.tx_crc(32'd0),.busy(bbusy),.error(be));
reg [8:0] div=0;wire tick=div==399;
always @(posedge ac)if(rst)div<=0;else div<=tick ? 0:div+1'b1;
saixian_transition #(.ALLOW_IMMEDIATE(1)) trans(.clk(ac),.rst(rst),.frame_tick(tick),.frame_ready_toggle(ready_t),
 .ready_buf_idx(ready_slot),.ready_slide_right(ready_right),.ready_immediate(immediate),.effect_select(3'd2),
 .active_buf_idx(active_slot),.slide_new_buf_idx(new_slot),.frame_commit_toggle(commit),.display_valid(visible),.transition_active(transition_active));
wire read_req,read_en,sent,lv,ls,le,lr,wr_req,we;wire [15:0] ld;wire [31:0] wd;
reg [31:0] rd=0;reg [1:0] ra=0,wa=0;reg finish=0;integer index=0,writes=0,transfers=0;
function [31:0] pattern;input integer n;begin pattern=32'ha58119ee^(32'h01010101*n);end endfunction
always @(posedge lc)begin
 if(rst)begin index<=0;rd<=0;ra<=0;wa<=0;writes<=0;finish<=0;da<=0;db<=0;transfers<=0;end
 else begin
  ra<={ra[0],read_req};wa<={wa[0],wr_req};
  if(read_req)index<=0;
  if(read_en)begin rd<=pattern(index);index<=index+1;end
  if(wr_req)writes<=0;
  if(we)begin
   if(visible && receive_slot==active_slot)$fatal(1,"overwrote active slot");
   if(wd!==pattern(writes))$fatal(1,"tag word corrupted");
   writes<=writes+1;
   if(writes==15)begin finish<=~finish;transfers<=transfers+1;end
  end
  if(rx_done)da<=~da;if(sent)db<=~db;
 end
end
photo_link_sender #(.FRAME_PIXELS(32)) tx(.high_color(1'b0),.clk(lc),.rst(rst),.start(start),.abort(abort_b),
 .data(rd),.empty(1'b0),.read_ack(ra[1]),.link_ready(lr),.read_req(read_req),.read_en(read_en),
 .link_data(ld),.link_valid(lv),.link_sof(ls),.link_eof(le),.done(sent));
photo_link_receiver #(.FRAME_PIXELS(32)) rx(.high_color(1'b0),.clk(lc),.rst(rst),.arm(arm),.abort(abort_a),
 .data(ld),.valid(lv),.sof(ls),.eof(le),.ready(lr),.armed(armed),.write_req(wr_req),.write_ack(wa[1]),
 .full(1'b0),.write_en(we),.write_data(wd),.finish_toggle(finish),.done(rx_done),.fault(fault));
task advance;
 input integer expected;input expected_immediate;
 reg seen;
 begin
  seen=ready_t;@(negedge ac);next=1;@(negedge ac);next=0;
  wait(ready_t!=seen);#1;
  if(immediate!==expected_immediate)$fatal(1,"wrong transition policy to image %0d",expected);
  wait(current==expected);repeat(5)@(negedge ac);
  if(sw!==(expected==1 ? 16'h8500:16'd1280) || sh!==720)$fatal(1,"display metadata mismatched");
 end
endtask
integer n;
`ifdef TRACE
initial forever begin #1000000;$display("TRACE t=%0t n=%0d A=%0d B=%0d cached=%0d ids=%0d/%0d/%0d/%0d valid=%b have=%b current=%0d nav=%0b navtarget=%0d target=%0d transfers=%0d tx=%0d rx=%0d errors=%0d/%0d",$time,n,a.state,b.state,cached,a.cache_id[0],a.cache_id[1],a.cache_id[2],a.cache_id[3],a.cache_valid,a.have_current,current,a.nav_pending,a.nav_target,target,transfers,tx.state,rx.state,ae,be);$fflush();end
`endif
initial begin
 repeat(20)@(negedge ac);rst=0;
 wait(visible && current==0 && cached==3 && !abusy && !bbusy);repeat(10)@(negedge ac);
 if(sw!==1280)$fatal(1,"background award metadata changed visible photo");
 for(n=0;n<6;n=n+1)begin advance(1,1);advance(2,1);advance(0,0);end
 if(ae || be || transfers!=3)$fatal(1,"cache reuse/error transfers=%0d A=%0d B=%0d",transfers,ae,be);
 advance(1,1);settings_mode=1;
 wait(!a.context_dirty && a.state==2 && !bbusy);repeat(5)@(negedge ac);
 if(!b.prefetch_pause || !b.display_valid || b.display_image!=1)$fatal(1,"menu display-pin context");
 settings[17:14]=5;
 wait(a.applied_settings==settings && !a.refresh_pending && !a.display_pending && !abusy && a.state==2 && !bbusy);
 repeat(5)@(negedge ac);
 if(sw!==16'h8500 || current!=1)$fatal(1,"settings refresh lost award metadata");
 settings_mode=0;wait(!a.context_dirty && a.state==2 && !bbusy && cached==3);
 if(b.prefetch_pause || ae || be)$fatal(1,"menu exit/context recovery");
 $display("PASS cached A/B UART metadata, background award isolation, frame-boundary entry/exit, photo transition restoration, 18 cached switches, settings pin/refresh/exit, active slot protection");$finish;
end
initial begin #30000000;$fatal(1,"control timeout A=%d B=%d cached=%d current=%d",a.state,b.state,cached,current);end
endmodule
