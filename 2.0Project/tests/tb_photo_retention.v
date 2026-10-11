`timescale 1ns/1ps
module tb_photo_retention;
reg clk=0,rst=1,pause=0,carousel=0,next=0;
wire idle,cardreset;wire [3:0] state;wire ready;
always #5 clk=~clk;
sd_card_bmp #(.SHARED_SD_HOST(1),.TWO_PHOTO_BUFFERS(1)) dut(
 .clk(clk),.rst(rst),.shared_sd_initialized(1'b1),.shared_init_stage(3'd7),
 .shared_sector_data(8'd0),.shared_sector_valid(1'b0),.shared_sector_end(1'b0),
 .prev_req_toggle(1'b0),.next_req_toggle(next),.carousel_mode(carousel),.display_commit_toggle(1'b0),
 .bmp_width(16'd1280),.bmp_height(16'd720),.write_finish_toggle(1'b0),.write_req_ack(1'b0),
 .audio_fifo_wrusedw(9'd511),.audio_track_index(3'd0),.audio_track_toggle(1'b0),.SD_MISO(1'b1),
 .media_pause(pause),.media_idle(idle),.card_reset_request(cardreset));
integer i;reg saved_toggle;
initial begin
 force dut.scan_done=1;force dut.bmp_ready=1;force dut.scan_found_valid=0;force dut.audio_scan_found_valid=0;
 force dut.audio_sd_sec_read=0;force dut.bmp_sd_sec_read=0;
 repeat(3)@(negedge clk);rst=0;
 @(negedge clk);dut.scan_kicked=1;dut.image_count=5;dut.current_image=2;dut.desired_image=2;
 dut.current_buf=0;dut.display_committed=1;dut.cache_valid=3;
 dut.cached_image[0]=2;dut.cached_image[1]=3;dut.image_sector2=333;
 dut.audio_found_o=1;dut.audio_track_count_o=5;dut.audio_start_sector0=777;
 pause=1;saved_toggle=dut.frame_ready_toggle;
 repeat(50)@(negedge clk);
 if(!idle || cardreset || dut.scan_start_pulse || dut.load_issue_pending || dut.image_sector2!=333 ||
    dut.audio_start_sector0!=777 || dut.image_count!=5 || dut.cache_valid!=3 || dut.current_buf!=0)$fatal(1,"pause discarded metadata/cache");
 for(i=0;i<2;i=i+1)begin
  dut.current_buf=i;
  if(dut.buffer_to_fill(3)==i || dut.buffer_to_fill(3)==3)$fatal(1,"victim overwrites display/TF partition");
 end
 dut.current_buf=0;pause=0;carousel=1;
 repeat(10)@(negedge clk);
 if(dut.scan_start_pulse || dut.load_issue_pending || dut.frame_ready_toggle!=saved_toggle)$fatal(1,"return rescanned or reread cached photo");
 next=1;repeat(10)@(negedge clk);
 if(dut.frame_ready_toggle==saved_toggle || dut.ready_buf_idx!=1 || dut.load_busy)$fatal(1,"cached neighbour not published");
 $display("PASS retained photo: two-buffer partition/victim protection, cached return/neighbour, image and audio positions survive pause, zero rescan/reset");$finish;
end
endmodule
