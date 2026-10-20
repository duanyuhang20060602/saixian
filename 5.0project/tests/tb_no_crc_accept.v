`timescale 1ns/1ps
module tb_no_crc_accept;
reg clk=0;always #5 clk=~clk;
reg rst=1,done=0,got=0;reg [31:0] raw_crc=32'h12345678;
reg [159:0] incoming=0;wire [31:0] local_crc,remote_crc;
wire [3:0] error;
photo_control_a #(.CHECK_FRAME_CRC(0),.CLK_HZ(1152000),.FRAME_BYTES(64)) a(
 .clk(clk),.rst(rst),.uart_rx(1'b1),.uart_tx(),.previous(1'b0),.next(1'b0),
 .active_slot(2'd0),.new_slot(2'd1),.transition_active(1'b0),.commit_toggle(1'b0),
 .receive_slot(),.arm_toggle(),.abort_toggle(),.rx_armed(1'b1),.rx_done(done),.rx_fault(1'b0),.rx_crc(raw_crc),
 .ready_toggle(),.ready_slot(),.ready_right(),.image_count(),.current_image(),.busy(),.error(error),.debug_state(),
 .debug_local_crc(local_crc),.debug_remote_crc(remote_crc));
photo_control_b #(.CHECK_FRAME_CRC(0),.CLK_HZ(1152000),.FRAME_BYTES(64)) b(
 .clk(clk),.rst(rst),.uart_rx(1'b1),.uart_tx(),.image_count(3'd6),.media_ready(1'b1),.media_slot(2'd0),.media_error(4'd0),
 .media_request(),.media_target(),.media_release(),.media_cancel(),.transmit_slot(),.start_toggle(),.abort_toggle(),
 .tx_done(done),.tx_crc(raw_crc),.busy(),.error(),.debug_state());
initial begin
 force a.got=got;force a.incoming=incoming;force a.tx_busy=1'b1;force b.tx_busy=1'b1;
 repeat(4)@(negedge clk);rst=0;
 a.state=7;a.session=32'h789;a.request_seq=9;a.target=0;b.state=6;
 done=1;@(negedge clk);done=0;raw_crc=32'hffffffff;
 incoming={8'd6,32'h789,16'd9,8'd0,8'd0,32'd64,32'h12345678,8'd0,16'd0};got=1;
 @(negedge clk);got=0;repeat(3)@(negedge clk);
 if(a.state!=8 || error!=0 || local_crc!=32'h12345678 || remote_crc!=32'h12345678)
  $fatal(1,"A did not use/freeze completed CRC pair");
 if(b.completed_crc!=32'h12345678)$fatal(1,"B did not freeze completion CRC");
 // Completed frame with differing CRC is accepted in the requested mode.
 a.state=7;a.done_seen=0;a.end_seen=0;raw_crc=32'h11223344;done=1;
 @(negedge clk);done=0;raw_crc=0;got=1;
 @(negedge clk);got=0;repeat(3)@(negedge clk);
 if(a.state!=8 || error!=0 || local_crc!=32'h11223344 || remote_crc!=32'h12345678)
  $fatal(1,"CRC still blocks acceptance");
 $display("PASS no frame CRC gate: unequal local/remote values accepted after complete frame");$finish;
end
initial begin #100000;$fatal(1,"timeout");end
endmodule
