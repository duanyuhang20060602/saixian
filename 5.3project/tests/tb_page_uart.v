`timescale 1ns/1ps
module tb_page_uart;
reg clk=0;always #5 clk=~clk;
reg rst=1,send=0;reg [159:0] message=0;
wire tx,ref_tx,busy,ref_busy,got,ref_got,bad,ref_bad;
wire [159:0] incoming,ref_incoming;
integer packets=0,i;
photo_uart #(.CLK_HZ(1152000)) dut(.clk(clk),.rst(rst),.rx(tx),.tx(tx),.send(send),.message(message),.busy(busy),.received(got),.received_message(incoming),.bad_packet(bad));
page_uart_reference #(.CLK_HZ(1152000)) reference(.clk(clk),.rst(rst),.rx(tx),.tx(ref_tx),.send(send),.message(message),.busy(ref_busy),.received(ref_got),.received_message(ref_incoming),.bad_packet(ref_bad));
always @(negedge clk)if(!rst)begin
 if({tx,busy,got,bad,incoming}!=={ref_tx,ref_busy,ref_got,ref_bad,ref_incoming})$fatal(1,"UART cycle mismatch");
 if(got)begin if(incoming!==message)$fatal(1,"CRC roundtrip mismatch");packets=packets+1;end
end
initial begin
 repeat(3)@(negedge clk);rst=0;
 for(i=0;i<32;i=i+1)begin
  @(negedge clk);message={$random,$random,$random,$random,$random};send=1;
  @(negedge clk);send=0;wait(!busy);repeat(30)@(negedge clk);
 end
 if(packets!=32)$fatal(1,"missing packets %0d",packets);
 $display("PASS UART serializer: 32 random 24-byte packets, every TX/RX/CRC/busy cycle equals frozen implementation");$finish;
end
initial begin #2000000;$fatal(1,"UART timeout");end
endmodule
