`timescale 1ns/1ps
module tb_event_flow;
reg clk=0;always #5 clk=~clk;reg rst=1;reg [3:0] sk=0,lk=0;
wire [2:0] state,ta,tb,la,lb;wire [9:0] a,b,lsa,lsb;wire [8:0] sec;wire [1:0] dur,cd,page;
wire [3:0] cue;wire lv,summary;wire [6:0] ln,nn,an;
event_flow #(.CLK_HZ(20),.LOBBY_SECONDS(2),.AWARD_SECONDS(12)) d(clk,rst,sk,lk,state,ta,tb,a,b,sec,dur,cd,cue,page,lv,la,lb,lsa,lsb,ln,nn,an,summary);
task step;begin @(posedge clk);#1;end endtask
task press;input [3:0] s,l;begin @(negedge clk);sk=s;lk=l;step;@(negedge clk);sk=0;lk=0;end endtask
task check;input ok;input [255:0] why;begin if(!ok)$fatal(1,"%s state=%d page=%d",why,state,page);end endtask
reg [2:0] saved_a,saved_b;
initial begin
 repeat(3)step;rst=0;step;check(state==5 && !lv && page==0,"boot lobby no fake result");
 wait(page==1);#1;check(state==5,"automatic lobby page");
 press(2,0);check(page==2,"manual next");press(1,0);check(page==1,"manual previous");
 press(4,0);step;check(state==0,"prepare from lobby");
 press(1,0);press(2,0);saved_a=ta;saved_b=tb;check(ta!=tb,"select teams");
 press(0,8);step;check(state==5 && ta==saved_a && tb==saved_b,"return preserves team config");
 press(8,0);repeat(3)step;check(state==1,"direct start from lobby");
 wait(state==2);#1;check(an==1 && nn==1,"first round number");
 press(1,0);press(1,0);press(2,0);press(0,8);repeat(3)step;
 check(state==4 && lv && lsa==2 && lsb==1 && ln==1,"capture final scores once");
 check(la==saved_a && lb==saved_b && nn==2,"capture same teams, next round");
 press(3,0);check(a==2 && b==1,"result lock");
 wait(summary);#1;check(state==4,"award before summary");
 wait(state==5);#1;repeat(3)step;check(page==3 && a==0 && b==0 && lsa==2 && lsb==1,"auto return last result");
 press(4,0);step;press(1,0);check(la==saved_a && lb==saved_b && lsa==2,"new selection does not overwrite history");
 press(8,0);wait(state==2);#1;check(an==2,"second round");
 press(3,0);press(0,8);repeat(3)step;check(lsa==1 && lsb==1 && ln==2,"tie stored");
 press(8,0);repeat(3)step;check(state==5 && page==3 && ln==2,"manual return keeps tie history");
 press(4,0);step;press(8,0);repeat(3)step;check(state==1,"count start");
 press(0,8);repeat(3)step;check(state==0 && ln==2,"cancel does not create result");
 $display("PASS event flow: lobby, configuration, shared teams, live scores, original award stage, summary, saved result, next round, tie and cancel");$finish;
end
initial begin #1000000;$fatal(1,"timeout");end
endmodule
