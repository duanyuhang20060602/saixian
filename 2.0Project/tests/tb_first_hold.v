`timescale 1ns/1ps
// Exercise initial presentation hold without simulating millions of
// already-tested decode/write handshakes. The normal clock still advances.
module tb_first_hold;
reg clk=0;always #5 clk=~clk;
reg rst=1,pause=0;wire start,pop,patch,pub,slot;wire [20:0] off,words,pa;wire [31:0] pd;
wire [3:0] error;wire [31:0] late;wire [5:0] source,descriptor;wire [4:0] state;
delta_player #(.INITIAL_HOLD_TICKS(100)) dut(clk,rst,1'b0,21'd472576,6'd27,
 start,off,words,1'b0,32'd0,1'b0,pop,patch,pa,pd,1'b0,pub,slot,1'b1,pause,error,late,source,descriptor,state,,1'b1);
reg [31:0] base;
initial begin
 repeat(4)@(negedge clk);rst=0;
 @(negedge clk);dut.state=7;dut.publish_toggle=1;dut.next_duration=40;dut.bootstrap=1;base=dut.clock_ticks;
 @(posedge clk);#1;if(dut.deadline!==base+140)$fatal(1,"initial hold duration wrong");
 @(negedge clk);dut.state=6;
 repeat(120)@(negedge clk);if(pub!=1)$fatal(1,"animation starts before first-image hold ends");
 repeat(25)@(negedge clk);if(pub!=0)$fatal(1,"animation never resumes from the first image");
 $display("PASS first-image hold: extra startup hold, then original frame schedule resumes");$finish;
end
endmodule
