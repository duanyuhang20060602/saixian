`timescale 1ns/1ps
module processing_link_case #(parameter FAST=0,MODE=0)(input clk,rst,output reg finished=0);
localparam FRAME_WORDS=MODE==0 ? 6400:460800;
localparam OUTPUT_WORDS=MODE==0 ? 6400:691200;
reg start=0,arm=0,ack=0,finish_toggle=0;reg [31:0] raw=0;
reg [18:0] settings=19'h0b6d3;
wire req,pop,source_read,empty,ready,write_req,write_en,armed,rx_done,fault,plane_start,effect_plane;
wire processing_start=start || plane_start;
wire [31:0] processed,stored,tx_crc,rx_crc;wire [15:0] data;wire valid,sof,eof;
integer ticks=0,source_index=0,consumer=0,planes=0,maximum=0;
reg [31:0] captured[0:OUTPUT_WORDS-1];
wire full=ticks%103<20 || ticks%701>=589;
wire source_empty=ticks%23<4;
`define PORTS .clk(clk),.rst(rst),.start(processing_start),.abort(1'b0),.read_req(req),.effect_plane(effect_plane),.source_ack(ack),.source_empty(source_empty),.source_data(raw),.settings_state(settings),.image_gain(2'd2),.source_read(source_read),.read_en(pop),.empty(empty),.data(processed)
generate if(FAST)begin
 photo_b_processing #(.FRAME_WORDS(FRAME_WORDS)) process(`PORTS);
end else begin
 photo_b_processing_ref #(.FRAME_WORDS(FRAME_WORDS)) process(`PORTS);
end endgenerate
`undef PORTS
photo_link_sender #(.FRAME_PIXELS(FRAME_WORDS*2),.ENABLE_CRC(1),.PREFETCH_WORD(FAST)) tx(
 .award_frame(1'b0),.clk(clk),.rst(rst),.start(start),.abort(1'b0),.extended_frame(MODE!=0),
 .plane_start(plane_start),.effect_plane(effect_plane),.data(processed),.empty(empty),.read_ack(ack),.link_ready(ready),
 .read_req(req),.read_en(pop),.link_data(data),.link_valid(valid),.link_sof(sof),.link_eof(eof),.frame_crc(tx_crc));
photo_link_receiver #(.FRAME_PIXELS(FRAME_WORDS*2),.ENABLE_CRC(1)) rx(
 .award_frame(1'b0),.clk(clk),.rst(rst),.arm(arm),.abort(1'b0),.extended_frame(MODE!=0),
 .data(data),.valid(valid),.sof(sof),.eof(eof),.ready(ready),.armed(armed),.write_req(write_req),.write_ack(write_req),
 .full(full),.write_en(write_en),.write_data(stored),.finish_toggle(finish_toggle),.done(rx_done),.fault(fault),.frame_crc(rx_crc));
always @(posedge clk)begin
 ticks<=ticks+1;ack<=req;
 if(processing_start)source_index=0;
 else if(source_read)begin
  raw<={16'(source_index*373+41),16'(source_index*107+117)};source_index=source_index+1;
 end
 if(plane_start)planes=planes+1;
 if(write_en && !full)begin
  if(consumer>=OUTPUT_WORDS)$fatal(1,"processing integration overrun");
  captured[consumer]=stored;consumer=consumer+1;
  if(consumer==OUTPUT_WORDS)finish_toggle<=~finish_toggle;
 end
 if(fault)$fatal(1,"processed link framing fault");
end
initial begin
 wait(!rst);@(negedge clk);arm=1;@(negedge clk);arm=0;wait(armed);
 @(negedge clk);start=1;@(negedge clk);start=0;
 wait(rx_done);repeat(4)@(negedge clk);
 if(consumer!=OUTPUT_WORDS || tx_crc!==rx_crc || planes!=(MODE!=0))$fatal(1,"processed link completion mismatch");
 finished=1;
end
endmodule
module tb;
parameter MODE=0;
reg clk=0,rst=1;always #5 clk=~clk;wire a,b;
processing_link_case #(.MODE(MODE)) baseline(clk,rst,a);
processing_link_case #(.MODE(MODE),.FAST(1)) optimized(clk,rst,b);
integer i;
initial begin
 repeat(6)@(negedge clk);rst=0;wait(a && b);
 for(i=0;i<(MODE==0 ? 6400:691200);i=i+1)
  if(baseline.captured[i]!==optimized.captured[i])$fatal(1,"processed pixel differs word %0d",i);
 if(baseline.tx_crc!==optimized.tx_crc)$fatal(1,"processed CRC differs");
 $display("PASS real processing-to-link mode=%0d: %0d identical processed words, native eRAM queue vs frozen register queue, wraparound, source gaps, receiver stalls and plane restart",MODE,i);$finish;
end
initial begin #150000000;$fatal(1,"processed link timeout");end
endmodule
