`timescale 1ns/1ps
module tb_boot_diag;
reg clk=0;always #5 clk=~clk;
reg rst=1,ack=0,scanning=0,displayed=0;
reg [2:0] stage=1,error=0;
reg [5:0] command=8;reg [7:0] response=8'hff;
wire [39:0] data;wire toggle;
reg [39:0] held;
saixian_boot_diag #(.CLK_FREQ_HZ(10)) dut(.*);
task accept;begin
 @(negedge clk);ack=toggle;repeat(4) @(negedge clk);
end endtask
initial begin
 repeat(3) @(negedge clk);rst=0;
 repeat(5) @(negedge clk);held=data;
 stage=2;command=41;response=1;error=2;
 repeat(25) @(negedge clk);
 if(data!==held) $fatal(1,"CDC snapshot changed before ACK");
 accept;
 if(data[39:37]!=2 || data[36:33]!=1 || data[16:14]!=2 || data[13:8]!=41 || data[7:0]!=1)
  $fatal(1,"Error context not retained");
 error=0;stage=4;command=17;response=0;scanning=1;
 repeat(25) @(negedge clk);accept;
 if(data[39:37]!=2 || data[36:33]!=1 || data[13:8]!=41 || data[24:17]<2)
  $fatal(1,"Recovery cleared history / scan timer missing");
 displayed=1;accept;held=data;
 repeat(40) @(negedge clk);accept;
 if(data[32:17]!==held[32:17]) $fatal(1,"Timers did not freeze at first display");
 if(dut.bcd_inc(8'h09)!=8'h10 || dut.bcd_inc(8'h99)!=8'h99) $fatal(1,"BCD overflow");
 $display("PASS diagnostic snapshot ACK stability, error/R1 history, recovery, BCD timers and first-display freeze");
 $finish;
end
endmodule
