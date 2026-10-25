`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,lock_source=1;always #5 clk=~clk;
photo_cached_control_a #(.FLUID(1),.CHECK_FRAME_CRC(1),.EARLY_THUMBNAIL(1)) dut(
 .clk(clk),.rst(rst),.uart_rx(1'b1),.settings_mode(1'b0),.settings_state(19'd0),.award_toggle(1'b0),.previous(1'b0),.next(1'b0),
 .active_slot(2'd0),.new_slot(2'd1),.transition_active(1'b0),.commit_toggle(1'b0),
 .rx_armed(1'b0),.rx_done(1'b0),.rx_fault(1'b0),.rx_crc(32'd0),.thumbnail_read_busy(lock_source),.thumbnail_read_slot(2'd1));
initial begin
 repeat(5)@(negedge clk);rst=0;
 @(negedge clk);dut.state_flags=0;dut.have_current=1;dut.current_image=0;dut.image_count=6;
 dut.cache_valid=3;dut.cache_id[0]=0;dut.cache_id[1]=1;dut.nav_pending=1;dut.nav_target=4;
 repeat(20)@(negedge clk);
 if(dut.victim_ok || dut.plan_ok)$fatal(1,"in-flight preview source selected as victim");
 lock_source=0;repeat(10)@(negedge clk);
 if(!dut.victim_ok || dut.victim!=1 || !dut.plan_ok || dut.plan_victim!=1)$fatal(1,"released source cannot be reused");
 // Reassert the lock against an already registered receive plan. Its
 // preview-context lease must prevent the old plan from overwriting slot 1.
 lock_source=1;dut.state_flags=4;
 repeat(10)@(negedge clk);
 if(!dut.cache_valid[1] || dut.victim_ok || dut.plan_ok)$fatal(1,"stale plan overwrote the newly pinned source");
 $display("PASS native two-slot preview source lock, release/reuse and stale receive-plan rejection");$finish;
end
initial begin #100000;$fatal(1,"source lock timeout");end
endmodule
