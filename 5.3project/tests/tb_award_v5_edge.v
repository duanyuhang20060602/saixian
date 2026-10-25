`timescale 1ns/1ps
module tb;
reg clk=0,rst=1;always #5 clk=~clk;
reg tick=0,music=0,pcm_valid=0,de=0,sof=0,eol=0;
reg signed [15:0] pcm_left=0,pcm_right=0;
reg [10:0] x=0;reg [9:0] y=0;reg [23:0] rgb=0;reg [5:0] darkness=0;
wire ade,asof,aeol,bde,bsof,beol;wire [23:0] a,b;wire [7:0] al,bl;
water_edge dut(.clk(clk),.rst(rst),.frame_tick(tick),.music_drive(music),.pcm_valid(pcm_valid),
 .pcm_left(pcm_left),.pcm_right(pcm_right),.x(x),.y(y),.de(de),.sof(sof),.eol(eol),.rgb(rgb),.darkness(darkness),
 .de_out(ade),.sof_out(asof),.eol_out(aeol),.rgb_out(a),.level(al));
water_edge_ref_v5 ref_dut(.clk(clk),.rst(rst),.frame_tick(tick),.music_drive(music),.pcm_valid(pcm_valid),
 .pcm_left(pcm_left),.pcm_right(pcm_right),.x(x),.y(y),.de(de),.sof(sof),.eol(eol),.rgb(rgb),.darkness(darkness),
 .de_out(bde),.sof_out(bsof),.eol_out(beol),.rgb_out(b),.level(bl));
integer c,d,aa,bb,checks=0,n,px,py;reg [31:0] random_state=32'h3719a721;reg [15:0] expected;
initial begin
 for(c=0;c<256;c=c+1)for(d=0;d<64;d=d+1)begin
  expected=c*(32-d);
  if(dut.dark_channel(c,d)!==expected || dut.dark_channel(c,d)!==ref_dut.dark_channel(c,d))$fatal(1,"fade arithmetic %0d %0d",c,d);
 end
 for(aa=-256;aa<256;aa=aa+1)for(bb=0;bb<256;bb=bb+1)begin
  expected=aa*bb;
  if(dut.edge_product(aa,bb)!==expected || dut.edge_product(aa,bb)!==ref_dut.edge_product(aa,bb))$fatal(1,"edge arithmetic %0d %0d",aa,bb);
 end
 repeat(8)@(negedge clk);rst=0;
 for(n=0;n<1237500;n=n+1)begin
  @(negedge clk);
  px=n%1650;py=n/1650;x=px;y=py;
  random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
  rgb=random_state[23:0];darkness=n%64;
  de=px<1280 && py<720;sof=px==0 && py==0;eol=px==1279;
  tick=px==0;music=py%3!=0;pcm_valid=n%13==0;
  pcm_left=random_state[31:16];pcm_right=random_state[15:0];
  @(posedge clk);#1;
  if(n>10 && {ade,asof,aeol,a,al}!=={bde,bsof,beol,b,bl})$fatal(1,"edge pipeline at %0d/%0d",px,py);
  checks=checks+1;
 end
 $display("PASS native edge/fade multipliers: all 147456 operands and %0d complete raster pipeline clocks match shift-add reference",checks);$finish;
end
endmodule
