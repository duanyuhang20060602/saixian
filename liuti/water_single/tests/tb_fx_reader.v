module tb;
reg clk=0;always #5 clk=~clk;
reg rst=1,req=0,active=0;reg[3:0] mode=0;reg[1:0] index=3;
reg[76:0] cfg=0;wire ack,done,re,we,busy,clear;wire[20:0] address;wire[31:0] data,timeouts;
reg[13:0] val=0;reg[20:0] addresses[0:13];integer cycle=0,fx,dir,step;
sdram_contract contract(clk,rst,re,address);
wire[31:0] memory_word={addresses[13][15:0],addresses[13][15:0]^16'hffff};
water_reader dut(.rst(rst),.mem_clk(clk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),
 .Sdr_rd_en(val[13]),.Sdr_rd_dout(memory_word),.App_wr_busy(cycle%1000<90),.O_rd_busy(busy),.App_rd_en(re),.App_rd_addr(address),
 .read_req(req),.read_req_ack(ack),.read_finish(done),.read_addr_0(21'd0),.read_addr_1(21'd691200),.read_addr_2(21'd0),.read_addr_3(21'd1382400),
 .read_addr_index(2'd0),.slide_old_index(2'd0),.slide_new_index(2'd1),.read_len(21'd5120),.slide_active(active),.slide_right(dir[0]),.transition_mode(mode),.slide_offset(11'd0),
 .force_effect_plane(1'b0),.water_cfg(cfg),.fifo_aclr(clear),.wrusedw(11'd0),.fifo_we(we),.fifo_data(data),.read_timeouts(timeouts));
integer k,j,f,z,expected_addr,frame=0,received=0,sent=0;reg[31:0] expected_word;
always @(posedge clk)begin
 cycle<=cycle+1;val<={val[12:0],re};addresses[0]<=address;
 for(k=1;k<14;k=k+1)addresses[k]<=addresses[k-1];
 if(re)begin
  if(address>=2073600)$fatal(1,"out-of-frame memory address %0d",address);
  sent=sent+1;
 end
 if(we)begin
  z=$fscanf(f,"%h",expected_word);
  if(z!=1||data!==expected_word)$fatal(1,"FIFO pixel mismatch frame%0d word%0d actual%h expected%h",frame,received,data,expected_word);
  received=received+1;
 end
end
initial begin
 f=$fopen("fx_reader_vectors.txt","r");repeat(4)@(negedge clk);rst=0;
 active=1;
 for(fx=0;fx<11;fx=fx+1)for(dir=0;dir<2;dir=dir+1)for(step=0;step<5;step=step+1)begin
  @(negedge clk);mode=fx;cfg=step*64;
  received=0;req=1;wait(ack);@(negedge clk);req=0;wait(done);@(negedge clk);
  if(received!=5120)$fatal(1,"showcase word count %0d",received);frame=frame+1;
 end
 if(timeouts!=0)$fatal(1,"memory timed out");
 $display("PASS integrated showcase reader: 110 frames / 563200 exact RGB565 words, all eleven geometries, both directions, old/new endpoints, local alpha and lighting; %0d SDRAM requests",sent);$finish;
end
initial begin #110000000;$fatal(1,"reader timeout state%0d sent%0d returned%0d written%0d",dut.state,dut.sent,dut.returned,dut.written);end
endmodule
