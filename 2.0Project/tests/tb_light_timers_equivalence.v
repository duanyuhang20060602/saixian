`timescale 1ns/1ps
module tb_light_timers_equivalence;
reg clk=0;always #5 clk=~clk;
reg rst=1,key_n=1;
wire press,press_ref,fast,fast_ref,one,one_ref;
saixian_key_debounce #(.CLK_FREQ_HZ(75000000)) dut(clk,rst,key_n,press);
saixian_key_debounce_ref #(.CLK_FREQ_HZ(75000000)) refkey(clk,rst,key_n,press_ref);
saixian_key_debounce #(.CLK_FREQ_HZ(3000),.DEBOUNCE_MS(1)) quick(clk,rst,key_n,fast);
saixian_key_debounce_ref #(.CLK_FREQ_HZ(3000),.DEBOUNCE_MS(1)) refquick(clk,rst,key_n,fast_ref);
saixian_key_debounce #(.CLK_FREQ_HZ(1000),.DEBOUNCE_MS(1)) single(clk,rst,key_n,one);
saixian_key_debounce_ref #(.CLK_FREQ_HZ(1000),.DEBOUNCE_MS(1)) refsingle(clk,rst,key_n,one_ref);
wire [5:0] sel,refsel;wire [7:0] data,refdata;
seg_scan scanner(clk,!rst,sel,data,8'h11,8'h22,8'h33,8'h44,8'h55,8'h66);
seg_scan_ref refscanner(clk,!rst,refsel,refdata,8'h11,8'h22,8'h33,8'h44,8'h55,8'h66);
integer checks=0,presses=0;
always @(posedge clk) begin
 #1;
 if({press,fast,one,sel,data} !== {press_ref,fast_ref,one_ref,refsel,refdata}) $fatal(1,"timer mismatch cycle %0d",checks);
 checks=checks+1;if(press) presses=presses+1;
end
initial begin
 if($bits(dut.count)!=21 || $bits(scanner.scan_timer)!=16) $fatal(1,"counter width incorrect");
 repeat(3) @(negedge clk);rst=0;
 repeat(8) begin @(negedge clk);key_n=!key_n;end
 @(negedge clk);key_n=0;
 repeat(1500020) @(negedge clk);
 key_n=1;repeat(1500020) @(negedge clk);
 key_n=0;repeat(1500020) @(negedge clk);
 if(presses!=2) $fatal(1,"wrong number of long debounce pulses: %0d",presses);
 $display("PASS %0d exact debounce/scan cycles, 75MHz 20ms, bounce, release, one-cycle and three-cycle parameters",checks);$finish;
end
endmodule
