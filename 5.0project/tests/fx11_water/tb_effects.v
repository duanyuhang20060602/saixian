`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=1,iv=0,en=0,right=0;reg[3:0] fx=0;reg[8:0] p=0;reg[9:0] x=0,y=0,wx=0,wy=0;
wire ov;wire[9:0] a,b,c,ox,oy;wire[8:0] alpha;wire[4:0] shade;wire[2:0] shine;
water_effect_map d(clk,rst,iv,en,right,fx,p,x,y,wx,wy,ov,a,b,c,ox,oy,alpha,shade,shine,11'd640,10'd360);
reg[31:0] rgb=0;wire[31:0] lit;water_effect_light light(rgb,shade,shine,lit);
integer f,z,n,count=0,checked=0;
integer vf[0:299999],vp[0:299999],vr[0:299999],ve[0:299999],vx[0:299999],vy[0:299999],vwx[0:299999],vwy[0:299999];
integer ea[0:299999],eb[0:299999],ec[0:299999],eq[0:299999],es[0:299999],eh[0:299999];
reg[31:0] words[0:299999],lit_words[0:299999];
always @(posedge clk)begin #1;
 if(ov)begin
  if({a,b,c,alpha,shade,shine}!=={ea[checked][9:0],eb[checked][9:0],ec[checked][9:0],eq[checked][8:0],es[checked][4:0],eh[checked][2:0]}||ox!=vx[checked]||oy!=vy[checked])
   $fatal(1,"effect map mismatch n%0d effect%0d p%0d xy%0d,%0d got %0d %0d %0d %0d %0d %0d expected %0d %0d %0d %0d %0d %0d",checked,vf[checked],vp[checked],vx[checked],vy[checked],a,b,c,alpha,shade,shine,ea[checked],eb[checked],ec[checked],eq[checked],es[checked],eh[checked]);
  rgb=words[checked];#1;if(lit!==lit_words[checked])$fatal(1,"effect light mismatch %h expected%h",lit,lit_words[checked]);
  checked=checked+1;
 end
end
initial begin
 f=$fopen("effects_vectors.txt","r");if(!f)$fatal(1,"missing vectors");
 while(!$feof(f))begin
  z=$fscanf(f,"%d %d %d %d %d %d %d %d %d %d %d %d %d %d %h %h",vf[count],vp[count],vr[count],ve[count],vx[count],vy[count],vwx[count],vwy[count],ea[count],eb[count],ec[count],eq[count],es[count],eh[count],words[count],lit_words[count]);
  if(z==16)count=count+1;
 end
 repeat(4)@(negedge clk);rst=0;
 for(n=0;n<count;n=n+1)begin
  if(n>0&&(vf[n]!=vf[n-1]||ve[n]!=ve[n-1]||vp[n]!=vp[n-1]||vr[n]!=vr[n-1]))repeat(10)@(negedge clk);
  iv=1;fx=vf[n];p=vp[n];right=vr[n];en=ve[n];x=vx[n];y=vy[n];wx=vwx[n];wy=vwy[n];
  @(negedge clk);iv=0;@(negedge clk);
 end
 repeat(8)@(negedge clk);if(checked!=count)$fatal(1,"effects count");
 $display("PASS eleven showcase maps: %0d exact coordinates, local alpha, shade and specular RGB565 cases; both directions, every progress value, endpoints, borders, disabled path and displaced water",checked);$finish;
end
initial begin #20000000;$fatal(1,"effect timeout");end
endmodule
