`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;reg rst=1,req=0,active=0,right=0;reg[3:0] mode=0;
reg[76:0] cfg=0;wire ack,done,re,we,busy,clear;wire[20:0] address;wire[31:0] data,timeouts;
reg[13:0] val=0;reg[20:0] aq[0:13];integer cycle=0,k,fx,dir,received=0,total=0,frames=0;
sdram_contract contract(clk,rst,re,address);
wire[31:0] memory_word={aq[13][15:0],aq[13][15:0]^16'ha731};
water_reader dut(.rst(rst),.mem_clk(clk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),
 .Sdr_rd_en(val[13]),.Sdr_rd_dout(memory_word),.App_wr_busy(cycle%1024<40),.O_rd_busy(busy),.App_rd_en(re),.App_rd_addr(address),
 .read_req(req),.read_req_ack(ack),.read_finish(done),.read_addr_0(21'd0),.read_addr_1(21'd691200),.read_addr_2(21'd0),.read_addr_3(21'd1382400),
 .read_addr_index(2'd1),.slide_old_index(2'd0),.slide_new_index(2'd1),.read_len(21'd2560),.slide_active(active),.slide_right(right),.transition_mode(mode),.slide_offset(11'd640),
 .force_effect_plane(1'b0),.water_cfg(cfg),.fifo_aclr(clear),.wrusedw(11'd0),.fifo_we(we),.fifo_data(data),.read_timeouts(timeouts));
reg[15:0] a;reg[31:0] expected;
always @(posedge clk)begin
 cycle=cycle+1;val<={val[12:0],re};aq[0]<=address;for(k=1;k<14;k=k+1)aq[k]<=aq[k-1];
 if(re&&(address<691200||address>=1152000))$fatal(1,"transition endpoint did not use native destination: mode%0d address%0d",mode,address);
 if(we)begin
  a=691200+received;expected={a,a^16'ha731};
  if(data!==expected)$fatal(1,"endpoint/commit origin changed mode%0d active%b word%0d got%h expected%h",mode,active,received,data,expected);
  received=received+1;total=total+1;
 end
end
task frame;begin
 received=0;repeat(8)@(negedge clk);req=1;wait(ack);@(negedge clk);req=0;wait(done);@(negedge clk);
 if(received!=2560)$fatal(1,"handoff word count");frames=frames+1;
end endtask
initial begin
 repeat(4)@(negedge clk);rst=0;
 for(fx=0;fx<11;fx=fx+1)for(dir=0;dir<2;dir=dir+1)begin
  mode=fx;right=dir;cfg=77'd256;active=1;frame;active=0;frame;
 end
 if(timeouts)$fatal(1,"read timeout");
 $display("PASS transition handoff: %0d frames, %0d native destination words; all eleven showcase effects, both directions, final transition and first committed frames bit-identical in position and detail",frames,total);$finish;
end
initial begin #12000000;$fatal(1,"handoff timeout");end
endmodule
