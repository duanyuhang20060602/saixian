`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=1,start=0;reg[9:0] a=0,b=0;reg[8:0] sec=30;reg[1:0] dur=0;
wire[3:0] a0,a1,a2,b0,b1,b2,m0,m1,s0,s1;wire[9:0] progress;
photo_match_numbers d(clk,rst,start,a,b,sec,dur,a0,a1,a2,b0,b1,b2,m0,m1,s0,s1,progress);
integer i,j,latency,max_latency=0,cases=0,want;
task check;begin
 @(negedge clk);start=1;@(negedge clk);start=0;latency=0;
 while(d.phase!=0)begin @(negedge clk);latency=latency+1;if(latency>600)$fatal(1,"blank-time arithmetic deadline");end
 if(latency>max_latency)max_latency=latency;
 if(a0!==a/100 || a1!==(a/10)%10 || a2!==a%10 || b0!==b/100 || b1!==(b/10)%10 || b2!==b%10)
  $fatal(1,"score decimal mismatch a=%d b=%d",a,b);
 if(m0!==(sec/60)/10 || m1!==(sec/60)%10 || s0!==(sec%60)/10 || s1!==sec%10)$fatal(1,"time decimal mismatch");
 case(dur)0:want=sec*17;1:want=(sec*17)>>1;2:want=(sec*91)>>5;3:want=(sec*109)>>6;endcase
 if(progress!==(want&1023))$fatal(1,"progress mismatch sec=%d dur=%d got=%d expected=%d",sec,dur,progress,want&1023);
 cases=cases+1;
end endtask
initial begin
 repeat(4)@(negedge clk);rst=0;
 for(i=0;i<1024;i=i+1)begin a=i;b=(i*37)%1024;sec=(i*13)%512;dur=i%4;check;end
 for(i=0;i<512;i=i+1)for(j=0;j<4;j=j+1)begin a=999;b=0;sec=i;dur=j;check;end
 $display("PASS match arithmetic: %0d exhaustive/boundary cases; max %0d clocks in blanking",cases,max_latency);$finish;
end
endmodule
