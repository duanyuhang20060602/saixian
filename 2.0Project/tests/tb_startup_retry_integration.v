`timescale 1ns/1ps
module tb_startup_retry_integration;
reg clk=0;always #5 clk=~clk;
reg rst=1;wire [2:0] error_code,raw_error;
wire initializing;
saixian_startup_error_policy policy(.clk(clk),.rst(rst),.initialized(dut.sd_init_done),
 .fault(raw_error),.reported_error(error_code),.initializing(initializing));
sd_card_bmp #(.CLK_FREQ_HZ(10)) dut(
 .clk(clk),.rst(rst),.prev_req_toggle(1'b0),.next_req_toggle(1'b0),.carousel_mode(1'b1),
 .display_commit_toggle(1'b0),.write_finish_toggle(1'b0),.audio_track_index(3'd0),
 .audio_track_toggle(1'b0),.audio_fifo_wrusedw(9'd0),.bmp_width(16'd1280),.bmp_height(16'd720),
 .write_req_ack(1'b0),.SD_MISO(1'b1),.error_code(raw_error));
integer count=0;
initial begin
 force dut.sd_init_done=0;force dut.init_stage=2;
 force dut.bmp_ready=0;force dut.scan_done=0;
 force dut.scan_found_valid=0;force dut.audio_scan_found_valid=0;
 force dut.bmp_data_wr_en=0;
 repeat(3) @(negedge clk);rst=0;
 wait(raw_error==2);repeat(2) @(negedge clk);
 if(error_code!=0 || dut.recovery_timer==0) $fatal(1,"First E02 did not retain internal recovery");
 wait(dut.op_abort);@(negedge clk);
 if(raw_error!=0 || error_code!=0 || dut.init_timer>1) $fatal(1,"Original recovery/reset timing changed");
 wait(raw_error==2);repeat(2) @(negedge clk);
 if(error_code!=2) $fatal(1,"Second real initialization timeout not reported");
 force dut.sd_init_done=1;repeat(3) @(negedge clk);
 if(error_code!=0 || initializing) $fatal(1,"Successful initialization did not clear state");
 force dut.sd_init_done=0;
 wait(raw_error==2);@(negedge clk);
 if(error_code!=2) $fatal(1,"Runtime error hidden");
 $display("PASS SD scheduler integration: unchanged first timeout recovery/reset, second timeout report, success and runtime error");$finish;
end
initial begin #10000;$fatal(1,"Integration timeout");end
endmodule
