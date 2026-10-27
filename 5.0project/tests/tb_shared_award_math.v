`timescale 1ns/1ps
module tb;
reg clk=0,rst=1;always #5 clk=~clk;
reg request=0;reg signed[8:0]br=0,bg=0;reg[3:0]alpha=0;
reg signed[5:0]nx=0,ny=0,lx=0,ly=0;wire signed[14:0]px,py;
photo_award_math_bank dut(clk,rst,request,br,bg,alpha,nx,ny,lx,ly,px,py);
integer a,b,cases=0,ex,ey;
task check;begin
 if(rst)begin ex=0;ey=0;end
 else if(request)begin ex=$signed(br);ey=$signed(bg);ex=ex*alpha;ey=ey*alpha;end
 else begin ex=$signed(nx)*$signed(lx);ey=$signed(ny)*$signed(ly);end
 @(posedge clk);#1;
 if($signed(px)!==ex || $signed(py)!==ey)$fatal(1,"multiply req=%d got=%d/%d expected=%d/%d",request,px,py,ex,ey);
 cases=cases+1;@(negedge clk);
end endtask
initial begin
 check;rst=0;
 for(a=-255;a<=255;a=a+1)for(b=0;b<16;b=b+1)begin request=1;br=a;bg=-a;alpha=b;check;end
 for(a=-32;a<32;a=a+1)for(b=-32;b<32;b=b+1)begin request=0;nx=a;ny=-a-1;lx=b;ly=-b-1;check;end
 for(a=0;a<10000;a=a+1)begin request=a[0];br=$random;bg=$random;alpha=$random;nx=$random;ny=$random;lx=$random;ly=$random;rst=(a%137)==0;check;end
 $display("PASS shared math: %0d exact signed products, both owners, opacity endpoints, alternating ownership and synchronous reset",cases);$finish;
end
endmodule
