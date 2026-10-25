`timescale 1ns/1ps
module tb_audio_visual_real;
reg clk=0;always #5 clk=~clk;
reg rst=1,sv=0;reg signed [15:0] l=0,r=0;
reg [4:0] band=0;wire [6:0] height,peak;wire valid,done;
integer fc=0;wire ft=fc==49999;
always @(posedge clk)if(rst)fc<=0;else fc<=ft ? 0:fc+1;
saixian_av_fft fft(.clk(clk),.rst(rst),.frame_tick(ft),.sample_valid(sv),.left(l),.right(r),.read_band(band),.read_height(height),.read_peak(peak),.valid(valid),.block_done(done));
reg wrst=1,wsv=0;reg signed [15:0] wl=0,wr=0;reg [7:0] idx=0;wire [31:0] extrema;wire wvalid;
saixian_av_wave wave(.clk(clk),.rst(wrst),.frame_tick(ft),.sample_valid(wsv),.left(wl),.right(wr),.read_index(idx),.read_extrema(extrema),.valid(wvalid));
integer scenario,i,j,h15,h24,maxh;real a;
task fft_sample;
 input integer x,y;
 begin @(negedge clk);l=x;r=y;sv=1;@(negedge clk);sv=0;repeat(399)@(negedge clk);end
endtask
initial begin
 for(scenario=0;scenario<3;scenario=scenario+1)begin
  rst=1;repeat(5)@(negedge clk);rst=0;
  for(i=0;i<1024;i=i+1)begin
   a=6.283185307179586*i/1024;
   if(scenario==0)fft_sample($rtoi(12000*$sin(21*a)),$rtoi(12000*$sin(128*a)));
   else if(scenario==1)fft_sample($rtoi(12000*$sin(21*a)),-$rtoi(12000*$sin(21*a)));
   else fft_sample(12000,-8000);
  end
  wait(done);repeat(150001)@(negedge clk);
  if(!valid)$fatal(1,"FFT snapshot missing");maxh=0;
  for(j=0;j<32;j=j+1)begin
   band=j;repeat(3)@(negedge clk);
   if(height>maxh)maxh=height;if(j==15)h15=height;if(j==24)h24=height;
  end
  if(scenario==0 && (h15<25 || h24<25))$fatal(1,"stereo bands missing %0d %0d",h15,h24);
  if(scenario==1 && h15<25)$fatal(1,"antiphase cancelled %0d",h15);
  if(scenario==2 && maxh>2)$fatal(1,"DC leakage %0d",maxh);
  $display("FFT scenario %0d band15=%0d band24=%0d max=%0d",scenario,h15,h24,maxh);
 end
 wrst=0;
 for(i=0;i<1030;i=i+1)begin
  @(negedge clk);wsv=1;wl=i[0] ? 12000:-12000;wr=i[0] ? 8000:-8000;
  @(negedge clk);wsv=0;
 end
 wait(wvalid);repeat(3)@(negedge clk);
 for(j=0;j<256;j=j+1)begin
  idx=j;repeat(3)@(negedge clk);
  if(extrema!==32'hd12ee01f)$fatal(1,"wave min/max %0d got %h",j,extrema);
 end
 $display("PASS real FFT stereo bands, antiphase, DC rejection, 256 stereo extrema");$finish;
end
initial begin #40000000;$fatal(1,"visual timeout");end
endmodule
