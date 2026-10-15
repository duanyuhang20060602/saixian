`timescale 1ns/1ps
module tb_audio_transport_repair;
reg ca=0,cb=0;always #6.666667 ca=~ca;always #5 cb=~cb;
reg rst=1,repair_enable=0;
wire sclk,cs,mosi,miso,req,bg,rep,prepare,pop,enabled,packet;
wire [7:0] epoch;wire [2:0] track;wire [3:0] volume,cue;
wire [31:0] raw,processed;wire empty,full;wire [13:0] used;
reg wr=0;reg [31:0] wd=0;integer i,prepared=0,checked=0,head=0,tail=0,clock_count=0,last_prepare=0;
reg [31:0] expected[0:8191];reg was_mix=0;
photo_audio_fifo fifo(.clk(cb),.rst(rst),.write_en(wr),.write_data(wd),.read_en(pop),.data(raw),.empty(empty),.full(full),.used(used));
photo_audio_spi_a a(.clk(ca),.rst(rst),.next_track(1'b0),.bg_enable(1'b1),.repair_enable(repair_enable),.volume(4'd8),.cue_event(4'd0),
 .spi_miso(miso),.spi_sclk(sclk),.spi_cs(cs),.spi_mosi(mosi));
photo_audio_spi_b b(.clk(cb),.rst(rst),.spi_sclk(sclk),.spi_cs(cs),.spi_mosi(mosi),.spi_miso(miso),.packet_active(packet),
 .active_epoch(epoch),.active_track(3'd0),.track_count(3'd1),.switching(1'b0),.fifo_used(used),.processed_pcm(processed),.bg_enabled(enabled),
 .sample_prepare(prepare),.fifo_read(pop),.request_valid(req),.request_epoch(epoch),.request_track(track),.request_bg(bg),.request_repair(rep),.request_volume(volume),.request_cue(cue));
photo_audio_processing_b p(.clk(cb),.rst(rst),.prepare(prepare),.request_valid(req),.request_epoch(epoch),.request_bg(bg),.request_repair(rep),
 .request_volume(volume),.request_cue(cue),.raw_pcm(raw),.processed_pcm(processed),.bg_enabled(enabled));
always @(posedge cb) if(!rst) begin
 clock_count=clock_count+1;
 if(prepare)begin
  if(prepared>0 && clock_count-last_prepare<320)$fatal(1,"repair input spacing");
  prepared=prepared+1;last_prepare=clock_count;
 end
end
// Queue the final B pipeline result before SPI consumes it. Compare the
// independently clocked A receiver's actual packet payload with this queue.
always @(negedge cb) if(!rst) begin
 if(was_mix)begin expected[tail]=processed;tail=tail+1;end
 was_mix=p.mix_valid;
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
 for(i=0;i<2048;i=i+1)begin @(negedge cb);wr=1;wd={16'(1000-i),16'(1000+i)};end
 @(negedge cb);wr=0;
 wait(checked>=256);@(negedge ca);repair_enable=1;
 wait(checked>=768);if(!p.repair_enable || p.repair.wet!=256)$fatal(1,"repair control did not arrive");
 @(negedge ca);repair_enable=0;
 wait(checked>=1280);if(p.repair.wet!=0)$fatal(1,"repair fade off failed");
 if(a.packet_errors!=0)$fatal(1,"packet errors");
 $display("PASS dual SPI 1280 samples, dry delay, stereo, repair crossfade, deadlines");$finish;
end
initial begin #150000000;$fatal(1,"transport timeout");end
endmodule
