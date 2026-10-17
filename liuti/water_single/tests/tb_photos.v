module tb;
reg clk=0;always #5 clk=~clk;
reg rst=1,req=0,active=0;reg[3:0] mode=0;reg[1:0] index=3;
reg[76:0] cfg=0;wire ack,done,re,we,busy,clear;wire[20:0] address;wire[31:0] data,timeouts;
reg[13:0] val=0;reg[20:0] addresses[0:13];integer cycle=0,fx,dir,step,photo;
sdram_contract contract(clk,rst,re,address);
reg[15:0] photo_data[0:307199];
reg[2047:0] data_file,golden_file;
function[31:0] memory;input[20:0] a;integer img,offset,row,xx,index;begin
 img=a/691200;offset=a%691200;
 // Physical slot 0 contains this photo; slot 1 contains its successor.
 img=(photo+img)%5;
 if(offset>=460800)begin offset=offset-460800;row=offset/320;xx=(offset%320)*2;index=img*61440+40960+row*640+xx;end
 else begin row=offset/640;xx=(offset%640)*2;index=img*61440+row*1280+xx;end
 if(val[13]&&row>=32)$fatal(1,"photo fixture row out of bounds %0d",row);
 memory={photo_data[index],photo_data[index+1]};
end endfunction
wire[31:0] memory_word=memory(addresses[13]);
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
 if(!$value$plusargs("PHOTO_DATA=%s",data_file)||!$value$plusargs("PHOTO_GOLDEN=%s",golden_file))$fatal(1,"photo fixtures missing");
 $readmemh(data_file,photo_data);photo=0;dir=0;f=$fopen(golden_file,"r");repeat(4)@(negedge clk);rst=0;
 active=1;
 for(photo=0;photo<5;photo=photo+1)for(fx=0;fx<11;fx=fx+1)for(step=1;step<=2;step=step+1)begin
  @(negedge clk);mode=fx;cfg=step*128;dir=photo%2;
  received=0;req=1;wait(ack);@(negedge clk);req=0;wait(done);@(negedge clk);
  if(received!=5120)$fatal(1,"showcase word count %0d",received);frame=frame+1;
 end
 if(timeouts!=0)$fatal(1,"memory timed out");
 $display("PASS five actual TF photos: 110 eight-row frames / 563200 exact RGB565 words, all eleven transitions, native endpoints, packed-cache tail and shared new/native ownership; %0d SDRAM requests",sent);$finish;
end
initial begin #110000000;$fatal(1,"reader timeout state%0d sent%0d returned%0d written%0d",dut.state,dut.sent,dut.returned,dut.written);end
endmodule
