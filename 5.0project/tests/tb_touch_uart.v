`timescale 1ns/1ps
module tb_touch_uart;
reg clk=0;always #5 clk=~clk;
reg rst=1,rx=1;wire valid,down,mode_valid,mode_value,next,bad;
wire [9:0] x;wire [8:0] y;integer tc=0,nc=0,bc=0,mc=0;
saixian_hmi_uart #(.CLK_FREQ_HZ(1152000)) dut(.clk(clk),.rst(rst),.uart_rx(rx),
 .touch_valid(valid),.touch_down(down),.touch_x(x),.touch_y(y),
 .touch_mode_valid(mode_valid),.touch_mode_value(mode_value),.next_pulse(next),.frame_error_pulse(bad));
always @(posedge clk)begin
 if(valid)tc=tc+1;if(next)nc=nc+1;if(bad)bc=bc+1;if(mode_valid)mc=mc+1;
end
task tx;input [7:0] b;integer i;
begin @(negedge clk);rx=0;repeat(10)@(negedge clk);
 for(i=0;i<8;i=i+1)begin rx=b[i];repeat(10)@(negedge clk);end
 rx=1;repeat(10)@(negedge clk);end endtask
task cmd;input [7:0] c,v;
begin tx('h55);tx(c);tx(v);tx(0);tx(255);tx(255);tx(255);repeat(20)@(negedge clk);end endtask
task touch;input [15:0] px,py;input [7:0] state;input corrupt;
reg [7:0] sum;
begin
 sum=8'ha6+px[7:0]+px[15:8]+py[7:0]+py[15:8]+state;
 tx('ha6);tx(px[7:0]);tx(px[15:8]);tx(py[7:0]);tx(py[15:8]);tx(state);
 tx(corrupt ? sum+8'd1:sum);tx(255);tx(255);tx(255);repeat(20)@(negedge clk);
end endtask
initial begin
 repeat(5)@(negedge clk);rst=0;
 cmd('h31,1);if(mc!=1 || !mode_value)$fatal(1,"enable");
 touch(16'h55,16'ha6,1,0);if(tc!=1 || x!=85 || y!=166 || !down)$fatal(1,"payload headers");
 touch(799,479,0,0);if(tc!=2 || x!=799 || y!=479 || down)$fatal(1,"limits");
 touch(200,200,1,1);touch(800,200,1,0);touch(200,480,1,0);touch(200,200,2,0);
 touch(65535,200,1,0);touch(200,65535,1,0);
 if(tc!=2 || bc!=6 || nc!=0)$fatal(1,"invalid packets must not act");
 tx('ha6);tx('h55);repeat(600)@(negedge clk); // timeout in touch packet
 cmd(5,0);touch(0,0,1,0);cmd('h31,0);
 if(tc!=3 || nc!=1 || mc!=2 || mode_value)$fatal(1,"mixed recovery");
 $display("PASS touch UART bounds/checksum/state/embedded headers/partial timeout/legacy commands");$finish;
end
initial begin #2000000;$fatal(1,"timeout");end
endmodule
