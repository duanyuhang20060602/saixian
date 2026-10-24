`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=1,start=0,arm=0;wire req,rack,read_en,armed,write_req,write_en,ready,tdone,rdone,plane_start;
reg ack=0;reg [31:0] data=0;wire [31:0] stored,tx_crc,rx_crc;wire [15:0] link_data;
wire valid,sof,eof,fault;reg finish_toggle=0;integer producer=0,consumer=0,ticks=0;
wire full=ticks%53<9;
photo_link_sender #(.ENABLE_CRC(1),.AWARD_TAIL(1),.PREFETCH_WORD(1)) tx(.award_frame(1'b1),.clk(clk),.rst(rst),.start(start),.abort(1'b0),
 .extended_frame(1'b0),.plane_start(plane_start),.data(data),.empty(1'b0),.read_ack(ack),.link_ready(ready),
 .read_req(req),.read_en(read_en),.link_data(link_data),.link_valid(valid),.link_sof(sof),.link_eof(eof),.done(tdone),.frame_crc(tx_crc));
photo_link_receiver #(.ENABLE_CRC(1),.AWARD_TAIL(1)) rx(.award_frame(1'b1),.clk(clk),.rst(rst),.arm(arm),.abort(1'b0),
 .extended_frame(1'b0),.data(link_data),.valid(valid),.sof(sof),.eof(eof),.ready(ready),.armed(armed),
 .write_req(write_req),.write_ack(rack),.full(full),.write_en(write_en),.write_data(stored),.finish_toggle(finish_toggle),.done(rdone),.fault(fault),.frame_crc(rx_crc));
assign rack=write_req;
function [31:0] pattern;input integer n;begin pattern=(n*32'h1020305)^32'h97a46b5d;end endfunction
always @(posedge clk)begin
 ticks<=ticks+1;ack<=req;
 if(read_en)begin data<=pattern(producer);producer=producer+1;end
 if(write_en && !full)begin
  if(stored!==pattern(consumer))$fatal(1,"dual-board tail corruption %0d",consumer);
  consumer=consumer+1;if(consumer==691200)finish_toggle<=~finish_toggle;
 end
 if(fault || plane_start)$fatal(1,"award is contiguous; unexpected frame fault or effect-plane restart");
end
initial begin
 repeat(8)@(negedge clk);rst=0;arm=1;@(negedge clk);arm=0;wait(armed);
 @(negedge clk);start=1;@(negedge clk);start=0;
 wait(rdone);repeat(4)@(negedge clk);
 if(consumer!=691200 || producer!=691200 || tx_crc!==rx_crc)$fatal(1,"award transfer incomplete or CRC mismatch");
 $display("PASS contiguous award+light dual-board transfer: 691200 exact words, SOF/EOF, CRC, receiver backpressure, no photo plane restart");$finish;
end
initial begin #100000000;$fatal(1,"link timeout %0d/%0d",producer,consumer);end
endmodule
