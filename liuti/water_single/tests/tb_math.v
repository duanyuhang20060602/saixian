module tb;
reg clk=0;always #5 clk=~clk;
reg rst=1,valid=0,mode,on0,on1;reg[9:0] x,y;reg[8:0] p;reg[10:0] cx0,cx1;reg[9:0] cy0,cy1;reg[11:0] r0,r1;
wire v;wire[9:0] sx,sy,ox,oy;
water_warp d(clk,rst,valid,x,y,mode,p,on0,on1,cx0,cx1,cy0,cy1,r0,r1,v,sx,sy,ox,oy);
integer f,nc,n,i,j,z,a,b,c,e,ex,ey,head=0,tail=0;integer qx[0:31],qy[0:31],qsx[0:31],qsy[0:31];
always @(posedge clk)begin #1;
 if(v)begin
  if(head>=tail||ox!==qx[head%32]||oy!==qy[head%32]||sx!==qsx[head%32]||sy!==qsy[head%32])
   $fatal(1,"geometry mismatch %0d: xy=%0d,%0d mapped=%0d,%0d expected %0d,%0d",head,ox,oy,sx,sy,qsx[head%32],qsy[head%32]);
  head=head+1;
 end
end
initial begin
 f=$fopen("math_vectors.txt","r");z=$fscanf(f,"%d",nc);repeat(4)@(negedge clk);rst=0;
 for(i=0;i<nc;i=i+1)begin
  z=$fscanf(f,"%d %d %d %d %d %d %d %d %d %d %d",mode,p,on0,on1,cx0,cx1,cy0,cy1,r0,r1,n);
  for(j=0;j<n;j=j+1)begin
   @(negedge clk);z=$fscanf(f,"%d %d %d %d",a,b,ex,ey);x=a;y=b;valid=1;
   qx[tail%32]=a;qy[tail%32]=b;qsx[tail%32]=ex;qsy[tail%32]=ey;tail=tail+1;
   @(negedge clk);valid=0;
   if(j%11==0)repeat(j%4)@(negedge clk);
  end
  @(negedge clk);valid=0;repeat(40)@(negedge clk);
 end
 if(head!=tail)$fatal(1,"lost coordinate results");
 $display("PASS %0d streamed coordinates bit-exact to integer reference",head);$finish;
end
initial begin #10000000;$fatal(1,"timeout");end
endmodule
