`timescale 1ns/1ps
module tb_interval_menu;
reg clk=0;always #5 clk=~clk;
reg rst=1,tick=0;reg [11:0] x=0;reg [10:0] y=0;reg [4:0] seconds=5;
integer i,px,py;reg [6:0] expected;
photo_settings_overlay #(.INTERVAL_CONTROL(1)) dut(.clk(clk),.rst(rst),.frame_tick(tick),.de(1'b1),.settings_mode(1'b1),.updating(1'b0),.x(x),.y(y),.setting_item(4'd14),.volume(4'd5),.brightness(4'd4),.contrast(4'd4),.saturation(4'd4),.sharpness(2'd1),.enhancement(2'd1),.invert(1'b0),.vintage(1'b0),.effect(5'd0),.edge_enable(1'b0),.auto_enable(1'b1),.waveform_mode(1'b0),.audio_repair_enable(1'b0),.auto_interval_seconds(seconds),.rgb_in(24'h123456));
task sample;input [11:0] xx;input [10:0] yy;
begin @(negedge clk);x=xx;y=yy;#1;end endtask
initial begin
 repeat(3)@(negedge clk);rst=0;tick=1;@(negedge clk);tick=0;
 for(i=1;i<=30;i=i+1)begin
  seconds=i;tick=1;@(negedge clk);tick=0;
  sample(608,600);if(dut.glyph!==35+i/10 || !dut.highlight)$fatal(1,"interval tens/highlight %0d",i);
  sample(640,600);if(dut.glyph!==35+i%10)$fatal(1,"interval units %0d",i);
  sample(672,600);if(dut.glyph!==126)$fatal(1,"seconds suffix");
  sample(96,600);if(dut.glyph_id!=37)$fatal(1,"interval label");
  repeat(3)@(negedge clk);if(dut.lookup_glyph!=58)$fatal(1,"interval ROM label not wheel glyph");
 end
 for(py=592;py<624;py=py+1)for(px=64;px<864;px=px+8)begin
  sample(px,py);if(dut.row_index!=14 || !dut.highlight || dut.track)$fatal(1,"new row overlaps old footer/slider");
 end
 sample(96,640);if(dut.glyph_id!=12)$fatal(1,"first footer position");
 sample(96,664);if(dut.glyph_id!=13)$fatal(1,"second footer position");
 sample(96,680);if(dut.text_on)$fatal(1,"footer spill");
 $display("PASS interval menu: 01..30 seconds, real label ROM, selected new row, moved footer and no overlap");$finish;
end
endmodule
