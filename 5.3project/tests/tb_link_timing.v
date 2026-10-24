`timescale 1ns/1ps
// Stress a slow data bit relative to forwarded clock and control wires.
// These delays are a simulation case, not measured board delay values.
module tb_link_timing;
reg bclk=0;always #40 bclk=~bclk;wire aclk;assign #6 aclk=bclk;
reg rst=1,start=0,arm=0;wire [15:0] data;wire valid,sof,eof,ready_a,ready_b,sent,done,armed,fault;
wire [31:0] tx_crc,rx_crc,read_data,write_data;
wire req,re,write_req,we;reg [1:0] read_ack=0,write_ack=0;reg [31:0] memory_word=0;
integer read_index=0,write_index=0;reg finish=0;
wire [15:0] rx_data;assign #55 rx_data[0]=data[0];assign #4 rx_data[15:1]=data[15:1];
wire rx_valid,rx_sof,rx_eof;
assign #3 rx_valid=valid;assign #3 rx_sof=sof;assign #3 rx_eof=eof;assign #9 ready_b=ready_a;
function [15:0] pattern;
 input integer p;begin pattern=(p*16'h1237)^16'h8291;end
endfunction
always @(posedge bclk)begin
 read_ack<={read_ack[0],req};
 if(req)read_index<=0;
 if(re)begin memory_word<={pattern(read_index*2),pattern(read_index*2+1)};read_index<=read_index+1;end
end
assign read_data=memory_word;
photo_link_sender #(.ENABLE_CRC(1),.LEGACY_TIMING(0),.FRAME_PIXELS(32)) tx(.clk(bclk),.rst(rst),.start(start),.abort(1'b0),.data(read_data),.empty(1'b0),
 .read_ack(read_ack[1]),.link_ready(ready_b),.read_req(req),.read_en(re),.link_data(data),.link_valid(valid),.link_sof(sof),.link_eof(eof),
 .done(sent),.busy(),.frame_crc(tx_crc));
photo_link_receiver #(.ENABLE_CRC(1),.LEGACY_TIMING(0),.FRAME_PIXELS(32)) rx(.clk(aclk),.rst(rst),.arm(arm),.abort(1'b0),.data(rx_data),.valid(rx_valid),.sof(rx_sof),.eof(rx_eof),
 .ready(ready_a),.armed(armed),.busy(),.write_req(write_req),.write_ack(write_ack[1]),.full(1'b0),.write_en(we),.write_data(write_data),
 .finish_toggle(finish),.done(done),.fault(fault),.frame_crc(rx_crc));
reg pixel_bad=0;
always @(posedge aclk)begin
 write_ack<={write_ack[0],write_req};
 if(write_req)write_index<=0;
 if(we)begin
  if(write_data!=={pattern(write_index*2),pattern(write_index*2+1)})pixel_bad<=1;
  write_index<=write_index+1;
  if(write_index==15)finish<=~finish;
 end
end
initial begin
 repeat(5)@(negedge bclk);rst=0;
 @(negedge aclk);arm=1;@(negedge aclk);arm=0;wait(armed);
 @(negedge bclk);start=1;@(negedge bclk);start=0;
 wait(done);repeat(5)@(negedge aclk);
 if(fault || pixel_bad || rx_crc!=tx_crc)$fatal(1,"delayed data bit: pixels_bad=%d CRC=%h/%h",pixel_bad,rx_crc,tx_crc);
 $display("PASS delayed-data/forwarded-clock/feedback stress, pixel reference and frame CRC");$finish;
end
initial begin #200000;$fatal(1,"timing model timeout");end
endmodule
