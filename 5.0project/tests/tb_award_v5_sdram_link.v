`timescale 1ns/1ps
// Exercise B's production SDRAM wrapper, native FIFO and link together.
// The calibrated controller contract puts raw data one clock ahead of valid.
module tb #(parameter EXPECT_CORRUPT=0,COLOR=0);
reg mc=0,lc=0,vc=0,rst=1,start=0,arm=0,play=0;
always #10 mc=~mc;always #20 lc=~lc;
// This test decodes rows only after receiving the complete package. Keep
// its unused video domain idle during transfer; continuous scanout is
// independently verified by tb_award_v5_startup and tb_award_v5_bus.
always #6.666667 if(rst || play)vc=~vc;
wire request,read_en,read_ack,empty;wire [31:0] read_data;
wire [15:0] link_data;wire valid,sof,eof,ready,armed,write_req,write_en,done,fault,plane;
wire [31:0] stored,tx_crc,rx_crc;reg finish_toggle=0;
integer ticks=0,words=0,mismatches=0,tail_mismatches=0,first_bad=-1,k;
reg [31:0] expected[0:691199],received[0:230399];
wire full=ticks%53<9;
frame_store #(.FLIP(1),.ENABLE_TOP_DOWN(1)) store(
 .write_award(1'b0),.read_award(1'b1),.write_top_down(1'b0),.high_color(COLOR!=0),
 .write_slot(2'd0),.read_slot(2'd1),.new_slot(2'd0),.slide_active(1'b0),.slide_right(1'b0),.slide_offset(11'd0),.transition_mode(3'd0),
 .mem_clk(mc),.mem_clk_sft(mc),.rst(rst),.write_clk(mc),.write_req(1'b0),.write_en(1'b0),.write_data(32'd0),
 .read_clk(lc),.read_req(request),.read_en(read_en),.read_ack(read_ack),.read_empty(empty),.read_data(read_data));
photo_link_sender #(.ENABLE_CRC(1),.AWARD_TAIL(1),.PREFETCH_WORD(1)) tx(
 .award_frame(1'b1),.clk(lc),.rst(rst),.start(start),.abort(1'b0),.high_color(1'b0),.extended_frame(1'b0),
 .plane_start(plane),.data(read_data),.empty(empty),.read_ack(read_ack),.read_req(request),.read_en(read_en),.link_ready(ready),
 .link_data(link_data),.link_valid(valid),.link_sof(sof),.link_eof(eof),.frame_crc(tx_crc));
photo_link_receiver #(.ENABLE_CRC(1),.AWARD_TAIL(1)) rx(
 .award_frame(1'b1),.clk(lc),.rst(rst),.arm(arm),.abort(1'b0),.high_color(1'b0),.extended_frame(1'b0),
 .data(link_data),.valid(valid),.sof(sof),.eof(eof),.ready(ready),.armed(armed),.write_req(write_req),.write_ack(write_req),
 .full(full),.write_en(write_en),.write_data(stored),.finish_toggle(finish_toggle),.done(done),.fault(fault),.frame_crc(rx_crc));
always @(posedge lc)begin
 ticks<=ticks+1;
 if(write_en && !full)begin
  if(words>=691200)$fatal(1,"extra award words");
  if(stored!==expected[words])begin
   mismatches=mismatches+1;if(first_bad<0)first_bad=words;
   if(words>=460800)tail_mismatches=tail_mismatches+1;
  end
  if(words>=460800)received[words-460800]=stored;
  words=words+1;if(words==691200)finish_toggle<=~finish_toggle;
 end
 if(fault || plane)$fatal(1,"link guard failed");
end
// Decode received data through the same A sparse-row player. Link CRC alone
// cannot discover corruption that happened in B before transmission.
wire lreq,lack,ldv,claim,lrd;wire [20:0] la,lra;wire [31:0] ld;wire [3:0] error;
reg toggle=0;reg [11:0] v=0;reg [31:0] d[0:11];integer j;
always @(posedge mc)begin
 v<={v[10:0],lrd};if(lrd)d[0]<=received[lra];for(j=1;j<12;j=j+1)d[j]<=d[j-1];
end
photo_award_memory bus(.clk(mc),.rst(rst),.enable(play),.init_done(1'b1),.refresh(1'b0),.busy(|v),.frame_busy(1'b0),
 .request(lreq),.address(la),.acknowledge(lack),.data(ld),.valid(ldv),.claim(claim),.read_command(lrd),.read_address(lra),.response_valid(v[11]),.response(d[11]));
photo_spotlight_player player(.mem_clk(mc),.mem_rst(rst),.enable(play),.base(21'd0),
 .stream_start(lreq),.stream_offset(la),.stream_ack(lack),.data(ld),.data_valid(ldv),.error(error),
 .video_clk(vc),.video_rst(rst),.display_valid(1'b0),.pause(1'b0),.rgb_in(24'd0),.de_in(1'b0),.vs_in(1'b0));
initial begin
 $readmemh("award_expected.hex",expected);
 repeat(8)@(negedge lc);rst=0;repeat(8)@(negedge lc);arm=1;@(negedge lc);arm=0;wait(armed);
 @(negedge lc);start=1;@(negedge lc);start=0;
 wait(done);repeat(6)@(negedge lc);
 if(words!=691200 || tx_crc!==rx_crc)$fatal(1,"length/CRC failure");
 play=1;repeat(20)@(negedge mc);
 force player.request_frame=7'd0;force player.request_row=7'd0;force player.request_initial=1'b1;force player.request_toggle=toggle;
 @(negedge mc);toggle=1;wait(player.done_toggle || error);repeat(4)@(negedge mc);
 if(EXPECT_CORRUPT)begin
  if(tail_mismatches<1000 || error!=3)$fatal(1,"old defect not reproduced mismatches=%0d error=%0d",tail_mismatches,error);
  $display("PASS negative control: original B wrapper corrupts %0d tail words despite matching link CRC; A light error=%0d; first bad word=%0d",tail_mismatches,error,first_bad);
 end else begin
  if(mismatches || error || !player.done_toggle)$fatal(1,"B SDRAM award corruption mismatches=%0d tail=%0d first=%0d A error=%0d",mismatches,tail_mismatches,first_bad,error);
  $display("PASS B production SDRAM/FIFO to A: 691200 exact award words, all 230400 light words, link CRC/backpressure and sparse decode; COLOR=%0d",COLOR);
 end
 $finish;
end
initial begin #200000000;$fatal(1,"timeout words=%0d",words);end
endmodule

// Existing board read-calibration contract: data leads valid by one clock.
module sdram(input Clk,Clk_sft,Rst,output Sdr_init_done,Sdr_init_ref_vld,Sdr_busy,
 input App_wr_en,input [20:0] App_wr_addr,input [3:0] App_wr_dm,input [31:0] App_wr_din,
 input App_rd_en,input [20:0] App_rd_addr,output Sdr_rd_en,output [31:0] Sdr_rd_dout);
reg [9:0] val=0;reg [31:0] data[0:9];reg [31:0] memory[0:691199];integer i;
assign Sdr_init_done=!Rst;assign Sdr_init_ref_vld=0;assign Sdr_busy=|val;
assign Sdr_rd_en=val[9];assign Sdr_rd_dout=data[8];
initial $readmemh("award_expected.hex",memory);
always @(posedge Clk)begin
 if(Rst)val<=0;else val<={val[8:0],App_rd_en};
 data[0]<=App_rd_addr>=691200 && App_rd_addr<1382400 ? memory[App_rd_addr-691200]:32'hbad0bad0;
 for(i=1;i<10;i=i+1)data[i]<=data[i-1];
 if(App_wr_en)$fatal(1,"unexpected B write");
end
endmodule
