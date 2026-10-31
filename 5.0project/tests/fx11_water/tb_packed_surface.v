`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=1,valid=0;reg[31:0] rgb=0;reg[4:0] shade=0;reg[2:0] shine=0;
reg[4:0] r=0,b=0;wire[4:0] red,blue;wire[5:0] green;
wire out_valid;wire[31:0] lit;
water_light_pair_channel pair(r,b,shade,shine,red,blue);
reg[5:0] g=0;water_light_channel gc(g,1'b1,shade,shine,green);
water_surface_light dut(clk,rst,valid,rgb,shade,shine,out_valid,lit,1'b0);
function[5:0] reference;
 input integer c,s,h,wide;integer v;
 begin v=c-(c*s)/32+h*(wide ? 8:4);
 reference=v>(wide ? 63:31) ? (wide ? 63:31):v;end
endfunction
function[15:0] pixel_ref;
 input[15:0] p;input[4:0] s;input[2:0] h;
 reg[5:0] cr,cg,cb;begin
 cr=reference(p[15:11],s,h,0);cg=reference(p[10:5],s,h,1);cb=reference(p[4:0],s,h,0);
 pixel_ref={cr[4:0],cg,cb[4:0]};end
endfunction
integer ri,bi,si,hi,gi,n,pair_cases=0,green_cases=0,surface_cases=0;
reg[31:0] expected;
reg[31:0] random_state=32'h0917abcd;
function[31:0] next_random;input[31:0] x;begin next_random=(x>>1)^((0-(x&1))&32'hd0000001);end endfunction
initial begin
 for(ri=0;ri<32;ri=ri+1)for(bi=0;bi<32;bi=bi+1)
 for(si=0;si<32;si=si+1)for(hi=0;hi<8;hi=hi+1)begin
  r=ri;b=bi;shade=si;shine=hi;#2;
  if(red!==reference(ri,si,hi,0)||blue!==reference(bi,si,hi,0))
   $fatal(1,"PAIR r=%0d b=%0d shade=%0d shine=%0d got=%0d,%0d",ri,bi,si,hi,red,blue);
  pair_cases=pair_cases+1;
 end
 for(gi=0;gi<64;gi=gi+1)for(si=0;si<32;si=si+1)for(hi=0;hi<8;hi=hi+1)begin
  g=gi;shade=si;shine=hi;#2;
  if(green!==reference(gi,si,hi,1))$fatal(1,"GREEN mismatch");green_cases=green_cases+1;
 end
 @(negedge clk);rst=0;
 for(n=0;n<4096;n=n+1)begin
  @(negedge clk);random_state=next_random(random_state);rgb=random_state;
  random_state=next_random(random_state);shade=random_state[4:0];shine=random_state[7:5];valid=1;
  expected={pixel_ref(rgb[31:16],shade,shine),pixel_ref(rgb[15:0],shade,shine)};
  @(posedge clk);#2;if(out_valid!==0)$fatal(1,"Unexpected early valid");
  @(negedge clk);valid=0;rgb=~rgb;shade=~shade;shine=~shine;
  @(posedge clk);#2;if(out_valid!==1||lit!==expected)$fatal(1,"SURFACE expected=%h got=%h",expected,lit);
  surface_cases=surface_cases+1;
  if(n%17==0)begin
   @(negedge clk);rst=1;@(posedge clk);#2;if(out_valid!==0)$fatal(1,"Reset valid");
   @(negedge clk);rst=0;
  end
  if(n%7==0)begin @(posedge clk);#2;if(out_valid!==0)$fatal(1,"Idle valid");end
 end
 $display("PASS packed_surface pair_cases=%0d green_cases=%0d two_pixel_transactions=%0d exact RGB565 reference, valid cadence and reset",pair_cases,green_cases,surface_cases);
 $finish;
end
endmodule
