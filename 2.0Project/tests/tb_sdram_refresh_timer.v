`timescale 1ns/1ps
`include "../user_source/hdl_source/include/global_def.v"
module tb_sdram_refresh_timer;
reg clk=0;always #10 clk=~clk; // Actual 50 MHz SDRAM clock.
reg rst=1,ack=0,rw_valid=0;
wire request,refresh_valid;
sdr_init_ref dut(.Sdr_clk(clk),.Rst(rst),.Sdr_init_req(1'b0),
 .Sdr_init_mode(4'd0),.App_ref_req(1'b0),.Sdr_ref_ack(ack),
 .Sdr_rw_vld(rw_valid),.Sdr_ref_req(request),.Sdr_init_ref_vld(refresh_valid));
integer cycle=0,last=-1,count=0,period=0;
always @(negedge clk) if(!rst) begin
 cycle=cycle+1;
 if(request) begin
  if(last>=0) begin
   period=cycle-last;
   if(period!=765) $fatal(1,"wrong request cadence: %d",period);
   if(period*20*4096>64000000) $fatal(1,"4096 refresh budget violated");
  end
  last=cycle;count=count+1;
 end
end
initial begin
 if(`SDR_CLK_PERIOD!=20 || `SELF_REFRESH_INTERVAL!=764)
  $fatal(1,"macro precedence/counter period invalid: %d %d",`SDR_CLK_PERIOD,`SELF_REFRESH_INTERVAL);
 repeat(4) @(negedge clk);
 // Isolate refresh scheduling from the unchanged power-up sequence.
 force dut.init_done=1'b1;force dut.sdr_init_en=1'b0;force dut.init_vld=1'b0;
 rst=0;
 wait(count==4097);
 @(posedge clk);#1;
 if(period*20*4096!=62668800) $fatal(1,"wrong full refresh window");
 // Exercise actual production ack/valid logic, not a copied timer model.
 @(negedge clk);ack=1;rw_valid=1;
 @(posedge clk);#1;if(refresh_valid) $fatal(1,"refresh commandeered active transaction");
 @(negedge clk);rw_valid=0;
 @(posedge clk);#1;if(!refresh_valid) $fatal(1,"idle acknowledged refresh not active");
 @(negedge clk);ack=0;
 repeat(25) @(posedge clk);
 #1;if(refresh_valid) $fatal(1,"refresh valid not retired");
 @(negedge clk);rst=1;
 repeat(4) @(negedge clk);
 if(request || refresh_valid || dut.init_cnt!=0) $fatal(1,"reset did not clear refresh state");
 $display("PASS production SDRAM refresh timer: 4096 intervals in 62.6688 ms, ack/valid guard, retirement, reset; encrypted command decoder NOT modeled");
 $finish;
end
initial begin #70000000;$fatal(1,"refresh timeout");end
endmodule
