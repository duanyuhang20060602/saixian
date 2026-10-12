`timescale 1ns/1ps
module tb_real_fifo_link_full;
localparam PIXELS=921600,WORDS=PIXELS/2;
reg mem_clk=0,link_clk=0,rst=1,start=0,arm=0;
always #10 mem_clk=~mem_clk;always #80 link_clk=~link_clk;
wire read_req,read_en,read_empty,read_full;wire [31:0] read_data;
reg [2:0] read_ack_pipe=0;integer produced=0,received=0,cycles=0;reg producing=0;
function [31:0] word_at;
 input integer n;reg [15:0] a,b;
 begin a=((2*n)*16'h1237)^16'h8291;b=((2*n+1)*16'h1237)^16'h8291;word_at={a,b};end
endfunction
wire source_write=producing && !read_req && !source_fifo.wr_rst && !read_full && produced<WORDS && cycles%9!=0;
rfifo_32_32_512 source_fifo(.rst(rst || read_req),.clkw(mem_clk),.clkr(link_clk),
 .we(source_write),.di(word_at(produced)),.re(read_en),.dout(read_data),.empty_flag(read_empty),.full_flag(read_full),
 .valid(),.afull(),.aempty(),.wrusedw(),.rdusedw());
wire [15:0] data;wire valid,sof,eof,ready,sent,done,fault,req,we,full,empty;
wire [31:0] packed_word,mem_data;reg [2:0] write_ack_pipe=0;reg finish=0;
photo_link_sender #(.FRAME_PIXELS(PIXELS)) tx(.clk(link_clk),.rst(rst),.start(start),.abort(1'b0),
 .data(read_data),.empty(read_empty),.read_ack(read_ack_pipe[2]),.link_ready(ready),.read_req(read_req),.read_en(read_en),
 .link_data(data),.link_valid(valid),.link_sof(sof),.link_eof(eof),.done(sent),.busy(),.frame_crc());
photo_link_receiver #(.FRAME_PIXELS(PIXELS)) rx(.clk(link_clk),.rst(rst),.arm(arm),.abort(1'b0),
 .data(data),.valid(valid),.sof(sof),.eof(eof),.ready(ready),.armed(),.busy(),
 .write_req(req),.write_ack(write_ack_pipe[2]),.full(full),.write_en(we),.write_data(packed_word),
 .finish_toggle(finish),.done(done),.fault(fault),.frame_crc());
// Stall consumption long enough to exercise the actual full flag and held word.
wire drain=!empty && cycles>40000 && cycles%400<256;
wfifo_32_32_512 dest_fifo(.rst(rst || req),.clkw(link_clk),.clkr(mem_clk),
 .we(we && !full),.di(packed_word),.re(drain),.dout(mem_data),.empty_flag(empty),.full_flag(full),
 .valid(),.afull(),.aempty(),.wrusedw(),.rdusedw());
integer full_cycles=0;
always @(posedge link_clk)if(full)full_cycles<=full_cycles+1;
always @(posedge mem_clk)begin
 if(rst)begin read_ack_pipe<=0;write_ack_pipe<=0;produced<=0;received<=0;cycles<=0;producing<=0;finish<=0;end
 else begin
  cycles<=cycles+1;read_ack_pipe<={read_ack_pipe[1:0],read_req};write_ack_pipe<={write_ack_pipe[1:0],req};
  if(read_req)begin produced<=0;producing<=1;end
  if(source_write)produced<=produced+1;
  if(drain)begin
   if(mem_data!==word_at(received))$fatal(1,"real FIFO word %d got=%h expected=%h",received,mem_data,word_at(received));
   received<=received+1;if(received==WORDS-1)finish<=~finish;
  end
 end
end
initial begin
 repeat(6)@(negedge link_clk);rst=0;start=1;arm=1;
 @(negedge link_clk);start=0;arm=0;
 wait(done);repeat(8)@(negedge link_clk);
 if(received!=WORDS || produced!=WORDS || fault || full_cycles==0)$fatal(1,"real FIFO count/marker/full coverage");
 $display("PASS actual vendor read/write FIFOs, 460800 ordered words, asynchronous clocks and full/empty backpressure");$finish;
end
initial begin #400000000;$fatal(1,"real FIFO timeout tx=%d rx=%d produced=%d received=%d",tx.state,rx.state,produced,received);end
endmodule
