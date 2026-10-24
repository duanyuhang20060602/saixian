`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,clear=0,sample_valid=0,enable=0;
reg signed[15:0] left_in=0,right_in=0;
wire signed[15:0] left_out,right_out,rl,rr;wire out_valid,rv;
integer i,j,seed=32'h1ec7017c,checked=0;
always #5 clk=~clk;
saixian_audio_repair dut(.*);
reference_audio_repair refdut(.clk(clk),.rst(rst),.clear(clear),.sample_valid(sample_valid),.enable(enable),
 .left_in(left_in),.right_in(right_in),.left_out(rl),.right_out(rr),.out_valid(rv));
reg[31:0] expected[0:5000];integer refs=0;
always @(negedge clk)if(!rst)begin
 if(rv)begin expected[refs]={rr,rl};refs=refs+1;end
 if(out_valid)begin
  if(checked>=refs || {right_out,left_out}!==expected[checked])
   $fatal(1,"repair PCM mismatch frame %0d got %h expected %h",checked,{right_out,left_out},expected[checked]);
  checked=checked+1;
 end
end
initial begin
 repeat(5)@(negedge clk);rst=0;
 for(i=0;i<5000;i=i+1)begin
  enable=(i/257)%2;left_in=$random(seed);right_in=$random(seed);
  if(i%64==0)begin left_in=-32768;right_in=32767;end
  sample_valid=1;@(negedge clk);sample_valid=0;
  for(j=0;j<599;j=j+1)begin
   if((i==799 && j==25)||(i==2600 && j==111))clear=1;
   else clear=0;
   @(negedge clk);
  end
 end
 if(checked<4900)$fatal(1,"coverage");
 $display("PASS %0d repair stereo frames bit-exact to frozen 5.4 (128 extra work clocks, same sample delay): extremes, random, toggles, wrap, mid-FIR clear",checked);$finish;
end
initial begin #40000000;$fatal(1,"repair equivalence timeout");end
endmodule
