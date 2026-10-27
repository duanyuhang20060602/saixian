`timescale 1ns/1ps
module tb;
reg clk=0,rst=1;always #5 clk=~clk;reg[11:0] x=0;reg[10:0] y=0;wire[23:0] rgb;
photo_boot_screen #(.VIDEO_DELAY(26),.STAGED_LOADING(1),.COMPLETE_SCAN(1)) d(
 .clk(clk),.rst(rst),.frame_tick(1'b0),.x(x),.y(y),.memory_ready(1'b1),.catalog_ready(1'b0),.frame_ready(1'b1),
 .animation_ready(1'b1),.audio_ready(1'b1),.scan_ready(1'b0),.font_ready(1'b0),
 .photo_present(1'b1),.music_present(1'b1),.font_present(1'b1),.rgb(rgb),.active());
integer i,j,k,fd;reg[255:0] name;
initial begin
 repeat(5)@(negedge clk);rst=0;
 for(k=0;k<3;k=k+1)begin
  @(negedge clk);d.progress=80+160*k;d.phase=16;
  case(k)0:name="photo.ppm";1:name="music.ppm";2:name="font.ppm";endcase
  fd=$fopen(name,"wb");$fwrite(fd,"P6\n520 180\n255\n");
  for(i=0;i<93625;i=i+1)begin
   @(negedge clk);x=380+i%520;y=240+i/520;
   @(posedge clk);#1;
   if(i>=25)begin
    if((^rgb)===1'bx)$fatal(1,"unknown startup pixel");
    $fwrite(fd,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);
   end
  end
  $fclose(fd);
 end
 $display("PASS production startup renderer snapshots, 26-clock alignment, three stages, no unknown RGB");$finish;
end
endmodule
