`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;reg rst=1,pv=0,request=0;
reg[23:0] rgb=0;wire nv,sv,overflow;wire[31:0] nw,sw;
water_pack p(.clk(clk),.rst(rst),.write_req(request),.pixel_valid(pv),.pixel(rgb),.full(1'b0),
 .valid(nv),.data(nw),.overflow(overflow),.small_valid(sv),.small_data(sw));
reg iv=0,last=0,affected=0;reg[31:0] ew;reg[63:0] native;
wire ov;wire[31:0] out_word;
water_reconstruct d(clk,rst,iv,last,affected,ew,native,ov,out_word);
reg[31:0] full_image[0:1279],small_image[0:639];
integer fc=0,sc=0,n,x,y,pass,received=0,row=0,checked=0;reg[15:0] a,b;
function[15:0] source;input integer x,y;reg[4:0] r,b;reg[5:0] g;
 begin r=x/43+y*3;g=(y%2) ? 54-2*(x%24):8+2*(x%24);b=x/11+y*7;source={r,g,b};end
endfunction
function[15:0] filtered;input integer x,y;reg[15:0] a,b,c;integer r,g,bl;
 begin a=source(x==0 ? 0:x-1,y);b=source(x,y);c=source(x+1,y);
 r=((a>>11)+2*(b>>11)+(c>>11)+2)/4;
 g=(((a>>5)&63)+2*((b>>5)&63)+((c>>5)&63)+2)/4;
 bl=((a&31)+2*(b&31)+(c&31)+2)/4;filtered=(r<<11)|(g<<5)|bl;end
endfunction
function[15:0] expected;input integer x,y,fx;reg[15:0] a,b;integer r,g,bl;
 begin
  if(!fx)expected=source(x,y);
  else begin
   a=filtered((x/2)*2,y);b=filtered(x==1279 ? 1278:(x/2)*2+2,y);
   r=((a>>11)+(b>>11)+1)/2;g=(((a>>5)&63)+((b>>5)&63)+1)/2;bl=((a&31)+(b&31)+1)/2;
   expected=x%2 ? (r<<11)|(g<<5)|bl:a;
  end
 end
endfunction
always @(posedge clk)begin
 if(nv)begin full_image[fc]=nw;fc=fc+1;end
 if(sv)begin small_image[sc]=sw;sc=sc+1;end
 if(ov)begin
  a=expected(2*received,row,affected);b=expected(2*received+1,row,affected);
  if(out_word!=={a,b})$fatal(1,"sample origin mismatch row%0d effect%b x%0d got%h expected%h",row,affected,2*received,out_word,{a,b});
  if(affected&&received*2%24>=2&&received*2%24<=20&&out_word[26:21]!==source_green(2*received,row))$fatal(1,"effect/native ramp moved");
  received=received+1;checked=checked+2;
 end
end
function[5:0] source_green;input integer x,y;reg[15:0] c;begin c=source(x,y);source_green=c[10:5];end endfunction
initial begin
 repeat(4)@(negedge clk);rst=0;
 for(y=0;y<2;y=y+1)for(x=0;x<1280;x=x+1)begin
  a=source(x,y);rgb={a[15:11],3'd0,a[10:5],2'd0,a[4:0],3'd0};pv=1;@(negedge clk);pv=0;@(negedge clk);
 end
 repeat(4)@(negedge clk);if(fc!=1280||sc!=640||overflow)$fatal(1,"packer counts");
 for(pass=0;pass<3;pass=pass+1)for(row=0;row<2;row=row+1)begin
  affected=pass==1;received=0;
  for(n=0;n<320;n=n+1)begin
   ew=small_image[row*320+n];native={full_image[row*640+2*n],full_image[row*640+2*n+1]};iv=1;last=n==319;
   @(negedge clk);iv=0;last=0;@(negedge clk);
  end
  repeat(8)@(negedge clk);if(received!=640)$fatal(1,"reconstruction row length");
 end
 $display("PASS sample phase: %0d exact pixels through actual packer/reconstruction, native/effect/native, ascending/descending ramps, identical interior pixel origins and row-edge clamps",checked);$finish;
end
initial begin #200000;$fatal(1,"sample phase timeout");end
endmodule
