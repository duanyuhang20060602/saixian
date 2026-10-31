`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,rx=1;always #5 clk=~clk;
wire capture,bv,valid,error;wire[7:0] bd;wire[255:0] line;
wire setting,touch,next;wire[7:0] value;wire[9:0] x;wire[8:0] y;
photo_text_input_a #(.HZ(921600)) text_input(clk,rst,bv,bd,1'b0,capture,valid,line,error);
saixian_hmi_uart #(.CLK_FREQ_HZ(921600),.TEXT_INPUT(1)) receiver(.clk(clk),.rst(rst),.uart_rx(rx),.text_capture(capture),.raw_byte_valid(bv),.raw_byte_data(bd),.setting_valid(setting),.setting_value(value),.touch_valid(touch),.touch_x(x),.touch_y(y),.next_pulse(next));
integer settings=0,touches=0,nexts=0,errors=0;
always @(posedge clk)begin
 if(setting)begin settings=settings+1;if(value!=64)$fatal(1,"legacy @ value lost");end
 if(touch)begin touches=touches+1;if(x!=64 || y!=10)$fatal(1,"legacy @ coordinate lost");end
 if(next)nexts=nexts+1;if(error)errors=errors+1;
end
task send;input[7:0] b;integer i;begin
 rx=0;repeat(8)@(negedge clk);for(i=0;i<8;i=i+1)begin rx=b[i];repeat(8)@(negedge clk);end
 rx=1;repeat(8)@(negedge clk);
end endtask
task trailer;begin send(255);send(255);send(255);repeat(8)@(negedge clk);end endtask
initial begin
 repeat(5)@(negedge clk);rst=0;
 send(8'h55);send(8'h10);send(64);send(0);trailer;
 send(8'ha6);send(64);send(0);send(10);send(0);send(1);send(0);trailer;
 send("@");send("2");send(":");send("U");send(8'ha6);send(8'ha1);send(8'hfe);send(8'hfe);send(13);send(10);repeat(8)@(negedge clk);
 if(!valid || line[255:254]!=2 || line[253:249]!=3 || line[13:0]!=85 || line[27:14]!=(128+5*94) || line[41:28]!=8963)$fatal(1,"typed GB2312 boundary/legacy demultiplex failure");
 // While a previous line is queued, a new line must not overwrite it.
 send("@");send("3");send(":");send("X");send(13);send(10);
 if(!valid || line[255:254]!=2 || line[13:0]!=85)$fatal(1,"queued line overwritten");
 send(8'h55);send(5);send(0);send(0);trailer;
 if(settings!=1 || touches!=1 || nexts!=1 || errors!=1)$fatal(1,"legacy control or busy-line isolation mismatch %d %d %d %d",settings,touches,nexts,errors);
 $display("PASS real J1 UART: legacy setting/coordinate byte 40, text byte 55/A6, GB2312, pending-line isolation and normal next command");$finish;
end
initial begin #10000000;$fatal(1,"HMI timeout");end
endmodule
