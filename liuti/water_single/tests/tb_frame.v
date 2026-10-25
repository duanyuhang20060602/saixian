`timescale 1ns/1ps
// Exercise the actual frame adapter and vendor async FIFO, including the
// data connection downstream of the reader. Independent read/memory clocks.
module tb;
reg mem=0,pixel=0;always #10 mem=~mem;always #6.667 pixel=~pixel;
reg rst=1,req=0,active=0;reg[3:0] mode=0;reg[1:0] index=3;
reg[76:0] cfg=0;wire ack,done,re,empty;wire[20:0] address;
wire[31:0] data,timeouts;reg[13:0] val=0;reg[20:0] addresses[0:13];
sdram_contract contract(mem,rst,re,address);
integer pc=0;wire pop=!empty&&(pc%7==0);
wire[31:0] memory_word={addresses[13][15:0],addresses[13][15:0]^16'hffff};
frame_read_write dut(.rst(rst),.mem_clk(mem),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),
 .App_rd_en(re),.App_rd_addr(address),.Sdr_rd_en(val[13]),.Sdr_rd_dout(memory_word),
 .read_clk(pixel),.read_req(req),.read_req_ack(ack),.read_finish(done),
 .read_addr_0(21'd0),.read_addr_1(21'd691200),.read_addr_2(21'd0),.read_addr_3(21'd1382400),
 .read_addr_index(index),.read_len(21'd5120),.read_en(pop),.read_data(data),.read_fifo_empty(empty),
 .slide_active(active),.slide_old_index(2'd0),.slide_new_index(2'd1),.slide_offset(11'd0),.slide_right(1'b0),
 .transition_mode(mode),.buffer0_vga(1'b0),.buffer1_vga(1'b0),.force_effect_plane(1'b0),.water_cfg(cfg),.read_timeouts(timeouts),
 .write_clk(mem),.write_req(1'b0),.write_addr_0(21'd0),.write_addr_1(21'd691200),
 .write_addr_2(21'd0),.write_addr_3(21'd1382400),.write_addr_index(2'd0),.write_len(21'd0),
 .write_vga(1'b0),.small_write_en(1'b0),.small_write_data(32'd0),.write_en(1'b0),.write_data(32'd0));
integer k,frame=0,received=0,f,z,total=0;reg[31:0] expected;
always @(posedge mem)begin
 val<={val[12:0],re};addresses[0]<=address;
 for(k=1;k<14;k=k+1)addresses[k]<=addresses[k-1];
end
always @(posedge pixel)begin
 pc=pc+1;
 #1;
 if(!rst&&dut.read_buf.valid)begin
  z=$fscanf(f,"%h",expected);
  if(z!=1||data!==expected)$fatal(1,"frame adapter/FIFO mismatch frame%0d word%0d: %h expected %h",frame,received,data,expected);
  received=received+1;total=total+1;
 end
end
initial begin
 f=$fopen("reader_vectors.txt","r");repeat(12)@(negedge mem);rst=0;
 for(frame=0;frame<3;frame=frame+1)begin
  if(frame==1)begin active=1;mode=6;cfg[8:0]=128;end
  if(frame==2)begin active=0;cfg={2'b11,11'd100,11'd200,10'd20,10'd30,12'd80,12'd160,9'd0};end
  received=0;@(negedge mem);req=1;wait(ack);@(negedge mem);req=0;
  wait(done);wait(received==5120);repeat(12)@(negedge mem);
  if(!empty)$fatal(1,"FIFO did not drain");
 end
 if(timeouts!=0)$fatal(1,"reader timeout");
 $display("PASS frame adapter and actual async FIFO: %0d bit-exact words, identity/blend/two drops",total);$finish;
end
initial begin #2000000;$fatal(1,"frame adapter timeout");end
endmodule
