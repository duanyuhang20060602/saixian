`timescale 1ns/1ps
module tb;
reg ca=0,cb=0;always #6.666667 ca=~ca;always #5 cb=~cb;
reg rst=1,stream_clear=0,bg_enable=1,repair_enable=0,next_track=0;
reg [3:0] user_volume=5;reg [2:0] mode=0;
wire sclk,cs,mosi,miso,request_valid,request_bg,request_repair,prepare,pop,enabled,packet;
wire [7:0] epoch;wire [2:0] track;wire [3:0] volume,cue;
wire [31:0] raw,pitched,processed;wire raw_pop,raw_empty,raw_full,pitch_ready,pitch_overrun;
wire [13:0] raw_used,pitched_used;wire [2:0] active_mode;
reg raw_write=0;reg [31:0] raw_word=0;integer serial=0,writer_clock=0;
integer accepted=0,sent=0,played=0,produced=0,tail=0,phase=0,last_sent=0;
reg [31:0] expected[0:127];reg scale_pending=0;
reg page_event=0;reg [3:0] page_style=0;wire page_valid,page_ready;wire [3:0] got_style;
wire [2:0] page_count;
photo_audio_fifo raw_fifo(.clk(cb),.rst(rst || stream_clear),.write_en(raw_write),.write_data(raw_word),
 .read_en(raw_pop),.data(raw),.empty(raw_empty),.full(raw_full),.used(raw_used));
photo_audio_pitch_b producer(.clk(cb),.rst(rst),.stream_clear(stream_clear || !enabled),
 .enable(1'b1),.repair_enable(request_repair),.requested_mode(mode),.raw_used(raw_used),.raw_pcm(raw),.raw_read(raw_pop),
 .output_read(pop),.output_pcm(pitched),.output_used(pitched_used),.ready(pitch_ready),.overrun(pitch_overrun),.active_mode(active_mode));
photo_audio_spi_a #(.FIFO_AW(11),.FIFO_RAM32_HEAD(2048),.STARTUP_SYNC(1),.EXTENDED_AV(1),.PAGE_CUE(1),.TYPED_PAGE(1)) a(
 .clk(ca),.rst(rst),.playback_hold(1'b0),.next_track(next_track),.bg_enable(bg_enable),.repair_enable(repair_enable),
 .volume(user_volume),.cue_event(4'd0),.spi_miso(miso),.spi_sclk(sclk),.spi_cs(cs),.spi_mosi(mosi),
 .av_available(1'b0),.page_event(page_event),.page_style(page_style));
photo_audio_spi_b #(.CATALOG_STATUS(1),.EXTENDED_AV(1),.PAGE_CUE(1),.TYPED_PAGE(1)) b(
 .clk(cb),.rst(rst),.spi_sclk(sclk),.spi_cs(cs),.spi_mosi(mosi),.spi_miso(miso),.packet_active(packet),
 .catalog_complete(1'b1),.active_epoch(epoch),.active_track(track),.track_count(3'd2),.switching(stream_clear),
 .fifo_used(pitched_used),.processed_pcm(processed),.bg_enabled(enabled),
 .sample_prepare(prepare),.fifo_read(pop),.request_valid(request_valid),.request_epoch(epoch),.request_track(track),
 .request_bg(request_bg),.request_repair(request_repair),.request_volume(volume),.request_cue(cue),
 .av_data(32'd0),.page_cue_count(page_count),.page_valid(page_valid),.page_style(got_style),.page_ready(page_ready));
photo_audio_processing_b #(.PAGE_CUE(1),.TYPED_PAGE(1),.SHARED_SCALE(1),.EXTERNAL_REPAIRED(1),.BOOSTED_VOLUME(1)) consumer(
 .clk(cb),.rst(rst),.prepare(prepare),.request_valid(request_valid),.request_epoch(epoch),.request_bg(request_bg),.request_repair(request_repair),
 .request_volume(volume),.request_cue(cue),.raw_pcm(pitched),.processed_pcm(processed),.bg_enabled(enabled),
 .page_cue_count(page_count),.background_available(1'b1),.page_valid(page_valid),.page_style(got_style),.page_ready(page_ready));
always @(negedge cb)begin
 if(rst || stream_clear)begin raw_write=0;writer_clock=0;end
 else begin
  writer_clock=writer_clock+1;raw_write=!raw_full && writer_clock%8==0;
  if(raw_write)begin raw_word={16'(2000-serial%3000),16'(serial%3000-1500)};serial=serial+1;end
 end
end
always @(posedge cb)if(!rst)begin
 if(raw_pop)accepted=accepted+1;
 if(producer.pitch_valid && producer.state==3)produced=produced+1;
 if(pitch_overrun)$fatal(1,"pitch input overrun");
 if(pop && pitched_used==0)$fatal(1,"empty pitch queue pop");
 if(pitched_used>256)$fatal(1,"pitch queue overflow");
end
always @(negedge cb)if(!rst)begin
 if(scale_pending)tail=tail+1;
 scale_pending=consumer.scale_phase==2;
 if(b.pcm_sent)begin
  if(tail<=last_sent)$fatal(1,"SPI deadline: result is stale");
  last_sent=tail;expected[b.word_index-2]=processed;
 end
end
always @(negedge ca)if(!rst)begin
 if(a.fifo_write)begin
  if(a.fifo_input!==expected[a.word_index-3])$fatal(1,"SPI order/data word %0d got %h expected %h",a.word_index-3,a.fifo_input,expected[a.word_index-3]);
  sent=sent+1;
 end
 if(a.sample_valid && a.playing)played=played+1;
end
task set_mode;
 input [2:0] value;
 begin @(negedge cb);mode=value;wait(active_mode==value && pitch_ready);end
endtask
task page;
 input [3:0] style;
 begin @(negedge ca);page_style=style;page_event=1;@(negedge ca);page_event=0;end
endtask
initial begin
 repeat(5)@(negedge cb);rst=0;
 wait(sent>=3072);if(!pitch_ready)$fatal(1,"warmup never completed");
 for(phase=1;phase<=4;phase=phase+1)begin set_mode(phase);page(phase);repeat(160000)@(negedge cb);end
 @(negedge ca);user_volume=0;wait(consumer.volume==0);repeat(200000)@(negedge cb);
 if(processed!==0)$fatal(1,"volume zero not silent");
 @(negedge ca);user_volume=8;repair_enable=1;wait(consumer.volume==8 && producer.repair.wet==256);
 repeat(200000)@(negedge cb);
 @(negedge ca);next_track=1;@(negedge ca);next_track=0;
 wait(cs);@(negedge cb);stream_clear=1;repeat(5)@(negedge cb);stream_clear=0;
 if(pitched_used!==0 || producer.pitch.fill!==0)$fatal(1,"track flush retains old history");
 wait(pitch_ready);repeat(200000)@(negedge cb);
 @(negedge ca);bg_enable=0;wait(!enabled);repeat(30000)@(negedge cb);
 if(pitched_used!==0 || producer.pitch.fill!==0)$fatal(1,"background stop leaves stale pitch history");
 page(8);repeat(200000)@(negedge cb);
 @(negedge ca);bg_enable=1;wait(enabled);set_mode(0);wait(pitch_ready);repeat(300000)@(negedge cb);
 if(a.packet_errors!=0 || a.underflows!=0)$fatal(1,"A errors/underflows %0d/%0d",a.packet_errors,a.underflows);
 if(sent<9000 || played<5000 || produced<8000)$fatal(1,"insufficient exercise %0d/%0d/%0d",sent,played,produced);
 $display("PASS dual 75/100MHz SPI %0d exact payloads, %0d playback ticks, %0d effect frames; five modes, typed cues, mute, boost, repair, background restart; zero underflows",sent,played,produced);$finish;
end
initial begin #1500000000;$fatal(1,"pitch transport timeout");end
endmodule
