`timescale 1ns/1ps
module tb_render_fx;
reg clk=0;always #5 clk=~clk;
reg rst=1,enable=0,tick=0;reg [10:0] x=0;reg [9:0] y=0;
reg [31:0] frame_words[0:460799];reg [15:0] pixel=0;
wire [5:0] green=pixel[0] ? {pixel[10:6],1'b0} : pixel[10:5];
wire [4:0] blue=pixel[0] ? {1'b0,pixel[10:7]} : {pixel[4:1],1'b0};
wire [23:0] base={pixel[15:11],pixel[15:13],green,green[5:4],blue,blue[4:2]};
wire [23:0] rgb;
award_fx dut(clk,rst,enable,1'b0,tick,x,y,base,pixel[5:0],rgb);
string source,dest;integer fd,f,j,k,xx,yy,steps=0,target_steps;
task advance;begin @(negedge clk);tick=1;@(negedge clk);tick=0;end endtask
initial begin
 if(!$value$plusargs("source=%s",source)||!$value$plusargs("dest=%s",dest))$fatal;
 $readmemh(source,frame_words);fd=$fopen(dest,"wb");if(!fd)$fatal;
 repeat(5)@(negedge clk);rst=0;enable=1;repeat(61)advance;
 for(f=0;f<72;f=f+1)begin
  target_steps=f*364/72;while(steps<target_steps)begin advance;steps=steps+1;end
  for(j=0;j<921604;j=j+1)begin
   @(negedge clk);
   if(j<921600)begin
    xx=j%1280;yy=j/1280;x=xx;y=yy;
    pixel=xx[0] ? frame_words[j/2][31:16] : frame_words[j/2][15:0];
   end
   @(posedge clk);#1;
   if(j>=4)$fwrite(fd,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);
  end
  $display("RTL rendered frame %0d of 72",f+1);$fflush();
 end
 $fclose(fd);$display("PASS actual RTL preview: 72 complete 1280x720 images");$finish;
end
endmodule
