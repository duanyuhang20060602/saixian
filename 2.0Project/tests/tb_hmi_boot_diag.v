`timescale 1ns/1ps
module tb_hmi_boot_diag;
reg clk=0;always #5 clk=~clk;
reg rst=1;
reg diag_ready=0;
wire uart_tx,command_sent_pulse;
wire [39:0] boot_diag={3'd2,4'd1,8'h16,8'h05,3'd2,6'd8,8'hff};
saixian_hmi_status_tx #(.CLK_FREQ_HZ(2000),.BAUD_RATE(200)) dut(
 .clk(clk),.rst(rst),.image_count(3'd5),.audio_found(1'b1),.error_code(3'd0),
 .boot_diag(boot_diag),.diag_ready(diag_ready),.uart_tx(uart_tx),.command_sent_pulse(command_sent_pulse));
reg [7:0] bytes[0:31],received;
integer n=0,pages=0;
reg [39:0] expected;
initial begin repeat(4) @(negedge clk);rst=0;end
initial begin
 wait(!rst);repeat(3500) @(negedge clk);
 if(dut.next_field!=2 || dut.tx_state!=dut.TX_IDLE || uart_tx!==1 || dut.diag_capture_pulse!==0)
  $fatal(1,"Formatter consumed diagnostic bus before synchronized ready");
 diag_ready=1;
end
initial begin
 wait(!rst);
 forever begin
  @(negedge uart_tx);
  repeat(15) @(posedge clk);#1;
  for(integer b=0;b<8;b=b+1) begin
   received[b]=uart_tx;
   if(b<7) begin repeat(10) @(posedge clk);#1;end
  end
  repeat(10) @(posedge clk);#1;
  if(uart_tx!==1) $fatal(1,"UART stop bit");
  bytes[n]=received;n=n+1;
  if(n>=3 && bytes[n-1]==255 && bytes[n-2]==255 && bytes[n-3]==255) begin
   if(bytes[2]==8'h31) begin
    case(pages)
     0:expected="E02  ";1:expected="I2R1 ";2:expected="C08  ";
     3:expected="AFF  ";4:expected="T16  ";5:expected="S05  ";
    endcase
    if(n!=20 || {bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]}!==expected || bytes[16]!=8'h22)
     $fatal(1,"HMI diagnostic text/length mismatch page %0d",pages);
    pages=pages+1;
    if(pages==6) begin
     $display("PASS decoded UART: error history, stage/retry, command, response, elapsed and scan pages");$finish;
    end
   end else if(n!=15 || bytes[10]!=(bytes[2]==8'h37 ? 8'h35 : 8'h31) || bytes[11]!=8'h22) begin
    $fatal(1,"Original picture/music status changed");
   end
   n=0;
  end
 end
end
initial begin #1500000;$fatal(1,"UART diagnostic timeout");end
endmodule
