`timescale 1ns/1ps
// Scheduler unit test: SPI/BMP engine responses are controlled independently.
module tb_boot_load_order;
reg clk=0;always #5 clk=~clk;
reg rst=1;
sd_card_bmp dut(.clk(clk),.rst(rst),.prev_req_toggle(1'b0),.next_req_toggle(1'b0),
 .carousel_mode(1'b1),.display_commit_toggle(1'b0),.write_finish_toggle(1'b0),
 .audio_track_index(3'd0),.audio_track_toggle(1'b0),.audio_fifo_wrusedw(9'd0),
 .bmp_width(16'd1280),.bmp_height(16'd720),.write_req_ack(1'b0),.SD_MISO(1'b0));
initial begin
 force dut.sd_init_done=1;force dut.scan_done=1;force dut.bmp_ready=1;
 force dut.scan_found_valid=0;force dut.audio_scan_found_valid=0;
 force dut.bmp_data_wr_en=0;force dut.wrfin_pulse=0;force dut.commit_pulse=0;
 repeat(3) @(negedge clk);rst=0;
 force dut.scan_kicked=1;force dut.image_count=2;
 force dut.image_sector0=32'h1000;force dut.sprint_background_sector=32'h2000;
 force dut.sprint_background_found=1;force dut.sprint_background_ready=0;
 force dut.display_committed=0;
 @(negedge clk);
 if(dut.load_sector!==32'h1000 || dut.write_buf_idx!==0 || dut.loading_sprint_background)
  $fatal(1,"sprint background delayed first carousel picture");
 force dut.load_busy=0;force dut.awaiting_commit=0;force dut.display_committed=1;
 @(negedge clk);
 if(dut.load_sector!==32'h2000 || dut.write_buf_idx!==2 || !dut.loading_sprint_background)
  $fatal(1,"dedicated sprint background not loaded after first picture");
 $display("PASS first carousel picture before dedicated sprint background; buffers remain separate");$finish;
end
endmodule
