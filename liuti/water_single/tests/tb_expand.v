`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;reg rst=1,de=0,vs=0,empty=0;
wire re,od,ov,oh,underflow;reg[31:0] data;
wire[23:0] rgb;
water_expand dut(.video_clk(clk),.rst(rst),.read_en(re),.read_data(data),.read_empty(empty),.display_valid(1'b1),
 .underflow_latched(underflow),.hs(1'b0),.vs(vs),.de(de),.hs_r(oh),.vs_r(ov),.de_r(od),.vout_data(rgb));
function[15:0] texel;input integer n;reg[4:0] r,b;reg[5:0] g;begin r=n;g=n*3;b=n/640;texel={r,g,b};end endfunction
function[23:0] expand;input[15:0] p;begin expand={p[15:11],p[15:13],p[10:5],p[10:9],p[4:0],p[4:2]};end endfunction
function[23:0] expected;input integer n;begin expected=expand(texel(n));end endfunction
integer reads=0,pixels=0,x,y;
always @(posedge clk)begin
 if(re)begin data<={texel(reads*2),texel(reads*2+1)};reads=reads+1;end
 #1;
 if(od)begin
  if(rgb!==expected(pixels))$fatal(1,"interpolator pixel%0d actual%h expected%h",pixels,rgb,expected(pixels));
  pixels=pixels+1;
 end
end
initial begin
 repeat(8)@(negedge clk);rst=0;
 for(y=0;y<4;y=y+1)for(x=0;x<1650;x=x+1)begin @(negedge clk);de=x<1280;end
 @(negedge clk);de=0;repeat(30)@(negedge clk);
 if(pixels!=5120||reads!=2560||underflow)$fatal(1,"interpolator size/underflow pixels%0d reads%0d",pixels,reads);
 $display("PASS native RGB565 scanout: 5120 exact RGB pixels, 2560 source words, exact first/last pixels");$finish;
end
initial begin #200000;$fatal(1,"expand timeout");end
endmodule
