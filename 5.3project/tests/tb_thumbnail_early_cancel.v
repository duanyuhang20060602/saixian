`timescale 1ns/1ps
module tb_thumbnail_early_cancel;
reg clk=0,rst=1,frame_tick=0,show=0,eligible=1,done=0;
reg [5:0] identity=5;wire req,cancel,visible,busy;wire [1:0] slot;
always #5 clk=~clk;
photo_thumbnail_overlay #(.SEPARATE_DISPLAY(1)) dut(
 .clk(clk),.rst(rst),.frame_tick(frame_tick),.enable(1'b1),.display_enable(show),
 .cache_valid(eligible),.cache_slot(identity[1:0]),.identity(identity),
 .de(1'b0),.x(12'd0),.y(11'd0),.request(req),.slot(slot),.cancel(cancel),
 .done(done),.data(16'hffff),.address(),.visible(visible),.rgb_in(24'd0),.rgb_out(),.read_busy(busy));
task clocks;input integer n;begin repeat(n)@(negedge clk);end endtask
task tick;begin frame_tick=1;clocks(1);frame_tick=0;clocks(1);end endtask
reg original_request;
initial begin
 clocks(5);rst=0;wait(busy);original_request=req;
 clocks(4);if(cancel || visible)$fatal(1,"hidden preparation cancelled");
 identity=10;clocks(2);if(!cancel || !busy)$fatal(1,"changed identity did not retain source lock");
 identity=5;clocks(2);if(!cancel || req!=original_request)$fatal(1,"cancellation lost or overlapped request");
 done=req;clocks(8);wait(busy && req!=done);
 if(visible)$fatal(1,"cancelled data visible");
 done=req;clocks(8);tick();if(visible || cancel || busy)$fatal(1,"completed hidden sample state wrong");
 show=1;clocks(2);if(visible)$fatal(1,"shown before frame boundary");
 tick();if(!visible)$fatal(1,"early sample not published at frame boundary");
 show=0;clocks(2);if(visible || !dut.ready)$fatal(1,"hiding display discarded prepared data");
 show=1;tick();if(!visible)$fatal(1,"prepared data did not return");
 eligible=0;clocks(2);if(visible || dut.ready)$fatal(1,"invalidated cache remained visible");
 $display("PASS early overlay: hidden prepare, sticky cancel/ack, no overlapping jobs, frame-boundary publication, hide/reuse, invalidation");$finish;
end
initial begin #100000;$fatal(1,"early overlay timeout");end
endmodule
