`timescale 1ns/1ps
module tb_hmi_byte_stream;
reg clk=0;always #5 clk=~clk;
reg rst=1;reg [2:0] page=0;reg [1:0] sharp=1,enhancement=2;
reg [3:0] brightness=4,contrast=5,saturation=6,volume=7,event_state=6;
reg invert=0,vintage=1,refresh=0;reg [6:0] minutes=59;reg [5:0] seconds=58;
wire uart,valid;wire [7:0] data;reg ready=0;reg [15:0] random=16'habc1;
always @(posedge clk)begin random<={random[14:0],random[15]^random[13]^random[12]^random[10]};ready<=random[0] && random[3];end
saixian_hmi_status_tx_before #(.CLK_FREQ_HZ(1152000),.ENHANCEMENT_FEEDBACK(1)) ref_uart(
 .clk(clk),.rst(rst),.image_count(3'd6),.audio_count(3'd5),.error_code(3'd7),.initializing(1'b0),.page_id(page),.refresh_request(refresh),
 .sharpness(sharp),.brightness(brightness),.contrast(contrast),.saturation(saturation),.volume(volume),.invert(invert),.vintage(vintage),
 .enhancement(enhancement),.event_state(event_state),.minutes(minutes),.seconds(seconds),.uart_tx(uart),.command_sent_pulse());
saixian_hmi_status_tx #(.CLK_FREQ_HZ(1152000),.ENHANCEMENT_FEEDBACK(1),.BYTE_STREAM(1)) dut(
 .clk(clk),.rst(rst),.image_count(3'd6),.audio_count(3'd5),.error_code(3'd7),.initializing(1'b0),.page_id(page),.refresh_request(refresh),
 .sharpness(sharp),.brightness(brightness),.contrast(contrast),.saturation(saturation),.volume(volume),.invert(invert),.vintage(vintage),
 .enhancement(enhancement),.event_state(event_state),.minutes(minutes),.seconds(seconds),.uart_tx(),.command_sent_pulse(),
 .byte_valid(valid),.byte_data(data),.byte_ready(ready));
reg [7:0] expected[0:2047],actual[0:2047];integer ne=0,na=0,k,p,n;reg [7:0] decoded;
always @(posedge clk)if(!rst && valid && ready)begin actual[na]=data;na=na+1;end
always begin
 @(negedge uart);if(!rst)begin
  repeat(15)@(negedge clk);
  for(k=0;k<8;k=k+1)begin decoded[k]=uart;repeat(10)@(negedge clk);end
  if(!rst)begin if(!uart)$fatal(1,"UART stop bit");expected[ne]=decoded;ne=ne+1;end
 end
end
initial begin
 for(p=0;p<5;p=p+1)begin
  rst=1;ne=0;na=0;page=p;repeat(200)@(negedge clk);rst=0;
  // Wait for all initial fields. Do not compare repeated refresh snapshots.
  wait(ref_uart.next_field==ref_uart.field_count && ref_uart.tx_state==0);
  repeat(20)@(negedge clk);
  if(na<ne || ne==0 && p<3)$fatal(1,"count mismatch page %0d expected %0d actual %0d",p,ne,na);
  for(n=0;n<ne;n=n+1)if(actual[n]!==expected[n])$fatal(1,"page %0d byte %0d expected %h actual %h",p,n,expected[n],actual[n]);
  $display("page %0d matched %0d bytes",p,ne);
 end
 $display("PASS byte stream equals original UART, pages 0..4, random backpressure");$finish;
end
initial begin #100000000;$fatal(1,"timeout");end
endmodule
