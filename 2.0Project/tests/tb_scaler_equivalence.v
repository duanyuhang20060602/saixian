`timescale 1ns/1ps
module tb_scaler_equivalence;
reg clk=0; always #5 clk=~clk;
reg rst=1,start=0,valid=0;
reg [15:0] w=4,h=3;
reg [23:0] rgb=0;
wire av,bv,ab,bb,af,bf;
wire [23:0] ap,bp;
saixian_load_scaler #(.OUT_WIDTH(7),.OUT_HEIGHT(5),.VERTICAL_PERIOD(1)) a(clk,rst,start,w,h,valid,rgb,av,ap,ab,af);
baseline_load_scaler #(.OUT_WIDTH(7),.OUT_HEIGHT(5),.VERTICAL_PERIOD(1)) b(clk,rst,start,w,h,valid,rgb,bv,bp,bb,bf);
integer frames=0,pixels=0,i,x,y,delay_count;
always @(negedge clk) if(!rst) begin
 if(a.h_run && a.sample_x==0 && a.left_pixel!==a.current_pixel) $fatal(1,"first scaler endpoints differ");
 if({av,ab,af} !== {bv,bb,bf} || (av && ap!==bp)) $fatal(1,"scaler mismatch frame=%0d pixel=%0d",frames,pixels);
 if(av) pixels=pixels+1;
end
initial begin
 repeat(4) @(negedge clk); rst=0;
 for(i=0;i<60;i=i+1) begin
  @(negedge clk); w=1+i%12; h=1+(i*7)%9;
  if(i==0) begin w=7;h=5;end
  start=1; @(negedge clk);start=0;repeat(30) @(negedge clk);
  for(y=0;y<h;y=y+1) for(x=0;x<w;x=x+1) begin
   @(negedge clk);rgb=$random;valid=1;
   @(negedge clk);valid=0;
   delay_count=32+($urandom%17);repeat(delay_count) @(negedge clk);
  end
  repeat(150) @(negedge clk);
  if(ab || af || pixels!=(frames+1)*35) $fatal(1,"scaler incomplete or fault");
  frames=frames+1;
 end
 // Abort a partially processed row with a fresh image start.
 @(negedge clk);start=1;@(negedge clk);start=0;
 repeat(30) @(negedge clk);
 valid=1;rgb=24'h123456;@(negedge clk);valid=0;
 repeat(3) @(negedge clk);start=1;@(negedge clk);start=0;
 repeat(100) @(negedge clk);
 rst=1;repeat(3) @(negedge clk);rst=0;
 repeat(5) @(negedge clk);
 $display("PASS scaler equivalence: 60 native/up/downscale images, 2100 exact pixels/cycle, restart/reset");$finish;
end
initial begin #10000000;$fatal(1,"timeout");end
endmodule
