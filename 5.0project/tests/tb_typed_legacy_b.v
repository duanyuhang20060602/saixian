`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,send=0,media_ready=0;always #5 clk=~clk;
reg[159:0] outgoing=0;wire host_tx,b_tx,host_busy,received;
wire[159:0] response;wire[18:0] settings;wire display_valid,pause,media_req,cancel;
wire[2:0] display_image,target;reg[2:0] images=3;
integer counts[0:255];reg[159:0] messages[0:255];integer i,mark,requests=0,cancels=0;
photo_uart #(.CLK_HZ(921600),.BAUD(115200),.PAYLOAD_BYTES(18),.PULSE_PAYLOAD(1)) host(
 .clk(clk),.rst(rst),.rx(b_tx),.tx(host_tx),.send(send),.message(outgoing),
 .busy(host_busy),.received(received),.received_message(response));
photo_typed_control_b #(.CLK_HZ(921600),.TIMER_SCALE(64),.SETTINGS_LINK(1),
 .AWARD_CONTROL(1),.FLUID(1),.AWARD_LIGHTS(1),.RELIEF_CONTROL(1),.BOOT_STATUS(1)) dut(
 .clk(clk),.rst(rst),.uart_rx(host_tx),.uart_tx(b_tx),.image_count(images),
 .award_available(1'b1),.relief_available(1'b1),.award_scan_complete(1'b1),
 .title_ready(1'b0),.title_length(5'd0),.title_data(32'd0),
 .media_ready(media_ready),.media_slot(2'd0),.media_error(4'd0),
 .media_source_width(16'd1280),.media_source_height(16'd720),.tx_done(1'b0),.tx_crc(32'd0),
 .media_request(media_req),.media_target(target),.media_cancel(cancel),
 .settings_state(settings),.display_valid(display_valid),.display_image(display_image),.prefetch_pause(pause),
 .text_pending(1'b0),.text_message(160'd0));
always @(negedge clk)if(!rst)begin
 if(received)begin counts[response[159:152]]=counts[response[159:152]]+1;messages[response[159:152]]=response;end
 if(media_req)requests=requests+1;if(cancel)cancels=cancels+1;
end
task packet;
 input[7:0] kind,image,flags;input[31:0] length,crc,session;input[7:0] status;
 begin
  wait(!host_busy);@(negedge clk);outgoing={kind,session,16'd3,image,flags,length,crc,status,16'd0};send=1;
  @(negedge clk);send=0;wait(host_busy);wait(!host_busy);repeat(12)@(negedge clk);
 end
endtask
initial begin
 for(i=0;i<256;i=i+1)begin counts[i]=0;messages[i]=0;end
 repeat(5)@(negedge clk);rst=0;
 packet(1,0,0,1843200,0,32'h5310,0);wait(counts[2]!=0);
 if(dut.session!==32'h5310)$fatal(1,"HELLO session failed");
 mark=counts[13];packet(12,0,0,0,32'h00012345,32'h5310,0);wait(counts[13]>mark);
 if(settings!==19'h12345 || messages[13][42:24]!==19'h12345)$fatal(1,"settings ACK/data changed");
 mark=counts[13];packet(12,0,0,0,32'h00052345,32'h5310,0);repeat(2000)@(negedge clk);
 if(settings!==19'h12345 || counts[13]!=mark)$fatal(1,"invalid settings bit accepted");
 packet(12,0,0,0,32'h00022222,32'h5311,0);repeat(2000)@(negedge clk);
 if(settings!==19'h12345 || counts[13]!=mark)$fatal(1,"wrong-session settings accepted");
 mark=counts[15];packet(14,1,3,0,0,32'h5310,0);wait(counts[15]>mark);
 if(!display_valid || !pause || display_image!=1)$fatal(1,"display pin context failed");
 mark=counts[15];packet(14,5,2,0,0,32'h5310,0);wait(counts[15]>mark);
 if(display_valid || pause || display_image!=5)$fatal(1,"invalid display target accepted");
 mark=counts[17];packet(16,0,0,0,0,32'h5310,0);wait(counts[17]>mark);
 if(dut.state!=dut.IDLE || cancels<2)$fatal(1,"cancel acknowledgement failed");
 mark=requests;packet(3,2,32,2764800,0,32'h5310,0);wait(requests>mark);
 if(target!=2 || dut.state!=dut.LOAD)$fatal(1,"photo request target/size failed");
 mark=counts[17];packet(16,0,0,0,0,32'h5310,0);wait(counts[17]>mark);
 mark=requests;packet(3,6,0,2764800,0,32'h5310,0);wait(requests>mark);
 if(target!=6)$fatal(1,"award request failed");
 mark=counts[17];packet(16,0,0,0,0,32'h5310,0);wait(counts[17]>mark);
 mark=counts[18];images=4;wait(counts[18]>mark);
 if(messages[18][18:16]!=4)$fatal(1,"catalog growth notification failed");
 packet(19,0,0,0,0,32'h5310,messages[18][23:16]);wait(dut.announced_count[2:0]==4);
 $display("PASS real B UART: HELLO, exact settings reply, rejected mode/session, context bounds, cancel, photo/award requests and catalog growth ACK");$finish;
end
initial begin #20000000;$fatal(1,"B legacy UART timeout state=%d requests=%d",dut.state,requests);end
endmodule
