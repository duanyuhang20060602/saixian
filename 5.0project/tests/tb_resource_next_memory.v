`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg[11:0] address=0;wire[16:0] inv;reg[16:0] original[0:2047];
reg[13:0] ra=0,wa=0;reg we=0;reg[31:0] wd=0;wire[31:0] rd;
reg[13:0] ra_q=0,wa_q=0;reg we_q=0;reg[31:0] wd_q=0,expected=0;
reg[31:0] memory[0:1023];integer n,checked=0;
water_inverse_rom inverse(clk,address,inv);
water_cache #(.BANKS(1),.TAIL_HALF(1)) cache(clk,ra,wa,we,wd,rd);
always @(posedge clk)begin
 if(we_q)memory[wa_q[9:0]]<=wd_q;
 expected<=memory[ra_q[9:0]];
 ra_q<=ra;wa_q<=wa;we_q<=we;wd_q<=wd;
end
initial begin
 $readmemh("common/fluid/water_inverse.hex",original);
 for(n=0;n<1024;n=n+1)begin @(negedge clk);we=1;wa=n;wd=$random;end
 @(negedge clk);we=0;repeat(3)@(negedge clk);
 for(n=0;n<20000;n=n+1)begin
  address=n<4096 ? n:$random;ra=$random;ra[13:10]=0;wa=$random;wa[13:10]=0;wd=$random;we=(n%3)!=0;
  @(negedge clk);
  if(inv !== (address<2048 ? original[address]:17'd0))$fatal(1,"reciprocal mismatch %0d %h",address,inv);
  if(rd!==expected)$fatal(1,"native tail simultaneous read/write mismatch %0d %h %h",n,rd,expected);
  checked=checked+1;
 end
 $display("PASS %0d native RAM9K tail transactions with concurrent writes and all 4096 reciprocal addresses; exact one-clock ROM/two-clock cache latency",checked);$finish;
end
endmodule
