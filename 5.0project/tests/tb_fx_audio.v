`timescale 1ns/1ps
module tb_fx_audio;
reg ca=0,cb=0;always #6.666667 ca=~ca;always #5 cb=~cb;
reg rst=1,repair_enable=0,page=0;wire [2:0] page_count;wire page_valid,page_ready;wire [3:0] received_style;reg [3:0] style=0;integer accepted=0,started=0,controls=0;
wire sclk,cs,mosi,miso,req,bg,rep,prepare,pop,enabled,packet;
wire [7:0] epoch;wire [2:0] track;wire [3:0] volume,cue;
wire [31:0] raw,processed;wire empty,full;wire [13:0] used;
integer av_commits=0;always @(negedge ca)if(!rst && a.av_commit)av_commits=av_commits+1;
reg wr=0;reg [31:0] wd=0;integer i,prepared=0,checked=0,head=0,tail=0,clock_count=0,last_prepare=0;
reg [31:0] expected[0:8191];reg was_mix=0;
photo_audio_fifo #(.RAM32_HEAD(8192)) fifo(.clk(cb),.rst(rst),.write_en(wr),.write_data(wd),.read_en(pop),.data(raw),.empty(empty),.full(full),.used(used));
photo_audio_spi_a #(.FIFO_AW(11),.FIFO_RAM32_HEAD(2048),.EXTENDED_AV(1),.PAGE_CUE(1),.TYPED_PAGE(1)) a(.av_available(1'b1),.playback_hold(1'b0),.clk(ca),.rst(rst),.next_track(1'b0),.bg_enable(1'b1),.repair_enable(repair_enable),.volume(4'd8),.cue_event(4'd0),
 .page_style(style),.page_event(page),.spi_miso(miso),.spi_sclk(sclk),.spi_cs(cs),.spi_mosi(mosi));
photo_audio_spi_b #(.EXTENDED_AV(1),.PAGE_CUE(1),.TYPED_PAGE(1)) b(.av_data(32'd0),.clk(cb),.rst(rst),.spi_sclk(sclk),.spi_cs(cs),.spi_mosi(mosi),.spi_miso(miso),.packet_active(packet),
 .active_epoch(epoch),.active_track(3'd0),.track_count(3'd1),.switching(1'b0),.fifo_used(used),.processed_pcm(processed),.bg_enabled(enabled),
 .sample_prepare(prepare),.fifo_read(pop),.request_valid(req),.request_epoch(epoch),.request_track(track),.request_bg(bg),.request_repair(rep),.request_volume(volume),.request_cue(cue),.page_cue_count(page_count),.page_valid(page_valid),.page_style(received_style),.page_ready(page_ready));
photo_audio_processing_b #(.PAGE_CUE(1),.TYPED_PAGE(1),.SHARED_SCALE(1)) p(.clk(cb),.rst(rst),.prepare(prepare),.request_valid(req),.request_epoch(epoch),.request_bg(bg),.request_repair(rep),
 .request_volume(volume),.request_cue(cue),.raw_pcm(raw),.processed_pcm(processed),.bg_enabled(enabled),.page_cue_count(page_count),.background_available(1'b1),.page_valid(page_valid),.page_style(received_style),.page_ready(page_ready));
always @(posedge cb) if(!rst) begin
 clock_count=clock_count+1;
 if(page_valid)begin
  if(received_style!==accepted%11)$fatal(1,"wrong event style %0d expected %0d",received_style,accepted%11);
  accepted=accepted+1;
 end
 if(p.cue_pulse==6)started=started+1;
 if(b.request_valid && b.control_only)controls=controls+1;
 if(prepare)begin
  if(prepared>0 && clock_count-last_prepare<320)$fatal(1,"repair input spacing");
  prepared=prepared+1;last_prepare=clock_count;
 end
end
// Queue the final B pipeline result before SPI consumes it. Compare the
// independently clocked A receiver's actual packet payload with this queue.
always @(negedge cb) if(!rst) begin
 if(was_mix)begin expected[tail]=processed;tail=tail+1;end
 was_mix=p.scale_phase==2;
end
always @(negedge ca) if(!rst && a.fifo_write)begin
 if(head>=tail)$fatal(1,"SPI consumed sample before repair completed");
 if(a.fifo_input!==expected[head])$fatal(1,"stale/corrupt PCM at %0d got %h expected %h",head,a.fifo_input,expected[head]);
 if(head<32 && a.fifo_input!==0)$fatal(1,"dry warmup not zero");
 if(head>=32 && head<200 && a.fifo_input!=={16'(1000-(head-32)),16'(1000+(head-32))})$fatal(1,"dry delay/stereo mismatch %0d",head);
 head=head+1;checked=checked+1;
end
initial begin
 repeat(5)@(negedge cb);rst=0;
 for(i=0;i<6144;i=i+1)begin @(negedge cb);wr=1;wd={16'(1000-i),16'(1000+i)};end
 @(negedge cb);wr=0;
 wait(checked>=256);
 // During active PCM and metadata packets; sequence wraps past seven.
 for(i=0;i<11;i=i+1)begin
  @(negedge ca);style=i;page=1;@(negedge ca);page=0;
  wait(a.typed_valid);wait(!a.typed_valid && !a.page_inflight);repeat(3)@(negedge ca);
 end
 wait(checked>=2048);
 if(accepted!=11 || started+p.pending_pages.used!=11)$fatal(1,"lost/duplicate page events accepted=%0d started=%0d pending=%0d",accepted,started,p.page_pending);
 if(a.desired_epoch!=1 || a.packet_errors!=0 || a.underflows!=0 || controls<11)$fatal(1,"page event disturbed PCM epoch/FIFO/packet stream");
 if(!p.cue_busy || a.play_position==0)$fatal(1,"cue/playback not running");
 $display("PASS page cue dual-clock SPI: 11 actual events, 11 styles, seq wrap/ACK/retry dedup/backpressure, control-only no PCM consume, exact PCM payload, no epoch reset or underflow");$finish;
end
initial begin #500000000;$fatal(1,"transport timeout");end
endmodule
