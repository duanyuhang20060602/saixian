`timescale 1ns/1ps
module link_case #(parameter MODE=0,FAST=0,STRESS=0,EXPECTED_CRC=0)(input clk,rst,output reg finished=0,output reg [31:0] cycles=0);
localparam WORDS=MODE==0 ? 460800:691200;
reg start=0,arm=0,ack=0,finish_toggle=0;reg [31:0] source_data=0;
wire req,read_en,ready,write_req,write_en,armed,tx_done,rx_done,fault,plane_start,effect_plane;
wire [15:0] data;wire valid,sof,eof;wire [31:0] stored,tx_crc,rx_crc;
integer ticks=0,producer=0,consumer=0,planes=0,begun=0;reg pending=0;
wire full=STRESS && (ticks%53<11 || ticks%997>=915);
wire empty=STRESS && (ticks%37<9 || ticks%1301>=1243);
photo_link_sender #(.ENABLE_CRC(1),.AWARD_TAIL(1),.PREFETCH_WORD(FAST)) tx(
 .award_frame(MODE==3),.clk(clk),.rst(rst),.start(start),.abort(1'b0),.extended_frame(MODE==2),
 .plane_start(plane_start),.effect_plane(effect_plane),.data(source_data),.empty(empty),.read_ack(ack),.link_ready(ready),
 .read_req(req),.read_en(read_en),.link_data(data),.link_valid(valid),.link_sof(sof),.link_eof(eof),.done(tx_done),.frame_crc(tx_crc));
photo_link_receiver #(.ENABLE_CRC(1),.AWARD_TAIL(1)) rx(
 .award_frame(MODE==3),.clk(clk),.rst(rst),.arm(arm),.abort(1'b0),.extended_frame(MODE==2),
 .data(data),.valid(valid),.sof(sof),.eof(eof),.ready(ready),.armed(armed),.write_req(write_req),.write_ack(write_req),
 .full(full),.write_en(write_en),.write_data(stored),.finish_toggle(finish_toggle),.done(rx_done),.fault(fault),.frame_crc(rx_crc));
function [31:0] pattern;input integer n;begin pattern=(n*32'h01020305)^32'h97a46b5d;end endfunction
reg stalled=0;reg [17:0] held=0;
always @(posedge clk)begin
 ticks<=ticks+1;ack<=req;
 if(begun && !finished)cycles<=cycles+1;
 if(read_en)begin
  if(empty || producer>=WORDS)$fatal(1,"source over-read mode=%0d fast=%0d at %0d",MODE,FAST,producer);
  if(MODE==2 && producer==460800 && planes!=1)$fatal(1,"prefetch crossed native/aux plane boundary");
  source_data<=pattern(producer);producer=producer+1;
 end
 if(plane_start)begin
  if(MODE!=2 || producer!=460800 || effect_plane!==1'b1)$fatal(1,"wrong plane restart");
  planes=planes+1;
 end
 if(stalled && {sof,eof,data}!==held)$fatal(1,"pins changed under backpressure");
 stalled=valid && !ready;held={sof,eof,data};
 // A pending output word must survive an arbitrarily long full interval.
 if(pending && (!write_en || stored!==pattern(consumer)))$fatal(1,"pending receive word lost");
 pending=write_en && full;
 if(write_en && !full)begin
  if(stored!==pattern(consumer))$fatal(1,"word order/data mismatch mode=%0d fast=%0d word=%0d",MODE,FAST,consumer);
  consumer=consumer+1;if(consumer==WORDS)finish_toggle<=~finish_toggle;
 end
 if(fault)$fatal(1,"receiver fault mode=%0d fast=%0d",MODE,FAST);
end
initial begin
 wait(!rst);@(negedge clk);arm=1;@(negedge clk);arm=0;wait(armed);
 @(negedge clk);start=1;begun=1;@(negedge clk);start=0;
 wait(rx_done);repeat(4)@(negedge clk);
 if(consumer!=WORDS || producer!=WORDS || tx_crc!==rx_crc || tx_crc!==EXPECTED_CRC || planes!=(MODE==2))
  $fatal(1,"completion mismatch mode=%0d fast=%0d producer=%0d consumer=%0d CRC=%h expected=%h",MODE,FAST,producer,consumer,tx_crc,EXPECTED_CRC);
 finished=1;
 $display("MEASURE mode=%0d stress=%0d prefetch=%0d words=%0d cycles=%0d crc=%08h",MODE,STRESS,FAST,WORDS,cycles,tx_crc);
end
endmodule
module tb;
parameter MODE=0,STRESS=0,EXPECTED_CRC=0;
reg clk=0,rst=1;always #5 clk=~clk;
wire a,b;wire [31:0] old_cycles,new_cycles;
link_case #(.MODE(MODE),.STRESS(STRESS),.EXPECTED_CRC(EXPECTED_CRC)) baseline(clk,rst,a,old_cycles);
link_case #(.MODE(MODE),.FAST(1),.STRESS(STRESS),.EXPECTED_CRC(EXPECTED_CRC)) optimized(clk,rst,b,new_cycles);
initial begin
 repeat(6)@(negedge clk);rst=0;wait(a && b);
 if(new_cycles>=old_cycles)$fatal(1,"prefetch did not reduce transfer duration");
 $display("PASS elastic link mode=%0d stress=%0d baseline=%0d optimized=%0d cycles; exact word count, independent CRC, SOF/EOF, plane isolation, source gaps and receive backpressure",MODE,STRESS,old_cycles,new_cycles);$finish;
end
initial begin #90000000;$fatal(1,"link timeout");end
endmodule
