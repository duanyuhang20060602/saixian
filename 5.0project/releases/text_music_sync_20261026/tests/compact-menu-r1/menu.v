`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,tick=0,de=0;always #5 clk=~clk;
reg [11:0] x=0;reg [10:0] y=0;reg [6:0] ea=0;wire[7:0] ew;wire[23:0] rgb;
reg [23:0] golden[0:921599];reg[15:0] font[0:1023];integer i,j,fd,checks=0;
photo_settings_overlay #(.COMPACT_MENU(1),.MUSIC_SYNC_CONTROL(1),.INTERVAL_CONTROL(1),.SHARED_EDGE_WEIGHT(1),.VIDEO_DELAY(21)) dut(
 .clk(clk),.rst(rst),.frame_tick(tick),.de(de),.settings_mode(1'b1),.updating(1'b0),.x(x),.y(y),.setting_item(4'd14),
 .volume(4'd5),.brightness(4'd4),.contrast(4'd4),.saturation(4'd4),.sharpness(2'd1),.enhancement(2'd1),
 .invert(1'b0),.vintage(1'b0),.effect(5'd1),.edge_enable(1'b0),.auto_enable(1'b1),.waveform_mode(1'b0),.audio_repair_enable(1'b0),
 .music_sync_enable(1'b1),.rgb_in(24'h123456),.rgb_out(rgb),.auto_interval_seconds(5'd5),.edge_weight_address(ea),.edge_weight(ew));
initial begin
 $readmemh("golden.hex",golden);$readmemh("compact.hex",font);
 fd=$fopen("menu.ppm","wb");$fwrite(fd,"P6\n1280 720\n255\n");
 repeat(5)@(negedge clk);rst=0;tick=1;@(negedge clk);tick=0;repeat(25)@(negedge clk);
 for(i=0;i<921620;i=i+1)begin
  @(negedge clk);x=i%1280;y=i/1280;de=i<921600;ea=i%128;
  @(posedge clk);#1;
  if(ew!==(ea[0] ? font[896+(ea>>1)][7:0]:font[896+(ea>>1)][15:8]))$fatal(1,"edge weight changed at %d",ea);
  if(i>=20)begin
   j=i-20;
   if(rgb!==golden[j])$fatal(1,"pixel %d,%d got %h expected %h",j%1280,j/1280,rgb,golden[j]);
   $fwrite(fd,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);checks=checks+1;
  end
 end
 $fclose(fd);if(checks!=921600)$fatal(1,"incomplete frame");
 $display("PASS compact menu: 921600 pixels, 21-cycle geometry, 15 labels, separate sync row, concurrent unchanged edge weights");$finish;
end
endmodule
