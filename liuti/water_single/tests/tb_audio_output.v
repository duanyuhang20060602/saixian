`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;reg rst=1,tick=0,cycle=0;
reg[23:0] left=0,right=0;wire valid;wire[23:0] ol,orr;wire[1:0] mode;
water_audio_output d(clk,rst,tick,cycle,left,right,valid,ol,orr,mode);
integer n=0,seen=0,m,i,j;reg[23:0] el,er;reg signed[15:0] tone[0:47];
// Independent source uses the same registered timing as the real PCM player.
always @(posedge clk)if(!rst&&tick)begin left<=24'h128000+n;right<=24'hff3700-n;n=n+1;end
always @(posedge clk)if(!rst&&valid)begin
 if(^ol===1'bx||^orr===1'bx)$fatal(1,"unknown PCM output");
 case(mode)
  0:begin el=24'h128000+seen;er=24'hff3700-seen;end
  1:begin el=0;er=0;end
  2:begin el={tone[d.phase==0 ? 47:d.phase-1],8'd0};er=el;end
 endcase
 if(ol!==el||orr!==er)$fatal(1,"HDMI PCM valid/data alignment mode%0d sample%0d got%h/%h expected%h/%h",mode,seen,ol,orr,el,er);
 seen=seen+1;
end
initial begin
 for(j=0;j<48;j=j+1)tone[j]=$rtoi(4096*$sin(6.283185307179586*j/48)+(j<24 ? 0.5:-0.5));repeat(4)@(negedge clk);rst=0;
 for(m=0;m<4;m=m+1)begin
  for(i=0;i<96;i=i+1)begin tick=1;@(negedge clk);tick=0;repeat(7)@(negedge clk);end
  cycle=1;@(negedge clk);cycle=0;repeat(8)@(negedge clk);
 end
 if(seen!=384||mode!=1)$fatal(1,"audio diagnostic mode/count");
 $display("PASS HDMI audio output: 384 exact stereo strobes, registered-player alignment, music/silence/1kHz tone/music mode cycle");$finish;
end
endmodule
