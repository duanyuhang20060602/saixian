`timescale 1ns/1ps
module tb #(parameter BAUD=230400, FIFO_AW=11);
reg clk=0,rst=1,scan_done=0,hold_audio=1;always #5 clk=~clk;
wire sc,cs,mo,mi,catalog,ready,pop;wire[23:0] left,right;wire sv;
wire[7:0] epoch;wire[2:0] track;integer pushes=0,pops=0,clocks=0,before_push,before_pop;
wire boot_active;
photo_boot_screen #(.MIN_FRAMES(1),.VIDEO_DELAY(6),.STAGED_LOADING(1),.COMPLETE_SCAN(1)) boot(
 .clk(clk),.rst(rst),.frame_tick((clocks%128)==0),.x(12'd0),.y(11'd720),.memory_ready(1'b1),.catalog_ready(catalog),
 .frame_ready(1'b1),.animation_ready(1'b1),.audio_ready(ready),.scan_ready(catalog),.font_ready(1'b1),
 .photo_present(1'b1),.music_present(1'b1),.font_present(1'b1),.active(boot_active),.rgb());
photo_audio_spi_a #(.CLK_HZ(921600),.HALF_DIV(10),.FIFO_AW(FIFO_AW),.STARTUP_SYNC(1),.PAGE_CUE(1),.TYPED_PAGE(1),.EXTENDED_AV(1),.REMOTE_HMI(1)) a(
 .clk(clk),.rst(rst),.next_track(1'b0),.bg_enable(1'b1),.repair_enable(1'b0),.playback_hold(hold_audio),.volume(4'd5),.cue_event(4'd0),
 .spi_miso(mi),.spi_sclk(sc),.spi_cs(cs),.spi_mosi(mo),.catalog_complete(catalog),.buffer_ready(ready),.sample_valid(sv),.audio_left(left),.audio_right(right),
 .av_available(1'b0),.page_event(1'b0),.page_style(4'd0),.relief_enable(1'b0),.relief_available(1'b0),.relief_descriptor(32'd0),.hmi_status(53'd0),.hmi_ack_valid(1'b0),.hmi_ack_token(8'd0),.hmi_reset_request(1'b0));
photo_audio_spi_b_offload #(.CATALOG_STATUS(1),.PAGE_CUE(1),.TYPED_PAGE(1),.EXTENDED_AV(1),.REMOTE_HMI(1)) b(
 .clk(clk),.rst(rst),.spi_sclk(sc),.spi_cs(cs),.spi_mosi(mo),.spi_miso(mi),.catalog_complete(scan_done),
 .active_epoch(epoch),.active_track(3'd0),.track_count(3'd1),.switching(1'b0),.fifo_used(14'd4096),.processed_pcm(32'h12345678),.bg_enabled(1'b1),
 .fifo_read(pop),.request_epoch(epoch),.request_track(track),.av_data(32'd0),.page_ready(1'b1),.relief_ready(1'b0),.relief_descriptor(32'd0),.relief_data(32'd0),.hmi_session(32'd1),.hmi_header(32'd0),.hmi_payload(96'd0));
always @(posedge clk)if(!rst)begin
 clocks=clocks+1;if(a.fifo_write)pushes=pushes+1;if(pop)pops=pops+1;
 if(hold_audio && sv && (left!==0 || right!==0))$fatal(1,"preload audio leaked");
end
initial begin
 repeat(5)@(negedge clk);rst=0;
 wait(a.fifo_used>(1<<(FIFO_AW-1)) && cs);repeat(3000)@(negedge clk);
 if(!ready || catalog || !boot_active || boot.progress!=320)$fatal(1,"precondition not established");
 before_push=pushes;before_pop=pops;
 scan_done=1;
 repeat(30000)@(negedge clk);
 if(!catalog)$fatal(1,"DEADLOCK: A stopped status polling after audio preload filled; late scan completion cannot leave FONT3/3");
 if(boot_active)$fatal(1,"updated catalog failed to release real FONT3/3 loading page");
 if(pushes!=before_push || pops!=before_pop)$fatal(1,"status poll consumed PCM while held");
 if(!a.sample_ready || a.sample_word!==32'h12345678)$fatal(1,"held first sample lost");
 hold_audio=0;wait(sv);repeat(2)@(negedge clk);
 if(left!==24'h567800 || right!==24'h123400)$fatal(1,"first audible sample changed");
 if(a.packet_errors || a.underflows)$fatal(1,"SPI status polling error");
 $display("PASS delayed full-scan after preload saturation: real FONT3/3 page exits, no PCM consumed or overwritten, silent hold and exact first sample; FIFO_AW=%0d",FIFO_AW);$finish;
end
initial begin #20000000;$fatal(1,"catalog-poll test timeout pushes=%d fifo=%d errors=%d",pushes,a.fifo_used,a.packet_errors);end
endmodule
