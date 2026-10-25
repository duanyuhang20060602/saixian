`timescale 1ns/1ps
module tb_page_mix;
reg clk=0;always #5 clk=~clk;
reg rst=1,prepare=0,req=0,available=0;reg [7:0] epoch=0;
reg [3:0] volume=8,cue=0;reg [2:0] pages=0;wire [31:0] pcm;
integer i,j,nonzero=0,starts=0;
photo_audio_processing_b #(.PAGE_CUE(1)) dut(.clk(clk),.rst(rst),.prepare(prepare),.request_valid(req),.request_epoch(epoch),.request_bg(1'b1),.request_repair(1'b0),.request_volume(volume),.request_cue(cue),.raw_pcm(32'h12345678),.processed_pcm(pcm),.page_cue_count(pages),.background_available(available));
always @(negedge clk)if(!rst && dut.cue_pulse==6)starts=starts+1;
task frame;
begin @(negedge clk);prepare=1;@(negedge clk);prepare=0;
 repeat(330)@(negedge clk);end endtask
initial begin
 repeat(3)@(negedge clk);rst=0;
 @(negedge clk);req=1;epoch=1;pages=2;
 @(negedge clk);req=0;pages=0;
 // An epoch update and queued page can coincide; neither queued cue is lost.
 for(i=0;i<3000;i=i+1)begin frame;if(pcm!=0)nonzero=nonzero+1;end
 if(nonzero<1000 || starts!=2 || dut.page_pending!=0 || dut.cue_busy)$fatal(1,"standalone queued cue failed nonzero=%0d starts=%0d",nonzero,starts);
 for(i=0;i<40;i=i+1)frame;
 if(pcm!==0)$fatal(1,"unavailable background leaked raw FIFO data");
 @(negedge clk);req=1;epoch=2;volume=0;pages=1;
 @(negedge clk);req=0;pages=0;
 for(i=0;i<1500;i=i+1)begin frame;if(pcm!==0)$fatal(1,"page cue ignored mute");end
 if(starts!=3)$fatal(1,"muted cue queue stalled");
 $display("PASS B cue mixer: two queued complete cues without music, no stale PCM, epoch coincidence preserves queue, volume zero mutes cue");$finish;
end
initial begin #20000000;$fatal(1,"mixer timeout");end
endmodule
