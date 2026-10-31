`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;reg rst=1;reg[3:0] sk=0,lk=0;reg rv=0;reg[3:0] op=0;reg[9:0] value=0;
wire[2:0] state,ta,tbteam;wire[9:0] a,b;wire[8:0] sec;wire[1:0] dur,cd;wire[3:0] cue;
photo_match_control #(.CLK_HZ(10)) d(clk,rst,sk,lk,state,ta,tbteam,a,b,sec,dur,cd,cue,rv,op,value);
task reset;begin @(negedge clk);rst=1;sk=0;lk=0;rv=0;repeat(3)@(negedge clk);rst=0;end endtask
task command;input[3:0] operation;input[9:0] number;input[3:0] shorts,longs;begin @(negedge clk);rv=1;op=operation;value=number;sk=shorts;lk=longs;@(negedge clk);rv=0;sk=0;lk=0;end endtask
initial begin
 reset;command(2,2,4'b0010,0);if(ta!=2 || tbteam!=1 || ta==tbteam)$fatal(1,"home serial/away physical selection race");
 reset;command(3,2,4'b0001,0);if(ta!=0 || tbteam!=2 || ta==tbteam)$fatal(1,"away serial/home physical selection race");
 reset;command(6,3,4'b1000,0);if(state!=0 || dur!=3 || sec!=300)$fatal(1,"duration/start race");
 command(1,0,4'b1000,0);wait(state==2);
 command(4,999,4'b0011,4'b0001);if(a!=999 || b!=1)$fatal(1,"serial absolute score priority");
 command(4,0,4'b0101,0);if(a!=0 || state!=3)$fatal(1,"serial zero score/pause race");
 command(5,999,0,4'b1000);if(state!=4 || b!=999)$fatal(1,"final edge correction");
 command(5,20,0,0);if(b!=999)$fatal(1,"result not locked");
 $display("PASS simultaneous serial/physical events: distinct teams, duration/start serialization, absolute0/999 priority, pause and final-edge correction");$finish;
end
endmodule
