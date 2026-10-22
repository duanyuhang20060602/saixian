`timescale 1ns/1ps
module tb_boot_audio_sync;
reg ca=0,cb=0;always #6.666667 ca=~ca;always #5 cb=~cb;
reg rst=1,scan_complete=0;reg [2:0] tracks=1;
wire sc,cs,mo,mi,req,bg,rep,prepare,pop,enabled,packet;
wire [7:0] epoch;wire [2:0] track;wire [3:0] volume,cue;
wire [31:0] raw,processed;wire empty,full;wire [13:0] used;
wire ready,catalog,active,sv;wire [23:0] al,ar;wire [23:0] boot_rgb;
reg released=0,wr=0;reg [31:0] wd=0;
integer frame_clock=0,i,played=0,sent=0,cycles=0,release_cycle=0,first_sample_cycle=0;
reg [31:0] expected[0:4095];reg [31:0] saved_first;integer saved_used;
wire frame_tick=frame_clock==0,first_pixel=frame_clock==100;
always @(posedge ca)if(rst)begin frame_clock<=0;released<=0;end
 else begin frame_clock<=frame_clock==1999 ? 0:frame_clock+1;
  if(!active && first_pixel)released<=1;
 end
photo_boot_screen #(.MIN_FRAMES(2)) boot(.clk(ca),.rst(rst),.frame_tick(frame_tick),.x(12'd0),.y(11'd720),
 .memory_ready(1'b1),.catalog_ready(1'b1),.frame_ready(ready || (catalog && tracks==0)),.active(active),.rgb(boot_rgb));
photo_audio_fifo fifo(.clk(cb),.rst(rst),.write_en(wr),.write_data(wd),.read_en(pop),.data(raw),.empty(empty),.full(full),.used(used));
photo_audio_spi_a #(.STARTUP_SYNC(1)) a(.clk(ca),.rst(rst),.next_track(1'b0),.bg_enable(1'b1),.repair_enable(1'b0),.volume(4'd8),.cue_event(4'd0),
 .playback_hold(!released),.buffer_ready(ready),.catalog_complete(catalog),.spi_miso(mi),.spi_sclk(sc),.spi_cs(cs),.spi_mosi(mo),.sample_valid(sv),.audio_left(al),.audio_right(ar));
photo_audio_spi_b #(.CATALOG_STATUS(1)) b(.clk(cb),.rst(rst),.catalog_complete(scan_complete),.spi_sclk(sc),.spi_cs(cs),.spi_mosi(mo),.spi_miso(mi),.packet_active(packet),
 .active_epoch(epoch),.active_track(3'd0),.track_count(tracks),.switching(1'b0),.fifo_used(used),.processed_pcm(processed),.bg_enabled(enabled),
 .sample_prepare(prepare),.fifo_read(pop),.request_valid(req),.request_epoch(epoch),.request_track(track),.request_bg(bg),.request_repair(rep),.request_volume(volume),.request_cue(cue));
photo_audio_processing_b p(.clk(cb),.rst(rst),.prepare(prepare),.request_valid(req),.request_epoch(epoch),.request_bg(bg),.request_repair(rep),
 .request_volume(volume),.request_cue(cue),.raw_pcm(raw),.processed_pcm(processed),.bg_enabled(enabled));
always @(negedge ca)if(!rst)begin
 cycles=cycles+1;
 if(a.fifo_write)begin expected[sent]=a.fifo_input;sent=sent+1;end
 if(released && release_cycle==0)release_cycle=cycles;
 if(sv)begin
  if(!released)begin
   if(al!==0 || ar!==0)$fatal(1,"music leaked into loading animation");
   if(a.sample_ready && a.sample_word!==expected[0])$fatal(1,"first sample consumed while held");
  end else if(a.playing)begin
   if(played>=sent)$fatal(1,"unbuffered playback");
   if({ar[23:8],al[23:8]}!==expected[played])$fatal(1,"lost/repeated startup sample %0d",played);
   if(played==0)first_sample_cycle=cycles;
   played=played+1;
  end
 end
end
initial begin
 repeat(5)@(negedge cb);rst=0;
 for(i=0;i<2048;i=i+1)begin @(negedge cb);wr=1;wd={16'(2000-i),16'(1000+i)};end
 @(negedge cb);wr=0;
 repeat(1000)@(negedge ca);if(!active || released)$fatal(1,"image-only startup escaped before audio");
 wait(played>=256);
 if(scan_complete || catalog)$fatal(1,"test must launch before full scan completes");
 if(first_sample_cycle-release_cycle>1600)$fatal(1,"audio did not start on next 48k tick");
 if(a.packet_errors || a.underflows)$fatal(1,"startup SPI errors/underflow");
 // A completed empty catalog must not deadlock a photo-only card.
 rst=1;tracks=0;scan_complete=1;wr=0;repeat(5)@(negedge cb);rst=0;
 wait(catalog);if(ready)$fatal(1,"empty music card falsely ready");
 wait(released);if(a.track_count!=0)$fatal(1,"empty catalog count");
 $display("PASS startup: silent preload, first sample preserved, first-track launch before scan end, frame-boundary release, empty-card exit");$finish;
end
initial begin #50000000;$fatal(1,"startup timeout");end
endmodule
