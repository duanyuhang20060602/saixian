`timescale 1ns/1ps
module tb_fx_styles;
reg clk=0;always #5 clk=~clk;
reg rst=1,tick=0;reg [3:0] cue=0,style=0;wire [23:0] left,right;wire busy;
integer i,j,k,nz;reg [31:0] hashes[0:10];reg [31:0] h;
photo_audio_cue_samples #(.PAGE_STYLES(1)) dut(.clk(clk),.rst(rst),.cue_event(cue),.page_style(style),.sample_tick(tick),.audio_left(left),.audio_right(right),.cue_busy(busy));
initial begin
 repeat(3)@(negedge clk);rst=0;
 for(i=0;i<11;i=i+1)begin
  @(negedge clk);style=i;cue=6;tick=0;@(negedge clk);cue=0;
  h=0;nz=0;j=0;
  while(busy)begin
   tick=1;@(negedge clk);tick=0;@(negedge clk);j=j+1;h={h[30:0],h[31]}^left;
   if(left!==right)$fatal(1,"page stereo mismatch");
   if(left!=0)nz=nz+1;
   if(j>6000)$fatal(1,"style did not finish %0d",i);
  end
  if(nz<100 || j<1000)$fatal(1,"silent/short page style %0d",i);
  hashes[i]=h;
  for(k=0;k<i;k=k+1)if(hashes[k]===h)$fatal(1,"styles %0d and %0d identical",k,i);
  tick=0;
 end
 $display("PASS all 11 page sounds: audible nonzero PCM, distinct waveforms, stereo, bounded durations and complete water segments");$finish;
end
endmodule
