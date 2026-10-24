`timescale 1ns/1ps
// Differential regression against the untouched cooperate UART. Exercise both
// production clocks as well as a small divisor, including changing TX input.
module v4_uart_case #(parameter HZ=75000000)(input clk,output reg done=0);
localparam DIV=(HZ+115200/2)/115200;
reg rst=1,send=0,inject=0,rx=1;
reg [159:0] message=160'h0102030405060708090a0b0c0d0e0f1020304050;
reg [159:0] expected;
wire tx,reference_tx,busy,reference_busy,received,reference_received,bad,reference_bad;
wire [159:0] result,reference_result;
wire pulse_tx,pulse_busy,pulse_received,pulse_bad;wire [159:0] pulse_result;
photo_uart #(.CLK_HZ(HZ),.PULSE_PAYLOAD(1)) compact(.clk(clk),.rst(rst),.rx(inject ? rx:tx),.tx(pulse_tx),
 .send(send),.message(message),.busy(pulse_busy),.received(pulse_received),.received_message(pulse_result),.bad_packet(pulse_bad));
integer count=0,errors=0,i,j;reg [31:0] noise=32'h91a37bc2;
photo_uart #(.CLK_HZ(HZ)) dut(.clk(clk),.rst(rst),.rx(inject ? rx:tx),.tx(tx),
 .send(send),.message(message),.busy(busy),.received(received),.received_message(result),.bad_packet(bad));
v4_port_ref_photo_uart #(.CLK_HZ(HZ)) golden(.clk(clk),.rst(rst),.rx(inject ? rx:tx),.tx(reference_tx),
 .send(send),.message(message),.busy(reference_busy),.received(reference_received),
 .received_message(reference_result),.bad_packet(reference_bad));
always @(posedge clk)begin
 #1;
 if(!rst)begin
  if({tx,busy,received,bad,result}!=={reference_tx,reference_busy,reference_received,reference_bad,reference_result})
   $fatal(1,"UART contract changed HZ=%0d",HZ);
  if({pulse_tx,pulse_busy,pulse_received,pulse_bad}!=={tx,busy,received,bad} || (received && pulse_result!==result))
   $fatal(1,"CRC-gated compact UART contract changed HZ=%0d",HZ);
  if(received)begin count=count+1;if(result!==expected)$fatal(1,"TX snapshot changed HZ=%0d",HZ);end
  if(bad)errors=errors+1;
 end
end
task send_byte;
 input [7:0] value;integer bit_index;
 begin
  rx=0;repeat(DIV)@(negedge clk);
  for(bit_index=0;bit_index<8;bit_index=bit_index+1)begin
   rx=value[bit_index];repeat(DIV)@(negedge clk);
  end
  rx=1;repeat(DIV)@(negedge clk);
 end
endtask
task loopback;
 begin
  expected=message;send=1;@(negedge clk);send=0;
  repeat(DIV*12)@(negedge clk);message=~message;
  wait(!busy);repeat(DIV*2)@(negedge clk);
 end
endtask
initial begin
 repeat(5)@(negedge clk);rst=0;loopback();
 if(count!=1)$fatal(1,"loopback failed");
 inject=1;send_byte(8'ha5);send_byte(8'h5a);
 for(i=0;i<20;i=i+1)send_byte(i);
 send_byte(0);send_byte(0);repeat(DIV*2)@(negedge clk);
 if(count!=1 || errors==0)$fatal(1,"bad CRC accepted");
 send_byte(8'ha5);send_byte(8'h5a);send_byte(8'h01);
 repeat(DIV*42)@(negedge clk);
 if(dut.rx_pos!=0)$fatal(1,"partial packet timeout failed");
 inject=0;loopback();if(count!=2)$fatal(1,"recovery failed");
 for(j=0;j<8;j=j+1)begin
  for(i=0;i<20;i=i+1)begin
   noise={noise[30:0],noise[31]^noise[21]^noise[1]^noise[0]};
   message[i*8 +: 8]=noise[7:0];
  end
  loopback();if(count!=j+3)$fatal(1,"random packet CRC/publication failed");
 end
 done=1;
end
endmodule
module tb_v4_uart_equivalence;
reg clk=0;always #5 clk=~clk;
wire a,b,c;
v4_uart_case #(.HZ(75000000)) ca(clk,a);
v4_uart_case #(.HZ(50000000)) cb(clk,b);
v4_uart_case #(.HZ(1152000)) cc(clk,c);
initial begin wait(a&&b&&c);$display("PASS UART exact TX/RX/CRC/timeout/snapshot at 75MHz, 50MHz and DIV10");$finish;end
initial begin #40000000;$fatal(1,"UART regression timeout");end
endmodule
