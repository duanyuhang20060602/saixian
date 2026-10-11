`timescale 1ns/1ps
module tb_audio_pipeline_equivalence;
reg clk=0,rst=1,clear=0,valid=0,en=0;
always #5 clk=~clk;
reg signed [15:0] li=0,ri=0;
wire signed [15:0] lo,ro,ref_l,ref_r;
wire ov,ref_valid;
integer i,j,outputs=0,checks=0,repaired=0;
saixian_audio_repair dut(clk,rst,clear,valid,en,li,ri,lo,ro,ov);
pre_pipeline_audio_repair reference(clk,rst,clear,valid,en,li,ri,ref_l,ref_r,ref_valid);
always @(posedge clk)begin
 #1;
 if({ov,lo,ro} !== {ref_valid,ref_l,ref_r})
  $fatal(1,"audio output/cycle mismatch sample %0d phase %0d",i,j);
 if(!rst && !clear)begin
  if(dut.clean_l!==reference.clean_l || dut.clean_r!==reference.clean_r)
   $fatal(1,"declick sample or phase changed");
  if(ov)outputs=outputs+1;
  if(dut.front_phase==4 && dut.clean_l!=dut.center_l)repaired=repaired+1;
  if(dut.front_phase==5 && dut.clean_r!=dut.center_r)repaired=repaired+1;
  checks=checks+1;
 end
end
initial begin
 repeat(4)@(negedge clk);rst=0;
 for(i=0;i<10000;i=i+1)begin
  for(j=0;j<320;j=j+1)begin
   @(negedge clk);valid=j==0;
   if(j==0)begin
    li=$random;ri=$random;
    case(i%37)
     0:begin li=-32768;ri=32767;end
     1:begin li=32767;ri=-32768;end
     2:begin li=0;ri=0;end
     3:begin li=255;ri=-256;end
     4:begin li=256;ri=-255;end
     6,8:begin li=100;ri=-100;end
     7,9,12,15:begin li=32767;ri=-32768;end
     10:begin li=99;ri=-99;end
     11:begin li=-127;ri=128;end
     13:begin li=128;ri=-127;end
     14:begin li=-128;ri=127;end
     16:begin li=128;ri=-129;end
    endcase
    if(i%173==0)en=~en;
   end
   // Clear every front/FIR phase across the run, including mid-multiply.
   clear=i%83==0 && j==(i%300)+1;
  end
 end
 @(negedge clk);valid=0;clear=0;
 repeat(350)@(negedge clk);
 if(outputs<9800)$fatal(1,"insufficient audio outputs %0d",outputs);
 if(repaired<100)$fatal(1,"insufficient actual spike repairs %0d",repaired);
 $display("PASS audio pipeline: %0d clock comparisons, %0d exact output pulses, %0d actual spike repairs, 10000 stereo samples, signed extremes, neighbor boundary 255/256, crossfade, every-phase clear, clean-sample and output timing unchanged",checks,outputs,repaired);
 $finish;
end
endmodule
