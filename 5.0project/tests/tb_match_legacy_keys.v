`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=1,bv=0;reg[7:0] data=0;reg[3:0] keys=15;integer clocks=0;
wire active;reg frame=0;wire[3:0] photo_press;wire photo_short,photo_long;
integer p0=0,p1=0,p2=0,p3=0,shorts=0,longs=0;
always @(posedge clk)begin clocks<=clocks+1;frame<=clocks%100==0;end
always @(negedge clk)begin
 if(photo_press[0])p0=p0+1;if(photo_press[1])p1=p1+1;if(photo_press[2])p2=p2+1;if(photo_press[3])p3=p3+1;
 if(photo_short)shorts=shorts+1;if(photo_long)longs=longs+1;
 if(active && (photo_press || photo_short || photo_long))$fatal(1,"scoreboard gesture leaked to photo mode");
end
photo_match_manager #(.HZ(1000000),.DB_CYCLES(3000),.HOLD_CYCLES(10000)) d(
 .clk(clk),.rst(rst),.frame_tick(frame),.entry_allowed(1'b1),.key_n(keys),.byte_valid(bv),.byte_data(data),.serial_idle(1'b1),.text_active(1'b0),
 .active(active),.photo_press(photo_press),.photo_short(photo_short),.photo_long(photo_long));
task cycles;input integer n;begin repeat(n)@(negedge clk);end endtask
task byte_send;input[7:0] value;begin @(negedge clk);bv=1;data=value;@(negedge clk);bv=0;end endtask
task mode;input value;begin byte_send("!");byte_send("M");byte_send(":");byte_send("0"+value);byte_send(13);byte_send(10);cycles(200);end endtask
integer i;
initial begin
 cycles(3);rst=0;cycles(5000);
 for(i=0;i<4;i=i+1)begin keys[i]=0;cycles(6000);keys[i]=1;cycles(6000);end
 if(p0!=1 || p1!=1 || p2!=1 || p3!=1 || shorts!=1 || longs!=0)$fatal(1,"legacy short/press semantics");
 keys[3]=0;cycles(30000);keys[3]=1;cycles(6000);
 if(p3!=2 || shorts!=1 || longs!=1)$fatal(1,"legacy long/release semantics");
 mode(1);if(!active)$fatal(1,"entry");
 keys[2]=0;cycles(6000);mode(0);if(active)$fatal(1,"exit");cycles(15000);
 if(p2!=1 || p3!=2 || shorts!=1 || longs!=1)$fatal(1,"held exit gesture leaked");
 keys[2]=1;cycles(6000);keys[2]=0;cycles(6000);keys[2]=1;cycles(6000);
 if(p2!=2)$fatal(1,"legacy keys failed to rearm");
 $display("PASS shared legacy keys: four press-on-down events, K4 release/one-shot-long, mode isolation and held exit rearm with divided clock");$finish;
end
endmodule
