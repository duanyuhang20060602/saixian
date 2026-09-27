`timescale 1ns/1ps
module tb_startup_error_policy;
reg clk=0;always #5 clk=~clk;
reg rst=1,initialized=0;reg [2:0] fault=0;
wire [2:0] reported_error;wire initializing;
saixian_startup_error_policy dut(.*);
task step;input [2:0] code;begin @(negedge clk);fault=code;repeat(3) @(negedge clk);end endtask
initial begin
 repeat(3) @(negedge clk);rst=0;
 step(2);
 if(reported_error!=0 || !initializing || dut.boot_e02_count!=1) $fatal(1,"First E02 not classified as startup retry");
 repeat(20) @(negedge clk);
 if(dut.boot_e02_count!=1 || reported_error!=0) $fatal(1,"Repeated level counted as multiple failures");
 step(0);step(2);
 if(reported_error!=2 || dut.boot_e02_count!=2) $fatal(1,"Second E02 hidden");
 step(0);step(2);
 if(reported_error!=2 || dut.boot_e02_count!=2) $fatal(1,"Persistent failures wrapped counter");
 step(1);if(reported_error!=1) $fatal(1,"E01 hidden");
 step(3);if(reported_error!=3) $fatal(1,"E03 hidden");
 step(4);if(reported_error!=4) $fatal(1,"E04 hidden");
 step(0);initialized=1;repeat(3) @(negedge clk);
 if(initializing || dut.boot_e02_count!=0) $fatal(1,"Success did not clear startup counter");
 initialized=0;step(2);
 if(reported_error!=2 || initializing) $fatal(1,"Runtime E02 incorrectly treated as first startup failure");
 rst=1;repeat(2) @(negedge clk);rst=0;step(2);
 if(reported_error!=0 || !initializing) $fatal(1,"Global reset did not restore startup policy");
 $display("PASS first/second/persistent E02, no level double-count, other errors, success clear and runtime reporting");$finish;
end
endmodule
