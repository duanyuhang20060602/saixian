`timescale 1ns/1ps
// Replay representative packets captured from the user's TJC8048T070.
// UART and gesture timer share the same clock, as on board A.
module tb_touch_experiment;
reg clk=0; always #5 clk=~clk;
reg rst=1,rx=1,enable=0;
wire valid,down,mode_valid,mode_value,click,contact;
wire [9:0] x; wire [8:0] y;
wire [10:0] cx; wire [9:0] cy;
integer samples=0,clicks=0,errors=0;
wire bad;
saixian_hmi_uart #(.CLK_FREQ_HZ(1152000)) uart(
 .clk(clk),.rst(rst),.uart_rx(rx),.touch_valid(valid),.touch_down(down),
 .touch_x(x),.touch_y(y),.touch_mode_valid(mode_valid),
 .touch_mode_value(mode_value),.frame_error_pulse(bad));
photo_touchpad #(.CLK_HZ(1152000)) pad(
 .clk(clk),.rst(rst),.enable(enable),.frame_tick(1'b1),
 .sample_valid(valid),.sample_down(down),.sample_x(x),.sample_y(y),
 .cursor_x(cx),.cursor_y(cy),.click(click),.contact(contact));
always @(posedge clk) begin
 if(rst) enable<=0; else if(mode_valid) enable<=mode_value;
 if(valid) samples=samples+1;
 if(click) clicks=clicks+1;
 if(bad) errors=errors+1;
end
task tx; input [7:0] b; integer i;
begin
 @(negedge clk);rx=0;repeat(10)@(negedge clk);
 for(i=0;i<8;i=i+1)begin rx=b[i];repeat(10)@(negedge clk);end
 rx=1;repeat(10)@(negedge clk);
end endtask
task packet; input [79:0] data; integer i;
begin
 for(i=9;i>=0;i=i-1)tx((data>>(i*8)) & 8'hff);
 // The capture contains no timestamps: assume a 20 ms sampling interval.
 repeat(22040)@(negedge clk);
end endtask
initial begin
 repeat(5)@(negedge clk);rst=0;
 tx('h55);tx('h31);tx(1);tx(0);tx(255);tx(255);tx(255);
 repeat(30)@(negedge clk);
 if(!enable)$fatal(1,"mode entry failed");
 packet(80'hA6_D8_01_11_01_01_92_FF_FF_FF);
 packet(80'hA6_D8_01_11_01_01_92_FF_FF_FF);
 packet(80'hA6_D8_01_11_01_00_91_FF_FF_FF);
 if(clicks!=1 || contact || cx!=640 || cy!=360)$fatal(1,"captured tap");
 packet(80'hA6_D0_01_0A_01_01_83_FF_FF_FF);
 packet(80'hA6_BC_00_62_01_01_C6_FF_FF_FF);
 packet(80'hA6_B0_01_91_01_01_EA_FF_FF_FF);
 packet(80'hA6_B0_01_91_01_00_E9_FF_FF_FF);
 if(clicks!=1 || contact || cx!=576 || cy!=630)$fatal(1,"captured drag/release");
 packet(80'hA6_58_02_6F_01_01_71_FF_FF_FF);
 packet(80'hA6_58_02_6F_01_00_70_FF_FF_FF);
 if(clicks!=2 || contact || cx!=576 || cy!=630)$fatal(1,"captured reanchor/tap");
 tx('h55);tx('h31);tx(0);tx(0);tx(255);tx(255);tx(255);
 repeat(30)@(negedge clk);
 if(enable || samples!=9 || errors!=0)$fatal(1,"packet count/mode exit");
 $display("PASS captured UART -> touchpad: 9 packets, 2 taps, relative drag, reanchor, mode entry/exit (20 ms assumed)");
 $finish;
end
initial begin #10000000;$fatal(1,"timeout");end
endmodule
