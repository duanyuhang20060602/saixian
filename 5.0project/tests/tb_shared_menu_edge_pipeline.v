`timescale 1ns/1ps
module tb #(parameter EXTERNAL=1);
reg clk=0,rst=1;always #5 clk=~clk;
reg[10:0]x=0;reg[9:0]y=0;reg[11:0]mx=0;reg[10:0]my=0;
reg tick=0,drive=0,de=0,sof=0,eol=0,pcm_valid=0;
reg signed[15:0]left=0,right=0;reg[23:0]pixel=0;reg[5:0]darkness=0;reg[7:0]target=0;
reg settings=0,updating=0;reg[3:0]item=0,volume=0,brightness=0,contrast=0,saturation=0;
reg[1:0]sharpness=0,enhancement=0;reg invert=0,vintage=0;reg[4:0]effect=0,interval=0;
reg auto_enable=0,waveform=0,repair=0,edge_enable=0;
wire[6:0]weight_address;wire[7:0]weight;wire[23:0]rgb,old_rgb,menu,old_menu;
wire ode,osof,oeol,old_de,old_sof,old_eol;wire[7:0]level,old_level;
photo_settings_overlay #(.SHARED_EDGE_WEIGHT(1),.VIDEO_DELAY(21),.INTERVAL_CONTROL(1)) screen(
 .edge_weight_address(weight_address),.edge_weight(weight),.clk(clk),.rst(rst),.frame_tick(tick),.de(de),.settings_mode(settings),.updating(updating),.x(mx),.y(my),.setting_item(item),
 .volume(volume),.brightness(brightness),.contrast(contrast),.saturation(saturation),.sharpness(sharpness),.enhancement(enhancement),.invert(invert),.vintage(vintage),.effect(effect),.edge_enable(edge_enable),.auto_enable(auto_enable),.waveform_mode(waveform),.audio_repair_enable(repair),.rgb_in(pixel),.rgb_out(menu),.auto_interval_seconds(interval));
photo_settings_overlay_before #(.VIDEO_DELAY(21),.INTERVAL_CONTROL(1)) old_screen(
 .clk(clk),.rst(rst),.frame_tick(tick),.de(de),.settings_mode(settings),.updating(updating),.x(mx),.y(my),.setting_item(item),
 .volume(volume),.brightness(brightness),.contrast(contrast),.saturation(saturation),.sharpness(sharpness),.enhancement(enhancement),.invert(invert),.vintage(vintage),.effect(effect),.edge_enable(edge_enable),.auto_enable(auto_enable),.waveform_mode(waveform),.audio_repair_enable(repair),.rgb_in(pixel),.rgb_out(old_menu),.auto_interval_seconds(interval));
water_edge #(.EXTERNAL_ENVELOPE(EXTERNAL),.SHARED_WEIGHT(1)) edge_renderer(
 .shared_weight(weight),.weight_address(weight_address),.clk(clk),.rst(rst),.frame_tick(tick),.music_drive(drive),.pcm_valid(pcm_valid),.pcm_left(left),.pcm_right(right),.x(x),.y(y),.de(de),.sof(sof),.eol(eol),.rgb(pixel),.darkness(darkness),.external_target(target),.de_out(ode),.sof_out(osof),.eol_out(oeol),.rgb_out(rgb),.level(level));
water_edge_before #(.EXTERNAL_ENVELOPE(EXTERNAL)) old_edge(
 .clk(clk),.rst(rst),.frame_tick(tick),.music_drive(drive),.pcm_valid(pcm_valid),.pcm_left(left),.pcm_right(right),.x(x),.y(y),.de(de),.sof(sof),.eol(eol),.rgb(pixel),.darkness(darkness),.external_target(target),.de_out(old_de),.sof_out(old_sof),.eol_out(old_eol),.rgb_out(old_rgb),.level(old_level));
integer i,xx,yy,checks=0,pixels=0;reg check_ready=0;
always @(posedge clk)begin #1;
 if(check_ready)begin
  if({rgb,ode,osof,oeol,level,menu}!=={old_rgb,old_de,old_sof,old_eol,old_level,old_menu})begin
   $display("glyph=%h/%h font=%h/%h table=%h/%h id=%h/%h index=%h/%h raw=%h",screen.lookup_glyph,old_screen.lookup_glyph,screen.font_bits,old_screen.font_bits,screen.text_rom_stage.lookup_word,old_screen.text_rom_stage.lookup_word,screen.id_q,old_screen.id_q,screen.index_q,old_screen.index_q,screen.text_rom_stage.text_lookup.raw_text);
   $fatal(1,"packed pipeline mismatch ext=%d x=%d y=%d RGB=%h/%h menu=%h/%h",EXTERNAL,x,y,rgb,old_rgb,menu,old_menu);
  end
  checks=checks+1;
 end
end
task stimulus;input integer n;begin
 pixel=$random;darkness=n%64;target=n%256;pcm_valid=n[0];left=$random;right=$random;
 item=n%14;volume=n%11;brightness=(n/11)%11;contrast=(n/121)%11;saturation=(n/7)%11;sharpness=n%4;enhancement=(n/4)%4;
 effect=n%11;invert=n[0];vintage=n[1];auto_enable=n[2];waveform=n[3];repair=n[4];edge_enable=n[5];interval=n%31;updating=n[6];
end endtask
initial begin
 repeat(6)@(negedge clk);rst=0;check_ready=1;drive=1;settings=1;
 // Independent menu and edge coordinates cover simultaneous reads, even
 // though these normally appear at different taps of the production raster.
 for(yy=0;yy<750;yy=yy+1)for(xx=0;xx<1650;xx=xx+1)begin
  @(negedge clk);x=xx;y=yy;mx=xx;my=yy;de=xx<1280 && yy<720;sof=xx==0&&yy==0;eol=xx==1279;tick=xx==0;stimulus(xx+yy*1650);if(de)pixels=pixels+1;
 end
 for(i=0;i<200000;i=i+1)begin
  @(negedge clk);x=$random;y=$random;mx=$random;my=$random;stimulus(i);de=i[0];sof=i%131==0;eol=i%127==0;tick=i%97==0;settings=i[7];drive=i[8];rst=i%12347==0;
 end
 if(pixels!=921600)$fatal(1,"incomplete full-frame coverage");
 $display("PASS shared menu/edge pipeline ext=%0d: %0d exact RGB/menu/sync/level checks, 921600 visible pixels, independent ports, all settings, outside coordinates, enable/disable, PCM, darkness and reset",EXTERNAL,checks);$finish;
end
endmodule
