`timescale 1ns/1ps
module tb_frame_handshake;
reg clk=0;always #5 clk=~clk;
reg rst=1,ack=0,raw_vs=1;
wire req,hs,vs,de;
video_timing_data dut(.video_clk(clk),.rst(rst),.read_req(req),
 .read_req_ack(ack),.hs(hs),.vs(vs),.de(de));
initial begin
 force dut.video_hs=1'b0;force dut.video_de=1'b0;force dut.video_vs=raw_vs;
 repeat(3) @(negedge clk);
 if({req,hs,vs,de}!==4'b0000) $fatal(1,"timing reset contains unknowns");
 rst=0;repeat(3) @(negedge clk);raw_vs=0;
 @(negedge clk);if(!req) $fatal(1,"frame request missing");
 #2 ack=1;
 @(negedge clk);if(!req) $fatal(1,"raw asynchronous ack used");
 @(negedge clk);if(!req) $fatal(1,"second-stage ack used too early");
 @(negedge clk);if(req) $fatal(1,"synchronized ack did not retire request");
 ack=0;repeat(3) @(negedge clk);raw_vs=1;repeat(3) @(negedge clk);
 raw_vs=0;@(negedge clk);if(!req) $fatal(1,"next frame request lost");
 $display("PASS timing-stage reset, two-stage asynchronous ack, repeated frame request");$finish;
end
endmodule
