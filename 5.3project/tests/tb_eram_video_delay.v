`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,de=0;always #5 clk=~clk;
reg [23:0] pixel=0;wire [23:0] actual,reference,tap7,tap12;
photo_neutral_delay dut(clk,rst,de,pixel,actual);
photo_neutral_delay_ref frozen(clk,rst,de,pixel,reference);
photo_award_delay award(clk,rst,pixel,tap12,tap7);
reg [23:0] old_award[0:11];integer i,n,checks=0;reg [31:0] random_state=32'h3719a721;
always @(posedge clk)begin
 if(rst)for(i=0;i<12;i=i+1)old_award[i]<=0;
 else begin old_award[0]<=pixel;for(i=1;i<12;i=i+1)old_award[i]<=old_award[i-1];end
end
initial begin
 repeat(4)@(negedge clk);rst=0;
 for(n=0;n<1300000;n=n+1)begin
  @(negedge clk);
  random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
  pixel=random_state[23:0];de=n%1650<1280 && (n/1650)%750<720;
  rst=n%71237==19 || n%71237==20;
  // Also reset between clock edges. The neutral path resets immediately;
  // the award path retains its original synchronous-reset interface.
  if(n%131071==31)begin #1;rst=1;#1;if(actual!==reference)$fatal(1,"asynchronous reset mismatch");#1;rst=0;end
  @(posedge clk);#1;
  if(actual!==reference)$fatal(1,"neutral latency/data mismatch at %0d",n);
  if(tap7!==old_award[6] || tap12!==old_award[11])$fatal(1,"award taps changed at %0d got %h/%h expected %h/%h",n,tap7,tap12,old_award[6],old_award[11]);
  checks=checks+1;
 end
 $display("PASS eRAM video delays: %0d pixels, 7/12/15-clock taps, blanking and synchronous/asynchronous resets",checks);$finish;
end
endmodule
