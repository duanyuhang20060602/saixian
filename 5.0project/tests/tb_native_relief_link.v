`timescale 1ns/1ps
module tb #(parameter KIND=2,WORDS=985088);
reg clk=0;always #20 clk=~clk;reg rst=1,start=0,arm=0;
reg award_input=KIND!=0,relief_input=KIND==2,extended_input=KIND==0;
wire read_req,read_en,write_req,we,ready,valid,sof,eof,tx_done,rx_done,fault,plane;
wire [15:0] payload;wire [31:0] wd,tx_crc,rx_crc;reg [31:0] src=0,crc_expected[0:0];
reg read_ack=0,write_ack=0,finish_toggle=0;integer offered=0,accepted=0,cycle=0,drain=0,planes=0;reg seen_tx=0,seen_rx=0;
wire full=cycle%53<7;wire empty=offered>=WORDS;
function [31:0] pattern;input [31:0] n;begin pattern=(n*32'h045d9f3b)^32'h96ac37e1;end endfunction
photo_link_sender #(.ENABLE_CRC(1),.LEGACY_TIMING(1),.AWARD_TAIL(1),.PREFETCH_WORD(1)) tx(
 .relief_frame(relief_input),.award_frame(award_input),.extended_frame(extended_input),.clk(clk),.rst(rst),.start(start),.abort(1'b0),
 .plane_start(plane),.effect_plane(),.data(src),.empty(empty),.read_ack(read_ack),.link_ready(ready),
 .read_req(read_req),.read_en(read_en),.link_data(payload),.link_valid(valid),.link_sof(sof),.link_eof(eof),.done(tx_done),.busy(),.frame_crc(tx_crc));
photo_link_receiver #(.ENABLE_CRC(1),.LEGACY_TIMING(1),.AWARD_TAIL(1)) rx(
 .relief_frame(relief_input),.award_frame(award_input),.extended_frame(extended_input),.clk(clk),.rst(rst),.arm(arm),.abort(1'b0),
 .data(payload),.valid(valid),.sof(sof),.eof(eof),.ready(ready),.armed(),.busy(),.write_req(write_req),.write_ack(write_ack),
 .full(full),.write_en(we),.write_data(wd),.finish_toggle(finish_toggle),.done(rx_done),.fault(fault),.frame_crc(rx_crc),.fault_detail());
always @(posedge clk)begin
 cycle<=cycle+1;read_ack<=read_req;write_ack<=write_req;
 if(read_en)begin if(offered>=WORDS)$fatal(1,"source read past packet");src<=pattern(offered);offered<=offered+1;end
 if(plane)planes<=planes+1;
 if(we && !full)begin
  if(accepted>=WORDS || wd!==pattern(accepted))$fatal(1,"link payload wrong kind=%0d word=%0d got=%h",KIND,accepted,wd);
  accepted<=accepted+1;
  if(accepted==127)begin award_input<=!award_input;relief_input<=!relief_input;extended_input<=!extended_input;end
  if(accepted==WORDS-1)drain<=12;
 end
 if(drain>0)begin drain<=drain-1;if(drain==1)finish_toggle<=~finish_toggle;end
 if(tx_done)seen_tx<=1;if(rx_done)seen_rx<=1;if(!rst && fault)$fatal(1,"production link receiver fault");
end
initial begin
 $readmemh("expected_crc.hex",crc_expected);repeat(8)@(negedge clk);rst=0;arm=1;start=1;@(negedge clk);arm=0;start=0;
 wait(seen_tx && seen_rx);repeat(5)@(negedge clk);
 if(offered!=WORDS || accepted!=WORDS || planes!=(KIND==0?1:0) || tx_crc!==crc_expected[0] || rx_crc!==crc_expected[0])
  $fatal(1,"link completion/CRC kind=%0d offered=%0d accepted=%0d planes=%0d crc=%h/%h expected=%h",KIND,offered,accepted,planes,tx_crc,rx_crc,crc_expected[0]);
 $display("PASS native/legacy/photo production link kind=%0d words=%0d: exact payload, independent CRC, full backpressure, complete native EOF and latched mode despite mid-packet changes",KIND,accepted);$finish;
end
initial begin #1000000000;$fatal(1,"link timeout kind=%0d words=%0d state=%0d/%0d",KIND,accepted,tx.state,rx.state);end
endmodule
