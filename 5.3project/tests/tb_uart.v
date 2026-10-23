`timescale 1ns/1ps
module tb_uart;
reg clk=0;always #5 clk=~clk;
reg rst=1,send=0;reg [159:0] message=160'h0102030405060708090a0b0c0d0e0f1020304050;
wire tx,busy,received,bad;wire [159:0] result;
reg inject=0,rx=1;integer count=0;
photo_uart #(.CLK_HZ(1152000)) port(.clk(clk),.rst(rst),.rx(inject ? rx:tx),.tx(tx),.send(send),.message(message),
 .busy(busy),.received(received),.received_message(result),.bad_packet(bad));
always @(posedge clk)if(received)begin count=count+1;if(result!=message)$fatal(1,"payload corrupted");end
task send_byte;
 input [7:0] value;integer i;
 begin rx=0;repeat(10)@(negedge clk);for(i=0;i<8;i=i+1)begin rx=value[i];repeat(10)@(negedge clk);end rx=1;repeat(10)@(negedge clk);end
endtask
integer i;
initial begin
 repeat(5)@(posedge clk);rst=0;@(negedge clk);send=1;@(negedge clk);send=0;
 wait(!busy);repeat(20)@(posedge clk);if(count!=1)$fatal(1,"UART loopback");
 inject=1;send_byte(8'ha5);send_byte(8'h5a);for(i=0;i<20;i=i+1)send_byte(i);send_byte(0);send_byte(0);
 repeat(20)@(posedge clk);if(count!=1)$fatal(1,"bad CRC accepted");
 send_byte(8'ha5);send_byte(8'h5a);send_byte(8'h01);repeat(500)@(posedge clk);
 if(port.rx_pos!=0)$fatal(1,"partial packet not timed out");
 inject=0;@(negedge clk);send=1;@(negedge clk);send=0;wait(!busy);repeat(20)@(posedge clk);
 if(count!=2)$fatal(1,"parser did not recover");
 $display("PASS UART loopback, CRC16 rejection, partial packet timeout and recovery");$finish;
end
initial begin #2000000;$fatal(1,"UART timeout");end
endmodule
