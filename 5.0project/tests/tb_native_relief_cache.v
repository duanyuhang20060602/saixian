`timescale 1ns/1ps
module tb;
reg clk=0,rst=1;reg[1:0]active=1;reg locked=0;always #5 clk=~clk;
photo_cached_control_a #(.FLUID(1),.EARLY_THUMBNAIL(1),.CLK_HZ(75000000)) dut(.clk(clk),.rst(rst),.uart_rx(1'b1),.active_slot(active),.new_slot(2'd0),.transition_active(1'b0),.commit_toggle(1'b0),.settings_mode(1'b0),.settings_state(19'd0),.award_toggle(1'b0),.relief_toggle(1'b0),.previous(1'b0),.next(1'b0),.thumbnail_read_busy(locked),.thumbnail_read_slot(2'd0),.rx_armed(1'b0),.rx_done(1'b0),.rx_fault(1'b0),.rx_crc(32'd0));
integer n,c,following,checks=0;
task settle;begin repeat(5)@(negedge clk);end endtask
initial begin
 repeat(4)@(negedge clk);rst=0;force dut.state_flags=16'd8;
 dut.have_current=1;dut.nav_pending=0;dut.display_pending=0;dut.cache_valid=3;
 for(n=2;n<=6;n=n+1)for(c=0;c<n;c=c+1)begin
  dut.image_count=n;dut.current_image=c;dut.cache_id[1]=c;dut.cache_id[0]=(c+n-1)%n;following=(c+1)%n;locked=0;settle();
  if(n==2)begin if(!dut.cache_window_ready || dut.plan_needed)$fatal(1,"two-photo ready window broken");end
  else begin
   if(!dut.plan_needed || !dut.plan_ok || dut.plan_target!=following || dut.plan_victim!=0)$fatal(1,"prefetch blocked count=%0d current=%0d need=%b ok=%b target=%d victim=%d",n,c,dut.plan_needed,dut.plan_ok,dut.plan_target,dut.plan_victim);
   locked=1;settle();if(dut.plan_ok)$fatal(1,"locked preview slot selected");locked=0;
   dut.cache_id[0]=following;settle();if(!dut.cache_window_ready || dut.plan_needed)$fatal(1,"current-next window not ready");
  end
  checks=checks+1;
 end
 $display("PASS two-slot production prefetch planner: all 20 current/previous/next windows for 2..6 photos, wrap, current-slot protection, locked preview exclusion and ready-window completion");$finish;
end
endmodule
