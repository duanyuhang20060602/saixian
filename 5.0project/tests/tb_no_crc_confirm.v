`timescale 1ns/1ps
// Controller boundary test: inject decoded packets. Wire/CRC parsing has its
// own tb_uart; tb_system also connects real UARTs end to end.
module tb_no_crc_confirm;
reg clk=0;always #5 clk=~clk;reg rst=1;reg [159:0] payload=0;reg valid=0;
wire release_slot,cancel;wire [3:0] error;
photo_control_b #(.CHECK_FRAME_CRC(0),.CLK_HZ(1152000),.FRAME_BYTES(64)) b(.clk(clk),.rst(rst),.uart_rx(1'b1),.uart_tx(),
 .image_count(3'd6),.media_ready(1'b1),.media_slot(2'd1),.media_error(4'd0),.media_request(),.media_target(),
 .media_release(release_slot),.media_cancel(cancel),.transmit_slot(),.start_toggle(),.abort_toggle(),
 .tx_done(1'b0),.tx_crc(32'h12345678),.busy(),.error(error));
integer releases=0;
always @(posedge clk)if(release_slot)releases=releases+1;
task inject;
 input [7:0] kind;input [31:0] session;input [15:0] seq;input [7:0] image;input [31:0] crc;
 begin @(negedge clk);payload={kind,session,seq,image,8'd0,32'd64,crc,8'd0,16'd0};
 // Real UART payload settles during the CRC bytes before received pulses.
 repeat(2)@(negedge clk);valid=1;
 @(negedge clk);valid=0;repeat(3)@(negedge clk);end
endtask
initial begin
 force b.got=valid;force b.incoming=payload;
 repeat(4)@(negedge clk);rst=0;
 // Seed a transaction after the END message; all subsequent updates are RTL.
 b.session=32'h789;b.request_seq=16'd9;b.media_target=3'd4;b.completed_crc=32'h12345678;b.state_flags=(11'd1<<8);
 inject(7,'h788,9,4,'h12345678);if(b.state!=8)$fatal(1,"wrong session accepted");
 inject(7,'h789,8,4,'h12345678);if(b.state!=8)$fatal(1,"old sequence accepted");
 inject(7,'h789,9,3,'h12345678);if(b.state!=8)$fatal(1,"wrong image accepted");
 inject(7,'h789,9,4,32'd0);if(b.state!=9 || releases!=0)$fatal(1,"ACCEPT released before transition");
 inject(7,'h789,9,4,32'd0);if(b.state!=9 || releases!=0)$fatal(1,"duplicate ACCEPT changed transaction");
 inject(8,'h789,8,4,'h12345678);if(b.state!=9)$fatal(1,"old COMMIT accepted");
 inject(8,'h789,9,4,32'd0);if(b.state!=2 || releases!=1)$fatal(1,"COMMIT did not release exactly once");
 inject(8,'h789,9,4,32'd0);if(b.state!=2 || releases!=1)$fatal(1,"duplicate COMMIT released twice");
 $display("PASS no frame CRC in ACCEPT/COMMIT; session/sequence/image and duplicate confirmation protection");$finish;
end
initial begin #200000;$fatal(1,"confirmation timeout");end
endmodule
