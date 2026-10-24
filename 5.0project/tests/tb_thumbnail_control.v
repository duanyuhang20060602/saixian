`timescale 1ns/1ps
module tb_thumbnail_control;
reg clk=0,rst=1,next=0;
always #5 clk=~clk;
wire valid;wire [1:0] slot;
photo_cached_control_a #(.FLUID(1),.CHECK_FRAME_CRC(1)) dut(.clk(clk),.rst(rst),.uart_rx(1'b1),
 .settings_mode(1'b0),.settings_state(19'd0),.award_toggle(1'b0),.previous(1'b0),.next(next),
 .active_slot(2'd0),.new_slot(2'd1),.transition_active(1'b0),.commit_toggle(1'b0),
 .rx_armed(1'b0),.rx_done(1'b0),.rx_fault(1'b0),.rx_crc(32'd0),.thumbnail_valid(valid),.thumbnail_slot(slot));
task settle;begin repeat(5)@(negedge clk);end endtask
initial begin
 repeat(5)@(negedge clk);rst=0;
 @(negedge clk);dut.state_flags=16'd4;dut.have_current=1;dut.current_image=0;dut.image_count=3;
 dut.nav_pending=0;dut.display_pending=0;dut.cache_valid=3;
 dut.cache_id[0]=0;dut.cache_id[1]=1;dut.cache_id[2]=2;
 settle();if(!valid || slot!=1)$fatal(1,"next image not selected");
 // End-of-list wraps to image zero, using its actual cache slot.
 dut.current_image=2;settle();if(!valid || slot!=0)$fatal(1,"last image does not wrap");
 dut.current_image=6;settle();if(valid)$fatal(1,"award offers a photo preview");
 dut.current_image=0;dut.image_count=1;settle();if(valid)$fatal(1,"single image offers a preview");
 dut.image_count=3;settle();if(!valid)$fatal(1,"preview did not return");
 next=1;@(negedge clk);next=0;
 if(valid)$fatal(1,"queued navigation left the previous preview visible");
 // Failed transport never publishes its partially generated thumbnail.
 dut.state_flags=16'd128;dut.nav_pending=0;dut.display_pending=0;
 dut.cache_valid=1;dut.receive_slot=1;dut.target=1;dut.done_seen=1;dut.end_seen=1;
 dut.expected_crc=32'h11111111;dut.received_crc=32'h22222222;
 @(negedge clk);
 if(dut.error!=4 || dut.cache_valid[1] || valid)$fatal(1,"bad CRC published next thumbnail");
 $display("PASS preview cache identity: next slot, wrap, award/single-photo exclusion, queued navigation and failed CRC");
 $finish;
end
initial begin #100000;$fatal(1,"cache-control timeout");end
endmodule
