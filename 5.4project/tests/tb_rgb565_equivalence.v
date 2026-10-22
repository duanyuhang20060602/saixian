`timescale 1ns/1ps
// Frozen 5.1 fixed-565 packing and HDMI consumption are the independent oracle.
module tb;
reg clk=0,rst=1,clear=0,valid=0;always #5 clk=~clk;
reg [23:0] input_rgb=0;wire av,bv,aa,ba;wire [31:0] ad,bd;
photo_color_pack actual(.clk(clk),.rst(rst),.clear(clear),.valid(valid),.rgb(input_rgb),.word_valid(av),.word_data(ad),.aligned(aa));
photo_color_pack_frozen frozen(.clk(clk),.rst(rst),.clear(clear),.high_color(1'b0),.valid(valid),.rgb(input_rgb),.word_valid(bv),.word_data(bd),.aligned(ba));
reg de=0,image_valid=1,ack=0,empty=0;reg [11:0] x=0;reg [10:0] y=0;reg [31:0] fifo_data=0;
wire ar,br,ap,bp,armed_a,armed_b,started_a,started_b,under_a,under_b;wire [23:0] rgb_a,rgb_b;
`define PIXELS .clk(clk),.rst(rst),.de(de),.x(x),.y(y),.image_valid(image_valid),.read_ack(ack),.empty(empty),.data(fifo_data)
frame_pixels consume_a(`PIXELS,.read_req(ar),.read_en(ap),.rgb(rgb_a),.armed(armed_a),.output_started(started_a),.underflow(under_a));
frame_pixels_frozen consume_b(`PIXELS,.high_color(1'b0),.read_req(br),.read_en(bp),.rgb(rgb_b),.armed(armed_b),.output_started(started_b),.underflow(under_b));
`undef PIXELS
integer n,words=0;
always @(posedge clk)begin
 if(ap)fifo_data<=$random;
 #1;
 if({av,aa,ad}!=={bv,ba,bd})$fatal(1,"packing phase/data mismatch at %0d",n);
 if({ar,ap,rgb_a,armed_a,started_a,under_a}!=={br,bp,rgb_b,armed_b,started_b,under_b})$fatal(1,"HDMI consumption mismatch at %0d",n);
 if(av)words=words+1;
end
initial begin
 repeat(4)@(negedge clk);rst=0;
 for(n=0;n<120000;n=n+1)begin
  @(negedge clk);
  rst=n%17003==0;clear=n%997==0;valid=$random;input_rgb=$random;
  x=n%1650;y=(n/1650)%750;
  if(n%7000==1)begin x=0;y=720;end
  de=x<1280 && y<720;ack=ar;empty=n%10007==177;image_valid=n%179!=0;
 end
 if(words<20000)$fatal(1,"insufficient packing coverage");
 $display("PASS fixed RGB565: 120000 cycle comparisons to frozen 5.1, packing gaps/clear, HDMI pair order, blanking, ACK, underflow recovery and resets");$finish;
end
endmodule
