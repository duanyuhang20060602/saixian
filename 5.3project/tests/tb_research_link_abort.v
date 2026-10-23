`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,start=0,arm=0,abort=0,hold_full=0,ack=0,finish_toggle=0;
always #5 clk=~clk;
reg [31:0] source_data=0;wire req,read_en,ready,write_req,write_en,armed,rx_done,fault,busy;
wire [15:0] data;wire valid,sof,eof;wire [31:0] stored,tx_crc,rx_crc;
integer ticks=0,producer=0,consumer=0,completed=0;
wire full=hold_full || ticks%17<3;
photo_link_sender #(.FRAME_PIXELS(256),.ENABLE_CRC(1),.PREFETCH_WORD(1)) tx(
 .award_frame(1'b0),.clk(clk),.rst(rst),.start(start),.abort(abort),.extended_frame(1'b0),
 .data(source_data),.empty(1'b0),.read_ack(ack),.link_ready(ready),.read_req(req),.read_en(read_en),
 .link_data(data),.link_valid(valid),.link_sof(sof),.link_eof(eof),.busy(busy),.frame_crc(tx_crc));
photo_link_receiver #(.FRAME_PIXELS(256),.ENABLE_CRC(1)) rx(
 .award_frame(1'b0),.clk(clk),.rst(rst),.arm(arm),.abort(abort),.extended_frame(1'b0),
 .data(data),.valid(valid),.sof(sof),.eof(eof),.ready(ready),.armed(armed),.write_req(write_req),.write_ack(write_req),
 .full(full),.write_en(write_en),.write_data(stored),.finish_toggle(finish_toggle),.done(rx_done),.fault(fault),.frame_crc(rx_crc));
function [31:0] pattern;input integer n;begin pattern=(n*32'h07030119)^32'hc6b347e2;end endfunction
always @(posedge clk)begin
 ticks<=ticks+1;ack<=req;
 if(start)begin producer=0;consumer=0;end
 if(read_en && !abort)begin source_data<=pattern(producer);producer=producer+1;end
 if(write_en && !full && !abort)begin
  if(stored!==pattern(consumer))$fatal(1,"stale prefetched word survived restart at %0d",consumer);
  consumer=consumer+1;if(consumer==128)finish_toggle<=~finish_toggle;
 end
 if(fault && !abort)$fatal(1,"abort/restart frame fault");
end
task begin_frame;begin
 @(negedge clk);arm=1;@(negedge clk);arm=0;wait(armed);
 @(negedge clk);start=1;@(negedge clk);start=0;
end endtask
task cancel_frame;begin
 @(negedge clk);abort=1;repeat(2)@(negedge clk);abort=0;hold_full=0;
 repeat(5)@(negedge clk);
 if(busy || tx.prefetch_pending || tx.prefetch_valid || valid)$fatal(1,"abort did not flush lookahead");
end endtask
task complete_frame;begin
 wait(rx_done);repeat(5)@(negedge clk);
 if(consumer!=128 || producer!=128 || tx_crc!==rx_crc)$fatal(1,"restart transfer incomplete");
 completed=completed+1;
end endtask
initial begin
 repeat(5)@(negedge clk);rst=0;
 begin_frame;wait(tx.prefetch_pending);cancel_frame;
 begin_frame;complete_frame;
 begin_frame;wait(tx.prefetch_pending);@(negedge clk);hold_full=1;wait(tx.prefetch_valid);cancel_frame;
 begin_frame;complete_frame;
 begin_frame;wait(req);cancel_frame;
 begin_frame;complete_frame;
 begin_frame;wait(tx.prefetch_valid);#2;rst=1;repeat(3)@(negedge clk);rst=0;
 begin_frame;complete_frame;
 $display("PASS elastic link cancellation: pending-read abort, buffered-word abort, request abort, asynchronous reset, %0d clean restarts and CRCs",completed);$finish;
end
initial begin #3000000;$fatal(1,"abort test timeout");end
endmodule
