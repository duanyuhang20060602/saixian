`timescale 1ns/1ps
module tb_fifo_full_equivalence;
reg rst=1,clkw=0,clkr=0,we=0,re=0;
reg [31:0] di=0;
wire old_full,new_full;
integer w,r,checks=0;
rfifo_32_32_512 baseline(.rst(rst),.clkw(clkw),.clkr(clkr),.we(we),.di(di),.re(re),.full_flag(old_full));
rfifo_32_32_512 #(.FAST_FULL_COMPARE(1)) optimized(.rst(rst),.clkw(clkw),.clkr(clkr),.we(we),.di(di),.re(re),.full_flag(new_full));
initial begin
 for(w=0;w<512;w=w+1)begin
  force baseline.wr_addr=w;force optimized.wr_addr=w;
  for(r=0;r<512;r=r+1)begin
   force baseline.shift_rdaddr=r;force optimized.shift_rdaddr=r;
   #1;
   if(old_full !== new_full)$fatal(1,"Full flag differs at write=%0d read=%0d",w,r);
   if(baseline.wr_en_s !== optimized.wr_en_s)$fatal(1,"Write gating differs");
   we=1;#1;
   if(baseline.wr_en_s !== optimized.wr_en_s)$fatal(1,"Enabled write gating differs");
   we=0;checks=checks+1;
  end
 end
 $display("PASS: %0d FIFO pointer pairs, full/wr_en identical including wrap",checks);
 $finish;
end
endmodule
