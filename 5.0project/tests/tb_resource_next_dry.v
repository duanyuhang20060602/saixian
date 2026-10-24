`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,write_frame=0,read_first=0,read_second=0;
reg[31:0] wd=0;wire[31:0] rd;
reg[31:0] samples[0:5999];
integer era,n,gap,checked=0,wraps=0,head_reads=0,tail_reads=0;
always #5 clk=~clk;
saixian_pitch_dry_delay dut(.*);
initial begin
 for(era=0;era<3;era=era+1)begin
  rst=1;write_frame=0;read_first=0;read_second=0;
  repeat(3)@(negedge clk);rst=0;
  for(n=0;n<(era==0 ? 1025:6000);n=n+1)begin
   samples[n]=$random;wd=samples[n];write_frame=1;
   @(negedge clk);write_frame=0;wd=~samples[n];
   // First reset interrupts the final tail write, not just an idle gap.
   if(era==0 && n==1024)rst=1;
   gap=2+($random & 31);repeat(gap)@(negedge clk);
   if(!rst)begin
    read_first=1;@(negedge clk);read_first=0;read_second=1;
    @(negedge clk);read_second=0;
    if(n>=1152)begin
     if(rd!==samples[n-1152])$fatal(1,"dry delay mismatch era=%0d n=%0d got=%h expected=%h",era,n,rd,samples[n-1152]);
     checked=checked+1;
     if(dut.pointer[10])tail_reads=tail_reads+1;else head_reads=head_reads+1;
     if(dut.pointer==0)wraps=wraps+1;
    end
   end
   repeat(2)@(negedge clk);
  end
 end
 if(wraps<8 || head_reads<8000 || tail_reads<1000)$fatal(1,"dry coverage incomplete");
 $display("PASS %0d exact stereo frames delayed 1152 samples, %0d full wraps, %0d head/%0d tail reads, changing write data, randomized idle spacing and reset during tail write",checked,wraps,head_reads,tail_reads);$finish;
end
initial begin #10000000;$fatal(1,"dry test timeout");end
endmodule
