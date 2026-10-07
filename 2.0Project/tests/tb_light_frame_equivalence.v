`timescale 1ns/1ps
module tb_light_frame_equivalence;
reg clk=0; always #5 clk=~clk;
reg rst=1,req=0,enabled=0,right=0,busy=0;
reg [2:0] mode=0;
reg [10:0] offset=0;
reg [1:0] index=0,old_index=0,new_index=1;
reg vga0=0,vga1=0;
wire en,ref_en,ack,ref_ack,done,ref_done,clear,ref_clear,rd_busy,ref_busy;
wire [20:0] address,ref_address;
frame_fifo_read #(.FRAME_WIDTH(1280)) dut(
 .rst(rst),.mem_clk(clk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),
 .Sdr_busy(1'b0),.Sdr_rd_en(1'b0),.App_wr_busy(busy),.O_rd_busy(rd_busy),
 .App_rd_en(en),.App_rd_addr(address),.read_req(req),.read_req_ack(ack),.read_finish(done),
 .read_addr_0(21'h000000),.read_addr_1(21'h080000),.read_addr_2(21'h100000),.read_addr_3(21'h180000),
 .read_addr_index(index),.read_len(21'd40960),.slide_active(enabled),
 .slide_old_index(old_index),.slide_new_index(new_index),.slide_offset(offset),
 .slide_right(right),.transition_mode(mode),.buffer0_vga(vga0),.buffer1_vga(vga1),
 .fifo_aclr(clear),.wrusedw(9'd0));
frame_fifo_read_ref #(.FRAME_WIDTH(1280)) reference(
 .rst(rst),.mem_clk(clk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),
 .Sdr_busy(1'b0),.Sdr_rd_en(1'b0),.App_wr_busy(busy),.O_rd_busy(ref_busy),
 .App_rd_en(ref_en),.App_rd_addr(ref_address),.read_req(req),.read_req_ack(ref_ack),.read_finish(ref_done),
 .read_addr_0(21'h000000),.read_addr_1(21'h080000),.read_addr_2(21'h100000),.read_addr_3(21'h180000),
 .read_addr_index(index),.read_len(21'd40960),.slide_active(enabled),
 .slide_old_index(old_index),.slide_new_index(new_index),.slide_offset(offset),
 .slide_right(right),.transition_mode(mode),.buffer0_vga(vga0),.buffer1_vga(vga1),
 .fifo_aclr(ref_clear),.wrusedw(9'd0));
integer cycles=0,issues=0;
always @(posedge clk) begin
 #1;
 if(!rst) begin
  cycles=cycles+1;
  if({en,address,ack,done,clear,rd_busy} !== {ref_en,ref_address,ref_ack,ref_done,ref_clear,ref_busy})
   $fatal(1,"controller mismatch cycle=%0d addr=%h expected=%h",cycles,address,ref_address);
  if(en) issues=issues+1;
 end
end
reg [10:0] mx=0,mo=0;reg [9:0] my=0;
reg [20:0] mb0=0,mb1=0;
reg me=0,mr=0;reg [2:0] mm=0;
wire [20:0] mapped;
saixian_frame_mapper #(.FRAME_WIDTH(1280)) mapper(mx,my,mb0,mb1,me,mr,mm,mo,mapped);
integer x,o,d,i,checks=0;
reg [31:0] random_state=32'h1a69fd31;
task check_map;
 reg [20:0] expected;
 begin
  #1; expected=reference.mapped_address(mx,my,mb0,mb1,me,mr,mm,mo);
  if(mapped !== expected) $fatal(1,"mapper mismatch x=%d y=%d off=%d mode=%d right=%d got=%h expected=%h",mx,my,mo,mm,mr,mapped,expected);
  checks=checks+1;
 end
endtask
initial begin
 // Exhaust every visible slide position and column in both directions.
 me=1;mm=0;mb0=21'h1ff800;mb1=21'h090000;
 for(d=0;d<2;d=d+1) begin
  mr=d;
  for(o=0;o<=1280;o=o+1) begin
   mo=o;
   for(x=0;x<1280;x=x+1) begin mx=x;check_map;end
  end
 end
 // All effects, disabled state, address wrapping and out-of-raster inputs.
 for(i=0;i<300000;i=i+1) begin
  random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
  mx=random_state[10:0];my=random_state[20:11];mo=random_state[31:21];
  mm=random_state[26:24];mr=random_state[27];me=random_state[28];
  mb0=random_state[20:0];mb1=random_state[31:11];check_map;
 end
 repeat(3) @(negedge clk);rst=0;
 for(i=0;i<24;i=i+1) begin
  @(negedge clk);enabled=i!=0;mode=i%8;right=i[3];offset=(i*127)%1281;
  old_index=i[1:0];new_index=(i+1)%4;index=(i+2)%4;vga0=i[0];vga1=i[1];req=1;
  wait(ack);repeat(3) @(negedge clk);req=0;
  wait(done);repeat(4) @(negedge clk);
 end
 $display("PASS light mapper %0d exact address checks; %0d complete controller cycles, %0d issued pixels across 24 requests",checks,cycles,issues);
 $finish;
end
initial begin #100000000;$fatal(1,"equivalence timeout");end
endmodule
