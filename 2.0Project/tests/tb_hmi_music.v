`timescale 1ns/1ps
module tb_hmi_music;
reg clk=0; always #5 clk=~clk;
reg rst=1,rx=1,carousel=1,busy=0,settings=0;
reg [2:0] count=0;
wire music,start,err,tx,stop;
integer pulses=0,errors=0,stops=0,n=0,checks=0;
reg [7:0] bytes[0:31],received;
saixian_hmi_uart #(.CLK_FREQ_HZ(10000),.BAUD_RATE(1000)) receiver(
 .clk(clk),.rst(rst),.uart_rx(rx),.music_next_pulse(music),.result_stop_pulse(stop),.start_pulse(start),.frame_error_pulse(err));
saixian_hmi_status_tx #(.CLK_FREQ_HZ(10000),.BAUD_RATE(1000)) transmitter(
 .clk(clk),.rst(rst),.page_id(3'd0),.refresh_request(1'b0),.image_count(3'd5),
 .audio_count(count),.initializing(1'b0),.error_code(3'd0),.uart_tx(tx));
top dut();
always @(posedge clk) begin if(music)pulses=pulses+1;if(err)errors=errors+1;if(stop)stops=stops+1;if(start)$fatal(1,"Music command started contest");end
task byte_out(input [7:0] b);
 begin @(negedge clk);rx=0;repeat(10)@(negedge clk);
 for(integer i=0;i<8;i=i+1)begin rx=b[i];repeat(10)@(negedge clk);end
 rx=1;repeat(10)@(negedge clk);end
endtask
task click(input [7:0] value);
 begin byte_out(8'h55);byte_out(8'h08);byte_out(value);byte_out(0);byte_out(255);byte_out(255);byte_out(255);repeat(6)@(negedge clk);end
endtask
initial begin
 force dut.video_clk=clk;force dut.rst_video=rst;force dut.audio_track_count_sd=count;
 force dut.hmi_music_next=music;force dut.key4_audio_long_press=1'b0;
 force dut.carousel_mode=carousel;force dut.battle_busy=busy;force dut.settings_mode=settings;
 repeat(4)@(negedge clk);rst=0;
 wait(checks==7);
 repeat(2)@(negedge clk);count=5;repeat(5)@(negedge clk);
 for(integer i=1;i<=5;i=i+1)begin click(0);if(dut.audio_track_index!=(i%5))$fatal(1,"Track cycle index %0d actual=%0d pulse=%0d count=%0d",i,dut.audio_track_index,pulses,dut.audio_track_count_sync1);end
 busy=1;click(0);if(dut.audio_track_index!=0)$fatal(1,"Result busy switched track");busy=0;
 carousel=0;click(0);if(dut.audio_track_index!=0)$fatal(1,"Contest switched track");carousel=1;
 settings=1;click(0);if(dut.audio_track_index!=0)$fatal(1,"Settings switched track");settings=0;
 count=1;repeat(5)@(negedge clk);click(0);if(dut.audio_track_index!=0)$fatal(1,"Single track switched");
 count=0;repeat(5)@(negedge clk);click(0);if(dut.audio_track_index!=0)$fatal(1,"No music switched");
 click(1);if(pulses!=10 || errors!=1)$fatal(1,"Music command validation");
 byte_out(8'h55);byte_out(8'h23);byte_out(0);byte_out(0);byte_out(255);byte_out(255);byte_out(255);repeat(6)@(negedge clk);
 if(stops!=1)$fatal(1,"Stop UART command missing");
 byte_out(8'h55);byte_out(8'h23);byte_out(1);byte_out(0);byte_out(255);byte_out(255);byte_out(255);repeat(6)@(negedge clk);
 if(stops!=1 || errors!=2)$fatal(1,"Invalid stop value accepted");
 $display("PASS music counts 0..5 and cleared count, real UART next-track command, wraparound and state guards");$finish;
end
initial begin
 wait(!rst);
 forever begin
 @(negedge tx);repeat(15)@(posedge clk);#1;
 for(integer b=0;b<8;b=b+1)begin received[b]=tx;if(b<7)begin repeat(10)@(posedge clk);#1;end end
 repeat(10)@(posedge clk);#1;if(tx!==1)$fatal(1,"Stop bit");bytes[n]=received;n=n+1;
 if(n>=3 && bytes[n-1]==255 && bytes[n-2]==255 && bytes[n-3]==255)begin
 if(bytes[7]==8'h6d && checks<7)begin
 if(n!=19 || bytes[14]!=(8'h30+(checks==6?0:checks)))$fatal(1,"Music count %0d was %h",checks,bytes[14]);
 checks=checks+1;@(negedge clk);if(checks<6)count=checks;else count=0;
 end
 n=0;
 end
 end
end
initial begin #2000000;$fatal(1,"Music test timeout");end
endmodule
