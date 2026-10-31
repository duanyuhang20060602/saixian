`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=1,rx=1,allowed=0,old_text=0;reg[3:0] keys=15;
wire bv,idle,busy,active;wire[7:0] data;wire[3:0] routed,cue;
wire[2:0] state,ta,tbteam;wire[9:0] a,b;wire[8:0] remaining;wire[1:0] duration,cd;
wire bad,legacy_start;
integer cycles=0,errors=0,legacy=0;
reg frame=0;
always @(posedge clk)begin cycles<=cycles+1;frame<=cycles%200==0;if(bad)errors<=errors+1;if(legacy_start && !active)legacy<=legacy+1;end
saixian_hmi_uart #(.CLK_FREQ_HZ(921600),.TEXT_INPUT(1)) uart(
 .clk(clk),.rst(rst),.uart_rx(rx),.text_active(old_text),.text_can_start(idle),.text_byte_valid(bv),.text_byte(data),.start_pulse(legacy_start));
photo_match_manager #(.HZ(2000),.DB_CYCLES(3),.HOLD_CYCLES(100)) d(
 .clk(clk),.rst(rst),.frame_tick(frame),.entry_allowed(allowed),.key_n(keys),
 .byte_valid(bv),.byte_data(data),.serial_idle(idle),.text_active(old_text),
 .active(active),.serial_busy(busy),.photo_key_n(routed),.state(state),.team_a(ta),.team_b(tbteam),
 .score_a(a),.score_b(b),.remaining(remaining),.duration_index(duration),.countdown(cd),.cue_event(cue),.serial_error(bad));
task byte_send;input[7:0] c;integer n;begin
 @(negedge clk);rx=0;repeat(8)@(negedge clk);
 for(n=0;n<8;n=n+1)begin rx=c[n];repeat(8)@(negedge clk);end
 rx=1;repeat(10)@(negedge clk);
end endtask
task text;input[319:0] s;integer n;begin for(n=39;n>=0;n=n-1)if(s[n*8+:8]!=0)byte_send(s[n*8+:8]);end endtask
task send;input[319:0] s;begin text(s);byte_send(13);byte_send(10);repeat(12)@(negedge clk);end endtask
task check;input condition;input[511:0] label;begin if(!condition)$fatal(1,"%s active=%b state=%d a=%d b=%d rem=%d",label,active,state,a,b,remaining);end endtask
reg[26:0] frozen;reg[8:0] old_remaining;
initial begin
 repeat(5)@(negedge clk);rst=0;
 send("!M:1");check(!active,"entry waits for boot-ready carousel");allowed=1;wait(active);repeat(8)@(negedge clk);
 send("!H:2");send("!V:4");send("!T:2");check(ta==2 && tbteam==4 && duration==2 && remaining==180,"screen team and duration");
 send("!H:4");check(ta==2 && tbteam==4,"same-team selection rejected");
 send("!K:0");check(state==1,"screen start");wait(state==2);send("!K:1");check(state==3,"screen pause");
 frozen=d.control.second_count;old_remaining=remaining;repeat(500)@(negedge clk);
 check(d.control.second_count==frozen && remaining==old_remaining,"pause fractional clock");
 send("!A:123");send("!B:45");check(a==123 && b==45,"screen absolute scores");
 send("!K:4");send("!K:6");check(a==124 && b==46,"screen plus");
 send("!K:5");send("!K:7");check(a==123 && b==45,"screen minus");
 keys[0]=0;repeat(20)@(negedge clk);keys[0]=1;repeat(20)@(negedge clk);check(a==124,"physical short plus");
 keys[0]=0;repeat(140)@(negedge clk);keys[0]=1;repeat(20)@(negedge clk);check(a==123,"physical long minus without release plus");
 send("!A:999");send("!K:4");check(a==999,"999 saturation");
 send("!A:0");send("!K:5");check(a==0,"zero saturation");
 send("!B:1000");send("!M:2");send("!K:8");send("!B:-1");check(b==45 && active,"invalid values do not change scores or mode");
 text("!B:12");repeat(400)@(negedge clk);check(!busy && b==45,"incomplete line timeout");
 old_text=1;send("!B:777");old_text=0;check(b==45,"caption content does not become score command");
 byte_send(8'h55);byte_send(8'h14);byte_send(8'h21);byte_send(0);byte_send(255);byte_send(255);byte_send(255);
 check(a==0 && b==45,"binary HMI payload does not enter score parser");
 check(d.control.second_count==frozen && remaining==old_remaining,"corrections preserve fractional clock");
 send("!K:1");check(state==2,"screen resume");send("!K:2");check(state==4,"screen finish");
 send("!A:88");send("!K:4");check(a==0,"result locked");
 keys[3]=0;repeat(140)@(negedge clk);send("!M:0");wait(!active);repeat(100)@(negedge clk);
 check(routed[3] && keys[3]==0,"held exit key cannot leak to old photo controls");
 keys[3]=1;repeat(20)@(negedge clk);check(routed==15,"old controls rearm");
 byte_send(8'h55);byte_send(1);byte_send(0);byte_send(0);byte_send(255);byte_send(255);byte_send(255);repeat(20)@(negedge clk);
 check(legacy==1,"legacy binary start preserved after exit");
 send("!M:1");wait(active);check(state==0 && a==0 && b==0,"fresh match entry");
 check(errors>=5,"malformed and overflow coverage");
 $display("PASS actual HMI UART: mode, teams, durations, direct0..999, +/- keys/buttons, pause, result lock, caption/binary coexistence, timeout and exit-key isolation");$finish;
end
initial begin #10000000;$fatal(1,"serial match timeout");end
endmodule
