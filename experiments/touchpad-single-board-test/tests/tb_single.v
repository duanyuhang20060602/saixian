`timescale 1ns/1ps
module tb_single;
reg clk=0;always #5 clk=~clk;
reg rst=1,rx=1;
wire [10:0] cx;wire [9:0] cy,raw_x;wire [8:0] raw_y;
wire mode_enabled,contact,click;wire [15:0] packets,errors,taps;wire [1:0] selected;
touch_test_core #(.CLK_HZ(1152000)) dut(.clk(clk),.rst(rst),.uart_rx(rx),.frame_tick(1'b1),
 .cursor_x(cx),.cursor_y(cy),.raw_x(raw_x),.raw_y(raw_y),.mode_enabled(mode_enabled),.contact(contact),
 .click(click),.rx_count(packets),.error_count(errors),.tap_count(taps),.selection(selected));
task tx;input [7:0] b;integer i;
begin @(negedge clk);rx=0;repeat(10)@(negedge clk);
 for(i=0;i<8;i=i+1)begin rx=b[i];repeat(10)@(negedge clk);end
 rx=1;repeat(10)@(negedge clk);end endtask
task touch;input [15:0] px,py;input pd,corrupt;reg [7:0] sum;
begin
 sum=8'ha6+px[7:0]+px[15:8]+py[7:0]+py[15:8]+pd+corrupt;
 tx('ha6);tx(px[7:0]);tx(px[15:8]);tx(py[7:0]);tx(py[15:8]);tx(pd);tx(sum);tx(255);tx(255);tx(255);
 repeat(24000)@(negedge clk);
end endtask
task mode;input state;
begin tx('h55);tx('h31);tx(state);tx(0);tx(255);tx(255);tx(255);repeat(30)@(negedge clk);end endtask
initial begin
 repeat(5)@(negedge clk);rst=0;
 if(!mode_enabled)$fatal(1,"must work without enable command");
 touch(100,100,1,0);touch(100,152,1,0);touch(100,152,0,0);
 if(cx!=640 || cy!=464 || taps!=0 || selected!=0)$fatal(1,"drag to green");
 touch(300,300,1,0);touch(300,300,0,0);
 if(taps!=1 || selected!=2 || packets!=5)$fatal(1,"green tap");
 touch(100,100,1,1);if(errors!=1 || packets!=5)$fatal(1,"bad checksum counter");
 mode(0);touch(100,100,1,0);touch(200,200,1,0);touch(200,200,0,0);
 if(cx!=640 || cy!=464 || taps!=1 || mode_enabled)$fatal(1,"disabled must not move");
 mode(1);touch(100,100,1,0);touch(100,180,1,0);touch(100,180,0,0);
 if(cx!=640 || cy!=624 || taps!=1)$fatal(1,"clear button drag");
 touch(300,300,1,0);touch(300,300,0,0);
 if(packets!=0 || taps!=0 || errors!=0 || selected!=0)$fatal(1,"clear button");
 $display("PASS single-board UART -> relative pointer -> green select -> disable -> clear");$finish;
end
initial begin #10000000;$fatal(1,"timeout");end
endmodule
