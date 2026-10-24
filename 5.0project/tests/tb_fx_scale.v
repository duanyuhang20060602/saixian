`timescale 1ns/1ps
module tb_fx_scale;
reg clk=0;always #5 clk=~clk;
reg rst=1,prepare=0,req=0,repair=0;reg [7:0] epoch=0;reg [3:0] volume=0;
reg [31:0] raw=0;wire [31:0] serial_pcm,parallel_pcm;
integer i,j;reg [31:0] expected;reg compare=0;
photo_audio_processing_b #(.SHARED_SCALE(1)) serial(.clk(clk),.rst(rst),.prepare(prepare),.request_valid(req),.request_epoch(epoch),.request_bg(1'b1),.request_repair(repair),.request_volume(volume),.request_cue(4'd0),.raw_pcm(raw),.processed_pcm(serial_pcm));
photo_audio_processing_b parallel(.clk(clk),.rst(rst),.prepare(prepare),.request_valid(req),.request_epoch(epoch),.request_bg(1'b1),.request_repair(repair),.request_volume(volume),.request_cue(4'd0),.raw_pcm(raw),.processed_pcm(parallel_pcm));
always @(posedge clk)begin
 compare=serial.scale_phase==2;
 #1;if(compare && serial_pcm!==expected)$fatal(1,"shared stereo scale mismatch got=%h expected=%h",serial_pcm,expected);
 if(serial.scale_phase==2)expected=parallel_pcm;
end
initial begin
 repeat(3)@(negedge clk);rst=0;
 for(i=0;i<180;i=i+1)begin
  @(negedge clk);req=1;epoch=epoch+1;volume=i%9;raw={$random};
  @(negedge clk);req=0;prepare=1;
  @(negedge clk);prepare=0;
  if(i%17==0)begin
   wait(serial.scale_phase==1);@(negedge clk);req=1;epoch=epoch+1;volume=(volume+3)%9;
   @(negedge clk);req=0;
  end
  repeat(400)@(negedge clk);
 end
 $display("PASS shared stereo scaler: 180 signed stereo frames, all 9 volumes, epoch changes between stereo phases, exact old PCM plus one pipeline clock");$finish;
end
endmodule
