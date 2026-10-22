`timescale 1ns/1ps
module tb_auto_compat;
reg clk=0;always #5 clk=~clk;
reg rst=1,enable=1,valid=1,transition=0,busy=0,enough=1,menu=0,manual=0;
wire pulse,ref_pulse;integer i,count=0;
photo_auto_advance #(.CLK_FREQ_HZ(13),.HOLD_SECONDS(3)) dut(clk,rst,enable,valid,transition,busy,enough,menu,manual,pulse,5'd0);
page_auto_reference #(.CLK_FREQ_HZ(13),.HOLD_SECONDS(3)) reference(clk,rst,enable,valid,transition,busy,enough,menu,manual,ref_pulse);
initial begin
 repeat(3)@(negedge clk);rst=0;
 for(i=0;i<20000;i=i+1)begin
  @(negedge clk);
  if(i%100==0)begin enable=1;valid=1;transition=0;busy=0;enough=1;menu=0;manual=0;rst=0;end
  if(i%100==85)begin enable=$random;valid=$random;transition=$random;busy=$random;enough=$random;menu=$random;manual=$random;rst=($random%7==0);end
  @(posedge clk);#1;
  if(pulse!==ref_pulse)$fatal(1,"legacy auto pulse moved at %0d",i);
  if(pulse)count=count+1;
 end
 if(count<200)$fatal(1,"insufficient interval coverage");
 $display("PASS autoplay compatibility: 20000 cycles equal original, fixed period, manual/busy/menu/transition/reset gates");$finish;
end
endmodule
