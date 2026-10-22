`timescale 1ns/1ps
module memory_case #(parameter FLIP=0)(output reg done=0);
reg clk=0;always #5 clk=~clk;reg rst=1,wreq=0,rreq=0;
wire wa,ra,we,re,wb,rb,wfinish,rfinish,wclear,rclear;
wire [20:0] waddr,raddr;reg [31:0] cycles=0;reg [8:0] rused=0;
reg read_valid=0;integer writes=0,reads=0,expected,x,y;
frame_fifo_write #(.FRAME_WIDTH(640),.FRAME_HEIGHT(720),.WRITE_V_FLIP(FLIP),.BURST_SIZE(256)) writer(
 .rst(rst),.mem_clk(clk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(cycles[8:0]>500),.Sdr_busy(1'b0),
 .App_rd_busy(rb),.O_wr_busy(wb),.App_wr_en(we),.App_wr_addr(waddr),.write_req(wreq),.write_req_ack(wa),.write_finish(wfinish),
 .write_addr_0(21'd0),.write_addr_1(21'd460800),.write_addr_2(21'd921600),.write_addr_3(21'd0),.write_addr_index(2'd2),
 .write_len(21'd460800),.write_vga(1'b0),.fifo_aclr(wclear),.rdusedw(9'd511));
frame_fifo_read #(.FRAME_WIDTH(640),.BURST_SIZE(256)) reader(
 .rst(rst),.mem_clk(clk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(cycles[8:0]>500),.Sdr_busy(1'b0),.Sdr_rd_en(read_valid),
 .App_wr_busy(wb),.O_rd_busy(rb),.App_rd_en(re),.App_rd_addr(raddr),.read_req(rreq),.read_req_ack(ra),.read_finish(rfinish),
 .read_addr_0(21'd0),.read_addr_1(21'd460800),.read_addr_2(21'd921600),.read_addr_3(21'd0),.read_addr_index(2'd1),
 .read_len(21'd460800),.slide_active(1'b0),.slide_old_index(2'd0),.slide_new_index(2'd0),.slide_offset(11'd0),
 .slide_right(1'b0),.transition_mode(3'd0),.buffer0_vga(1'b0),.buffer1_vga(1'b0),.fifo_aclr(rclear),.wrusedw(rused));
always @(posedge clk)begin
 if(rst)begin cycles<=0;rused<=0;read_valid<=0;end
 else begin
  cycles<=cycles+1;read_valid<=re;
  if(rclear)rused<=0;
  else if(read_valid && !(rused>0 && cycles[1:0]!=0))rused<=rused+1;
  else if(!read_valid && rused>0 && cycles[1:0]!=0)rused<=rused-1;
  if(we && re)$fatal(1,"simultaneous SDRAM read/write application requests");
  if(we)begin
   x=writes%640;y=writes/640;expected=921600+(FLIP ? (719-y)*640:y*640)+x;
   if(waddr!==expected)$fatal(1,"write mapping FLIP=%d word=%d got=%d expected=%d",FLIP,writes,waddr,expected);
   writes=writes+1;
  end
  if(re)begin if(raddr!==460800+reads)$fatal(1,"read mapping word=%d addr=%d",reads,raddr);reads=reads+1;end
 end
end
initial begin
 repeat(4)@(negedge clk);rst=0;wreq=1;rreq=1;
 wait(wa && ra);@(negedge clk);wreq=0;rreq=0;
 wait(writes==460800 && reads==460800);repeat(20)@(negedge clk);
 if(writes!=460800 || reads!=460800)$fatal(1,"overrun at final burst");
 $display("PASS full 460800-word memory FSMs FLIP=%d, slot boundaries, 640-word rows and read/write arbitration",FLIP);done=1;
end
initial begin #40000000;$fatal(1,"memory timeout FLIP=%d write=%d read=%d",FLIP,writes,reads);end
endmodule
module tb_memory;
wire a,b;memory_case #(.FLIP(0)) ac(a);memory_case #(.FLIP(1)) bc(b);
initial begin wait(a && b);$finish;end
endmodule
