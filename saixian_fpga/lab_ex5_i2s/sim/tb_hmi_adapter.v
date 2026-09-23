`timescale 1ns/1ps
module tb_hmi_adapter;
reg clk=0; always #5 clk=~clk;
reg rst=1,rx=1;
wire start,pause,finish,prev,next,valid,reset,error;
wire [2:0] id; wire [7:0] value;
integer counts[0:7]; integer errs=0,i,before_count;
reg [23:0] pixel; reg inv=0,old=0; wire [23:0] styled;
saixian_hmi_color_style style(pixel,inv,old,styled);
saixian_hmi_uart #(.CLK_FREQ_HZ(800),.BAUD_RATE(100)) dut(
.clk(clk),.rst(rst),.uart_rx(rx),.start_pulse(start),.pause_pulse(pause),
.finish_pulse(finish),.prev_pulse(prev),.next_pulse(next),
.setting_valid(valid),.setting_id(id),.setting_value(value),
.reset_defaults_pulse(reset),.frame_error_pulse(error));
always @(posedge clk) begin
 if(start) counts[0]=counts[0]+1;
 if(pause) counts[1]=counts[1]+1;
 if(finish) counts[2]=counts[2]+1;
 if(prev) counts[3]=counts[3]+1;
 if(next) counts[4]=counts[4]+1;
 if(valid) counts[5]=counts[5]+1;
 if(reset) counts[6]=counts[6]+1;
 if(error) errs=errs+1;
end
task byte_send; input [7:0] v; integer j;
begin
 @(negedge clk);rx=0;repeat(8) @(negedge clk);
 for(j=0;j<8;j=j+1) begin rx=v[j];repeat(8) @(negedge clk);end
 rx=1;repeat(8) @(negedge clk);
end endtask
task frame; input [7:0] cmd,v;
begin byte_send(8'h55);byte_send(cmd);byte_send(v);byte_send(0);
repeat(3) byte_send(8'hff);repeat(5) @(negedge clk);end endtask
task check; input ok;input [511:0] msg;
begin if(!ok) begin $display("FAIL %s",msg);$fatal(1);end end endtask
initial begin
for(i=0;i<8;i=i+1)counts[i]=0;
repeat(4) @(negedge clk);rst=0;
byte_send(0);repeat(3) byte_send(255);byte_send(8'h88);repeat(3) byte_send(255);
for(i=1;i<=5;i=i+1) frame(i,0);
for(i=0;i<5;i=i+1)check(counts[i]==1,"action map 01..05");
for(i=0;i<7;i=i+1)begin
 frame(8'h10+i,i>=5?1:3);
 check(id==i && value==(i>=5?1:3),"setting map 10..16");
end
frame(8'h15,0);check(id==5 && value==0,"invert off");
frame(8'h16,0);check(id==6 && value==0,"vintage off");
check(counts[5]==9,"setting pulse count");
frame(8'h15,2);check(counts[5]==9 && errs==1,"invalid toggle rejected");
frame(8'h1f,0);check(counts[6]==1,"restore defaults");
frame(8'h70,0);check(errs==2,"unknown command");
byte_send(8'h55);byte_send(8'h10);repeat(400) @(negedge clk);
check(dut.frame_index==0 && errs==3,"truncated frame timeout");
frame(1,0);check(counts[0]==2,"recovery after timeout");
byte_send(8'h55);byte_send(1);byte_send(0);byte_send(1);
repeat(3) byte_send(255);
frame(5,0);check(counts[0]==2 && counts[4]==2,"corrupt frame recovery");
pixel=24'h204080;#1;check(styled==pixel,"filter bypass");
inv=1;#1;check(styled==24'hdfbf7f,"invert");
inv=0;old=1;#1;check(styled==24'h684836,"warm mono");
inv=1;#1;check(styled==24'h97b7c9,"vintage then invert");
$display("PASS HMI: all 13 command IDs, boot noise, invalid toggles, timeout, recovery, color filters");
$finish;
end
initial begin #10000000;$fatal(1,"timeout");end
endmodule

