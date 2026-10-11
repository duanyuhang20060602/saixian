`timescale 1ns/1ps
module tb_render_sparse #(parameter COUNT=72);
reg clk=0;always #5 clk=~clk;
reg rst=1,enable=0,tick=0;reg [10:0] x=0;reg [9:0] y=0;
reg [31:0] frame_words[0:460799];reg [15:0] pixel=0;
wire [5:0] green=pixel[0] ? {pixel[10:6],1'b0} : pixel[10:5];
wire [4:0] blue=pixel[0] ? {1'b0,pixel[10:7]} : {pixel[4:1],1'b0};
wire [23:0] base={pixel[15:11],pixel[15:13],green,green[5:4],blue,blue[4:2]};
wire [23:0] rgb;
award_fx dut(clk,rst,enable,1'b0,tick,x,y,base,pixel[5:0],rgb);
integer point_x[0:399999],point_y[0:399999];
string source,dest;integer fd,f,j,k,col,layer,xx,yy,dx,dy,marked=0,points,steps=0,target_steps,cx,cy,index;
reg [15:0] random_seed;reg [10:0] ignored;
task advance;begin @(negedge clk);tick=1;@(negedge clk);tick=0;end endtask
initial begin
 if(!$value$plusargs("source=%s",source)||!$value$plusargs("dest=%s",dest))$fatal;
 $readmemh(source,frame_words);fd=$fopen(dest,"wb");if(!fd)$fatal;
 for(j=0;j<921600;j=j+1)begin
  pixel=j[0] ? frame_words[j/2][31:16] : frame_words[j/2][15:0];
  if(pixel[0])begin point_x[marked]=j%1280;point_y[marked]=j/1280;marked=marked+1;end
 end
 repeat(5)@(negedge clk);rst=0;enable=1;repeat(61)advance;
 for(f=0;f<COUNT;f=f+1)begin
  target_steps=f*364/COUNT;while(steps<target_steps)begin advance;steps=steps+1;end
  points=marked;
  // The same RTL function supplies the sprite bounds. No second effect model.
  for(col=0;col<40;col=col+1)for(layer=0;layer<4;layer=layer+1)begin
   random_seed=dut.seed_for_column(col);
   case(layer)1:random_seed=random_seed^16'h5429;2:random_seed=random_seed^16'h9561;3:random_seed=random_seed^16'h39ac;endcase
   ignored=dut.sprite_address(layer,0,0,dut.motion,random_seed);
   cx=col*32+dut.sprite_address.center_x;cy=dut.sprite_address.center_y;
   for(dy=-16;dy<16;dy=dy+1)for(dx=-16;dx<16;dx=dx+1)begin
    xx=cx+dx;yy=cy+dy;
    if(xx>=0&&xx<1280&&yy>=0&&yy<548)begin point_x[points]=xx;point_y[points]=yy;points=points+1;end
   end
  end
  if(points>400000)$fatal;
  for(j=0;j<points+4;j=j+1)begin
   @(negedge clk);
   if(j<points)begin
    x=point_x[j];y=point_y[j];index=(point_y[j]*1280+point_x[j])/2;
    pixel=point_x[j]%2 ? frame_words[index][31:16] : frame_words[index][15:0];
   end
   @(posedge clk);#1;
   if(j>=4)begin k=j-4;$fwrite(fd,"%c%c%c%c%c%c%c%c",f,point_x[k]&255,(point_x[k]>>8)&255,point_y[k]&255,(point_y[k]>>8)&255,rgb[23:16],rgb[15:8],rgb[7:0]);end
  end
  $display("RTL rendered frame %0d of %0d, %0d affected samples",f+1,COUNT,points);$fflush();
 end
 $fclose(fd);$display("PASS actual RTL preview: %0d full-size frames, all marked mesh/wall pixels and every foil footprint rendered by RTL",COUNT);$finish;
end
endmodule
