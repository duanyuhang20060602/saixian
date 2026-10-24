`timescale 1ns/1ps
// Real cached A controller, B controller, UART, pixel link and transition.
// Memory application interfaces are modeled; image 1 carries the award flag.
module tb_award_mode_v4;
reg ac=0,bc=0,lc=0;always #7 ac=~ac;always #5 bc=~bc;always #10 lc=~lc;
reg rst=1,next=0,award_toggle=0,award_found=0,scan_complete=0,fail_award=0;wire available,loading;wire [2:0] notice;wire at,bt,arm_t,abort_a_t,start_t,abort_b_t;
reg settings_mode=0,photo_focus=0;
always @(posedge ac)if(rst)photo_focus<=0;else photo_focus<=settings_mode || loading || sw[15];
reg [18:0] settings={1'b0,4'd4,4'd4,4'd4,2'd1,2'd1,1'b0,1'b0};
wire [1:0] receive_slot,active_slot,new_slot,ready_slot,transmit_slot;
wire transition_active,commit,ready_t,ready_right,immediate,visible,armed,rx_done,fault;
wire arm,abort_a,start,abort_b,done_a,done_b;reg da=0,db=0;
wire [2:0] count,current,cached;wire [3:0] ae,be;wire abusy,bbusy;wire [15:0] sw,sh;
photo_event_sync aa(lc,rst,arm_t,arm), ax(lc,rst,abort_a_t,abort_a), bs(lc,rst,start_t,start), bx(lc,rst,abort_b_t,abort_b);
photo_event_sync ad(ac,rst,da,done_a), bd(bc,rst,db,done_b);
wire request,release_media,cancel;wire [2:0] target;
reg [3:0] sticky_media_error=0;
reg [2:0] media_request_settle=0;
wire media_result_current=!request && media_request_settle==0;
always @(posedge bc)begin
 if(rst)begin media_request_settle<=0;sticky_media_error<=0;end
 else begin
  if(request)begin media_request_settle<=4;sticky_media_error<=0;end
  else begin
   if(media_request_settle!=0)media_request_settle<=media_request_settle-1'b1;
   if(fail_award && locked==6)sticky_media_error<=8;
  end
 end
end
reg media_ready=0;reg [2:0] locked=0;integer pending=0;
always @(posedge bc)begin
 if(rst || cancel)begin media_ready<=0;pending<=0;end
 else begin
  if(release_media)media_ready<=0;
  if(request)begin locked<=target;pending<=16;media_ready<=0;end
  if(pending>0)begin pending<=pending-1;if(pending==1 && !(fail_award && locked==6))media_ready<=1;end
 end
end
photo_cached_control_a #(.CLK_HZ(806400),.FRAME_BYTES(64),.SETTINGS_LINK(1),.AWARD_CONTROL(1)) a(
 .award_toggle(award_toggle),.award_available(available),.award_loading(loading),.award_notice(notice),
 .settings_mode(photo_focus),.settings_state(settings),.clk(ac),.rst(rst),.uart_rx(bt),.uart_tx(at),.previous(1'b0),.next(next),
 .active_slot(active_slot),.new_slot(new_slot),.transition_active(transition_active),.commit_toggle(commit),
 .receive_slot(receive_slot),.arm_toggle(arm_t),.abort_toggle(abort_a_t),.rx_armed(armed),.rx_done(done_a),.rx_fault(fault),.rx_crc(32'd0),
 .ready_immediate(immediate),.ready_toggle(ready_t),.ready_slot(ready_slot),.ready_right(ready_right),
 .image_count(count),.current_image(current),.busy(abusy),.error(ae),.cached_count(cached),
 .current_source_width(sw),.current_source_height(sh));
photo_control_b #(.CLK_HZ(1152000),.FRAME_BYTES(64),.SEND_SOURCE_SIZE(1),.SETTINGS_LINK(1),.AWARD_CONTROL(1)) b(
 .award_available(award_found),.award_scan_complete(scan_complete),
 .clk(bc),.rst(rst),.uart_rx(at),.uart_tx(bt),.image_count(3'd6),.media_ready(media_ready && media_result_current),
 .media_slot(2'd0),.media_error(media_result_current ? sticky_media_error:4'd0),.media_source_width(locked==6 ? 16'h8500:16'd1280),.media_source_height(16'd720),
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
photo_link_sender #(.FRAME_PIXELS(32)) tx(.clk(lc),.rst(rst),.start(start),.abort(abort_b),
 .data(rd),.empty(1'b0),.read_ack(ra[1]),.link_ready(lr),.read_req(read_req),.read_en(read_en),
 .link_data(ld),.link_valid(lv),.link_sof(ls),.link_eof(le),.done(sent));
photo_link_receiver #(.FRAME_PIXELS(32)) rx(.clk(lc),.rst(rst),.arm(arm),.abort(abort_a),
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
  if(sw!==(expected==6 ? 16'h8500:16'd1280) || sh!==720)$fatal(1,"display metadata mismatched");
 end
endtask
integer n;
`ifdef TRACE
initial forever begin #1000000;$display("TRACE t=%0t n=%0d A=%0d B=%0d cached=%0d ids=%0d/%0d/%0d/%0d valid=%b have=%b current=%0d nav=%0b navtarget=%0d target=%0d transfers=%0d tx=%0d rx=%0d errors=%0d/%0d flagsB=%b cat=%h ann=%h flagA=%b notice=%0d reply=%b",$time,n,a.state,b.state,cached,a.cache_id[0],a.cache_id[1],a.cache_id[2],a.cache_id[3],a.cache_valid,a.have_current,current,a.nav_pending,a.nav_target,target,transfers,tx.state,rx.state,ae,be,scan_complete,b.catalog,b.announced_count,a.award_scan_complete,notice,a.count_reply);$fflush();end
`endif
task toggle_award;
 begin @(negedge ac);award_toggle=1;@(negedge ac);award_toggle=0;end
endtask
initial begin
 repeat(20)@(negedge ac);rst=0;
 wait(visible && current==0 && cached==4 && !abusy && !bbusy);
 if(count!=6 || available)$fatal(1,"initial photo catalogue");
 scan_complete=1;wait(a.award_scan_complete);wait(b.announced_count==8'h46);toggle_award();repeat(5)@(negedge ac);
 if(notice!=2 || current!=0 || !visible)$fatal(1,"missing DLT blanked photo");
 scan_complete=0;wait(!a.award_scan_complete);
 for(n=1;n<=6;n=n+1)advance(n%6,0);
 // A request made before background discovery must wait without blanking.
 toggle_award();repeat(100)@(negedge ac);
 if(!loading || current!=0 || !visible)$fatal(1,"discovery wait blanked photo");
 award_found=1;scan_complete=1;
 wait(current==6);repeat(5)@(negedge ac);
 if(sw!==16'h8500 || !available)$fatal(1,"dedicated award metadata");
 wait(!a.context_dirty && !bbusy && b.display_image==6 && b.prefetch_pause);
 if(!b.display_valid)$fatal(1,"award playback not pinned in B cache");
 toggle_award();wait(current==0);repeat(5)@(negedge ac);
 // Photo key leaves the award and advances from the saved photo.
 toggle_award();wait(current==6);advance(1,1);
 // Invalidate only the award cache, then fail its media load.
 wait(!abusy && !bbusy && a.state==2);
 for(n=0;n<4;n=n+1)if(a.cache_id[n]==6)a.cache_valid[n]=0;
 fail_award=1;toggle_award();wait(notice==3);repeat(10)@(negedge ac);
 if(current!=1 || !visible || a.nav_pending)$fatal(1,"failed award did not preserve photo");
 fail_award=0;toggle_award();wait(current==6);
 toggle_award();wait(current==1);
 // Six photos still wrap; reserved ID 6 is never included.
 for(n=2;n<=7;n=n+1)advance(n%6,0);
 $display("PASS V3 six photos plus dedicated award, deferred discovery, toggle return, photo-key exit, failed-load preservation and retry, no award in photo loop");$finish;
end
initial begin #30000000;$fatal(1,"control timeout A=%d B=%d cached=%d current=%d",a.state,b.state,cached,current);end
endmodule
