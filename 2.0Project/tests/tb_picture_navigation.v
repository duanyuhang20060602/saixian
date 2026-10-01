`timescale 1ns/1ps
// Control the reader's completion independently from requests. The oracle is
// the requested image sequence, not the scheduler's choice of prefetch slots.
module tb_picture_navigation;
reg clk=0; always #5 clk=~clk;
reg rst=1,prev=0,next=0,commit=0,finish=0;
sd_card_bmp #(.CLK_FREQ_HZ(1000)) dut(
 .clk(clk),.rst(rst),.prev_req_toggle(prev),.next_req_toggle(next),
 .carousel_mode(1'b1),.display_commit_toggle(commit),.write_finish_toggle(finish),
 .audio_track_index(3'd0),.audio_track_toggle(1'b0),.audio_fifo_wrusedw(9'd0),
 .bmp_width(16'd1280),.bmp_height(16'd720),.write_req_ack(1'b0),.SD_MISO(1'b0));
reg old_ready;
task reset_model;
begin
 rst=1;prev=0;next=0;commit=0;finish=0;
 force dut.sd_init_done=1;force dut.scan_done=1;force dut.bmp_ready=0;
 force dut.scan_found_valid=0;force dut.audio_scan_found_valid=0;
 force dut.bmp_data_wr_en=0;
 repeat(3) @(negedge clk);rst=0;
 force dut.scan_kicked=1;force dut.image_count=5;
 force dut.image_sector0=32'h1000;force dut.image_sector1=32'h2000;
 force dut.image_sector2=32'h3000;force dut.image_sector3=32'h4000;
 force dut.image_sector4=32'h5000;
 force dut.image_width0=1280;force dut.image_height0=720;
 force dut.image_width1=1920;force dut.image_height1=1080;
 force dut.image_width4=640;force dut.image_height4=480;
 repeat(4) @(negedge clk);
 dut.display_committed=1;dut.current_image=0;dut.desired_image=0;
 dut.current_buf=0;dut.load_busy=0;dut.awaiting_commit=0;
 dut.cache_valid=4'b0001;dut.cached_image[0]=0;
end
endtask
task press_next;
begin next=~next;repeat(5) @(negedge clk);end
endtask
task press_previous;
begin prev=~prev;repeat(5) @(negedge clk);end
endtask
task commit_frame;
begin commit=~commit;repeat(5) @(negedge clk);end
endtask
initial begin
 reset_model;
 // A cached previous image must respond even while the next image is loading.
 dut.cache_valid=4'b1001;dut.cached_image[3]=4;
 dut.load_busy=1;dut.loading_image=1;dut.write_buf_idx=1;
 dut.load_initial=0;dut.source_started=1;dut.source_done=0;
 old_ready=dut.frame_ready_toggle;
 press_previous;
 if(!dut.awaiting_commit || dut.ready_buf_idx!=3 || dut.pending_image!=4 ||
    dut.frame_ready_toggle==old_ready || !dut.load_busy)
  $fatal(1,"cached previous request blocked by unrelated TF load");
 // Complete that unrelated read before committing the selected image.
 force dut.bmp_ready=1;finish=~finish;repeat(5) @(negedge clk);
 if(dut.pending_image!=4 || !dut.cache_valid[1] || dut.cached_image[1]!=1)
  $fatal(1,"background completion replaced selected image metadata");
 force dut.bmp_ready=0;commit_frame;
 if(dut.current_image!=4 || dut.current_buf!=3 || dut.source_width!=640 || dut.source_height!=480)
  $fatal(1,"slot 3 promotion or source dimensions wrong");
 press_next;
 if(!dut.awaiting_commit || dut.ready_buf_idx!=0 || dut.pending_image!=0)
  $fatal(1,"old visible image was discarded instead of cached for reversal");
 commit_frame;

 // Five same-direction clicks during a slow load must retain the next image,
 // rather than wrapping the target back to the still-visible frame. A later
 // reverse click replaces that target; the old load must not be displayed.
 reset_model;
 dut.load_busy=1;dut.loading_image=1;dut.write_buf_idx=1;
 dut.load_initial=0;dut.source_started=1;dut.source_done=0;
 old_ready=dut.frame_ready_toggle;
 repeat(5) press_next;
 if(dut.desired_image!=1) $fatal(1,"five-click backlog cancelled next image");
 press_previous;
 if(dut.desired_image!=4) $fatal(1,"latest direction did not refer to visible frame");
 force dut.bmp_ready=1;finish=~finish;repeat(5) @(negedge clk);
 if(dut.frame_ready_toggle!=old_ready || dut.awaiting_commit || dut.current_image!=0)
  $fatal(1,"obsolete loaded image was displayed");
 if(!dut.load_busy || dut.load_sector!=32'h5000 || dut.loading_image!=4 || dut.write_buf_idx==0 || dut.write_buf_idx==2)
  $fatal(1,"latest target not loaded into a safe carousel slot");

 // The first manually requested miss must beat the dedicated backdrop.
 reset_model;dut.sprint_background_found=1;dut.sprint_background_ready=0;
 press_next;force dut.bmp_ready=1;repeat(2) @(negedge clk);
 if(!dut.load_busy || dut.load_sector!=32'h2000 || dut.write_buf_idx==2 || dut.load_prefetch)
  $fatal(1,"manual request delayed behind optional background load");

 // Populate both neighbours without overwriting the current frame or the
 // neighbour already ready. No extra on-chip frame storage is involved.
 reset_model;dut.sprint_background_found=0;
 force dut.bmp_ready=1;repeat(2) @(negedge clk);
 if(dut.loading_image!=1 || dut.write_buf_idx!=1)
  $fatal(1,"next prefetch allocation wrong: image=%d slot=%d busy=%d target=%d reload=%d",dut.loading_image,dut.write_buf_idx,dut.load_busy,dut.desired_image,dut.reload_first_after_scan);
 force dut.bmp_ready=0;repeat(2) @(negedge clk);
 force dut.bmp_ready=1;finish=~finish;repeat(5) @(negedge clk);
 if(!dut.cache_valid[1] || dut.cached_image[1]!=1 || dut.loading_image!=4 || dut.write_buf_idx!=3)
  $fatal(1,"previous prefetch overwrote visible/next frame");
 force dut.bmp_ready=0;repeat(2) @(negedge clk);
 force dut.bmp_ready=1;finish=~finish;repeat(5) @(negedge clk);
 if(dut.load_busy || dut.cache_valid!=4'b1011 || dut.cached_image[3]!=4)
  $fatal(1,"two-neighbour cache did not settle");
 old_ready=dut.frame_ready_toggle;press_next;
 if(!dut.awaiting_commit || dut.pending_image!=1 || dut.ready_buf_idx!=1 || dut.frame_ready_toggle==old_ready)
  $fatal(1,"cached next failed to publish");
 $display("PASS navigation: cached prev/next during loads, slot 3, coalesced clicks/latest direction, no stale display, manual priority, both neighbours");
 $finish;
end
endmodule
