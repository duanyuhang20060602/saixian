`timescale 1ns/1ps
// Production B SDRAM write address FSM, four-beat bursts. Verify both BMP
// bottom-up and DLT top-down mapping, in RGB565 and RGB888 layouts.
module tb_dlt_orientation;
reg clk=0;always #10 clk=~clk;
reg rst=1,req=0,hc=0,td=0;wire ack,finish,we;wire [20:0] addr;
integer mode,count=0,width,expected,total;
frame_fifo_write #(.BURST_SIZE(128),.FRAME_WIDTH(640),.FRAME_HEIGHT(720)) dut(
 .write_top_down(td),.rst(rst),.mem_clk(clk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),
 .Sdr_busy(1'b0),.App_rd_busy(1'b0),.App_wr_en(we),.App_wr_addr(addr),.write_req(req),.write_req_ack(ack),
 .write_finish(finish),.write_addr_0(21'd0),.write_addr_1(21'd0),.write_addr_2(21'd0),.write_addr_3(21'd0),
 .write_addr_index(2'd0),.write_len(hc ? 21'd691200:21'd460800),.write_vga(1'b0),.rdusedw(9'd511));
always @(posedge clk)if(we)begin
 expected=td ? count:(719-count/width)*width+count%width;
 if(addr!==expected)$fatal(1,"row mapping color=%0b top_down=%0b word=%0d got=%0d expected=%0d",hc,td,count,addr,expected);
 count=count+1;
end
initial begin
 for(mode=0;mode<4;mode=mode+1)begin
  rst=1;req=0;hc=mode[1];td=mode[0];width=hc ? 960:640;total=width*720;count=0;
  repeat(6)@(negedge clk);rst=0;repeat(6)@(negedge clk);req=1;wait(ack);@(negedge clk);req=0;
  wait(finish);repeat(5)@(negedge clk);
  if(count!=total)$fatal(1,"write word count color=%0b top_down=%0b count=%0d",hc,td,count);
 end
 $display("PASS B write orientation: all RGB565/RGB888 words, BMP vertical flip, DLT top-down, row boundaries and full-frame lengths");$finish;
end
initial begin #150000000;$fatal(1,"write orientation timeout");end
endmodule
