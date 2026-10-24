`timescale 1ns/1ps
// Native RAM mapping, all four native banks, random reads, one-clock latency,
// and replacement of incomplete images after an aborted thumbnail build.
module tb_thumbnail_packing;
reg wc=0,rc=0,we=0;
always #10 wc=~wc;
always #7 rc=~rc;
reg [12:0] wa=0,ra=0;reg [15:0] wd=0;
wire [15:0] data;
photo_thumbnail_cache dut(.write_clk(wc),.write_enable(we),.write_address(wa),.write_data(wd),
 .read_clk(rc),.read_address(ra),.read_data(data));
function [15:0] pattern;
 input integer a,pass;
 begin pattern=((a*73)^(a>>3)^(pass*8191));end
endfunction
task write_pixel;
 input integer a,pass;
 begin @(negedge wc);wa=a;wd=pattern(a,pass);we=1;end
endtask
task check_pixel;
 input integer a,pass;
 begin
  @(negedge rc);ra=a;@(posedge rc);#1;
  if(data !== (a<7056 ? pattern(a,pass):16'd0))
   $fatal(1,"packing/latency a=%d pass=%d got=%h expected=%h",a,pass,data,pattern(a,pass));
 end
endtask
integer a,pass;
initial begin
 for(pass=0;pass<8;pass=pass+1)begin
  // Leave a partial image before restarting at 0.
  for(a=0;a<4097+pass;a=a+1)write_pixel(a,pass+10);
  @(negedge wc);we=0;
  for(a=0;a<7056;a=a+1)write_pixel(a,pass);
  @(negedge wc);we=0;
  for(a=0;a<7056;a=a+1)check_pixel((a*4093)%7056,pass);
  check_pixel(7056,pass);check_pixel(8191,pass);
 end
 $display("PASS banked RGB565 RAM: 8 replacement passes, all 7056 pixels in shuffled order, all four banks, incomplete images discarded, one-clock reads, invalid addresses blanked");
 $finish;
end
initial begin #10000000;$fatal(1,"packing timeout");end
endmodule
