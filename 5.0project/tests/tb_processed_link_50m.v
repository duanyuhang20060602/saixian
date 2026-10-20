`timescale 1ns/1ps
// B's production pixel processing -> 50 MHz source-synchronous link -> A's
// real write FIFO. Exercise packed RGB888 phases and FIFO-full backpressure.
module processed_link_case #(parameter HC=1,LINK_HALF=10,CLOCK_SKEW=2,READY_DELAY=3,EXPECT_FAILURE=0)(output reg done=0);
localparam PIXELS=4096,WORDS=HC ? PIXELS*3/4:PIXELS/2;
reg mc=0,lc=0,rst=1,start=0,arm=0;
always #11 mc=~mc;
always #(LINK_HALF) lc=~lc;
wire #(CLOCK_SKEW) ac=lc;
wire rreq,rack,re,source_empty,source_full,source_pop,processing_pop;
wire [31:0] source_data,processed_data;
wire processed_empty;
reg [2:0] rack_pipe=0,wack_pipe=0;
integer produced=0,received=0,cycles=0,full_cycles=0;
reg producing=0,finish=0;
reg mismatch=0;
function [23:0] pixel;input integer n;begin pixel={8'((n*13)^8'hc3),8'((n*29)^8'h41),8'((n*47)^8'h8e)};end endfunction
function [15:0] p565;input integer n;reg [23:0] p;begin p=pixel(n);p565={p[23:19],p[15:10],p[7:3]};end endfunction
function [31:0] word_at;
 input integer n;integer j;reg [23:0] a,b,c,d;
 begin
  if(!HC)word_at={p565(n*2),p565(n*2+1)};
  else begin
   j=(n/3)*4;a=pixel(j);b=pixel(j+1);c=pixel(j+2);d=pixel(j+3);
   case(n%3)0:word_at={a,b[23:16]};1:word_at={b[15:0],c[23:8]};default:word_at={c[7:0],d};endcase
  end
 end
endfunction
wire source_we=producing && !rreq && !source_fifo.wr_rst && !source_full && produced<WORDS && cycles%9!=0;
rfifo_32_32_512 source_fifo(.rst(rst || rreq),.clkw(mc),.clkr(lc),
 .we(source_we),.di(word_at(produced)),.re(source_pop),.dout(source_data),.empty_flag(source_empty),.full_flag(source_full));
wire [18:0] settings={HC!=0,4'd4,4'd4,4'd4,2'd0,2'd0,1'b0,1'b0};
photo_b_processing processing(.clk(lc),.rst(rst),.start(start),.abort(1'b0),.read_req(rreq),
 .source_ack(rack_pipe[2]),.source_empty(source_empty),.source_data(source_data),.settings_state(settings),.image_gain(2'd1),
 .source_read(source_pop),.read_en(re),.empty(processed_empty),.data(processed_data));
wire [15:0] link_data;wire valid,sof,eof,ready,sent,complete,fault,wreq,we,full,empty;
wire [31:0] packed_word,mem_data;
wire [31:0] tx_crc,rx_crc;
wire [15:0] #3 data_at_a=link_data;
wire #3 valid_at_a=valid,sof_at_a=sof,eof_at_a=eof;
wire #(READY_DELAY) ready_at_b=ready;
photo_link_sender #(.FRAME_PIXELS(PIXELS),.ENABLE_CRC(1)) tx(.high_color(HC!=0),.clk(lc),.rst(rst),.start(start),.abort(1'b0),
 .data(processed_data),.empty(processed_empty),.read_ack(rack_pipe[2]),.link_ready(ready_at_b),.read_req(rreq),.read_en(re),
 .link_data(link_data),.link_valid(valid),.link_sof(sof),.link_eof(eof),.done(sent),.frame_crc(tx_crc));
photo_link_receiver #(.FRAME_PIXELS(PIXELS),.ENABLE_CRC(1)) rx(.high_color(HC!=0),.clk(ac),.rst(rst),.arm(arm),.abort(1'b0),
 .data(data_at_a),.valid(valid_at_a),.sof(sof_at_a),.eof(eof_at_a),.ready(ready),
 .write_req(wreq),.write_ack(wack_pipe[2]),.full(full),.write_en(we),.write_data(packed_word),
 .finish_toggle(finish),.done(complete),.fault(fault),.frame_crc(rx_crc));
wire drain=!empty && cycles>40000 && cycles%400<256;
wfifo_32_32_512 dest_fifo(.rst(rst || wreq),.clkw(ac),.clkr(mc),
 .we(we && !full),.di(packed_word),.re(drain),.dout(mem_data),.empty_flag(empty),.full_flag(full));
always @(posedge lc)if(full)full_cycles<=full_cycles+1;
always @(posedge mc)begin
 if(rst)begin rack_pipe<=0;wack_pipe<=0;produced<=0;received<=0;cycles<=0;producing<=0;finish<=0;end
 else begin
  cycles<=cycles+1;rack_pipe<={rack_pipe[1:0],rreq};wack_pipe<={wack_pipe[1:0],wreq};
  if(rreq)begin produced<=0;producing<=1;end
  if(source_we)produced<=produced+1;
  if(drain)begin
   if(mem_data!==word_at(received))begin
    if(EXPECT_FAILURE)mismatch<=1;
    else $fatal(1,"RGB%0d processed/link word %0d got=%h expected=%h",HC ? 888:565,received,mem_data,word_at(received));
   end
   received<=received+1;if(received==WORDS-1)finish<=~finish;
  end
 end
end
always @(posedge lc)if(EXPECT_FAILURE && !done && (mismatch || fault))begin
 $display("PASS baseline reproduces ready-return timing fault: link=%0dMHz skew=%0dns feedback=%0dns rx_count=%0d",500/LINK_HALF,CLOCK_SKEW,READY_DELAY,rx.count);done=1;
end
initial begin
 // Only shorten the hardcoded production frame-length bounds. All byte
 // packing, state machines, queue logic and actual FIFO RTL are unchanged.
 if(HC)begin force tx.final_index=WORDS*2-2;force rx.final_count=WORDS*2-1;force processing.frame_words=WORDS;end
 repeat(6)@(negedge lc);rst=0;start=1;arm=1;
 @(negedge lc);start=0;arm=0;
 wait(complete);repeat(8)@(negedge lc);
 if(EXPECT_FAILURE && !mismatch && !fault)$fatal(1,"baseline timing hazard was not reproduced");
 if(!EXPECT_FAILURE)begin
  if(received!=WORDS || produced!=WORDS || fault || full_cycles==0 || tx_crc!==rx_crc)$fatal(1,"processed link incomplete HC=%0d tx=%0d rx=%0d produced=%0d received=%0d crc=%h/%h",HC,tx.state,rx.state,produced,received,tx_crc,rx_crc);
  $display("PASS RGB%0d production B processing + %0dMHz link + actual A FIFO: %0d ordered words, matching CRC32, skew/delay/full",HC ? 888:565,500/LINK_HALF,WORDS);done=1;
 end
end
initial begin #5000000;if(!done)$fatal(1,"processed link timeout HC=%0d tx=%0d rx=%0d processing=%0d produced=%0d received=%0d",HC,tx.state,rx.state,processing.state,produced,received);end
endmodule
module tb_processed_link_margin;
wire a,b;
processed_link_case #(.HC(1),.CLOCK_SKEW(8),.READY_DELAY(15),.EXPECT_FAILURE(1)) fast(a);
processed_link_case #(.HC(1),.LINK_HALF(20),.CLOCK_SKEW(8),.READY_DELAY(15)) safe(b);
initial begin wait(a && b);$finish;end
endmodule
module tb_processed_link_50m;
wire a,b;processed_link_case #(.HC(0)) normal(a);processed_link_case #(.HC(1)) precise(b);
initial begin wait(a && b);$finish;end
endmodule
