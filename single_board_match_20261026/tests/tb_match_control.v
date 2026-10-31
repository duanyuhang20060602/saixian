`timescale 1ns/1ps
module tb_match_control;
reg clk=0;always #5 clk=~clk;
reg rst=1;reg [3:0] sk=0,lk=0;wire [2:0] state,ta,tb;wire [9:0] a,b;wire [8:0] sec;wire [1:0] dur,cd;wire [3:0] cue;
match_control #(.CLK_HZ(20)) d(clk,rst,sk,lk,state,ta,tb,a,b,sec,dur,cd,cue);
task step;begin @(posedge clk);#1;end endtask
task press;input [3:0] s,l;begin @(negedge clk);sk=s;lk=l;step;@(negedge clk);sk=0;lk=0;end endtask
task check;input ok;input [255:0] msg;begin if(!ok)$fatal(1,"%s state=%d sec=%d a=%d b=%d",msg,state,sec,a,b);end endtask
integer i,n;reg [26:0] frozen;reg [8:0] saved_sec;
initial begin
 repeat(3)step;rst=0;step;check(state==0 && sec==30 && ta!=tb,"reset");
 for(i=0;i<30;i=i+1)begin press(3,0);step;check(ta!=tb,"teams distinct");end
 press(4,0);step;check(sec==60 && dur==1,"duration60");
 press(4,0);press(4,0);press(4,0);step;check(sec==30 && dur==0,"duration wraps");
 press(8,0);check(state==1 && cd==3,"start countdown");
 wait(state==2);#1;check(sec==30,"countdown no time loss");
 press(3,0);check(a==1 && b==1,"simultaneous scores");
 press(0,1);press(0,1);check(a==0,"subtract saturates zero");
 // Pause partway through a second; the fraction must remain unchanged.
 repeat(3)step;press(4,0);check(state==3,"pause");frozen=d.second_count;saved_sec=sec;
 repeat(55)step;check(sec==saved_sec && d.second_count==frozen,"fraction frozen");
 press(1,0);check(a==1,"paused correction");press(4,0);check(state==2 && d.second_count==frozen,"resume fraction");
 wait(sec==10);#1;check(cue==1,"last ten alert");
 wait(state==4);#1;check(sec==0 && cue==5,"automatic finish");
 press(3,0);press(0,3);check(a==1 && b==1,"result locked tie");
 press(8,0);step;check(state==0 && a==0 && b==0,"new match clears score");
 press(8,0);press(0,8);step;check(state==0,"countdown cancel");
 press(8,0);wait(state==2);#1;press(4,0);check(state==3,"pause second match");
 for(n=0;n<1005;n=n+1)press(1,0);
 check(a==999,"score cap999");press(0,1);check(a==998,"decrease999");
 press(0,8);check(state==4 && sec>0,"manual end retains time");
 press(8,0);step;press(4,0);press(4,0);press(4,0);step;check(sec==300,"five minutes");
 $display("PASS control: selection, durations, countdown, scores, freeze, alerts, tie, lock, cap, cancel");$finish;
end
initial begin #1000000;$fatal(1,"timeout");end
endmodule
