`timescale 1ns/1ps
module tb_resolution_position;
reg clk=0;always #5 clk=~clk;
reg rst=1;reg [9:0] x=0;reg [8:0] y=0;integer px,py,slot;reg [6:0] expected;
saixian_osd_overlay dut(.clk(clk),.rst(rst),.frame_tick(1'b0),.de_i(1'b1),.x_i(x),.y_i(y),
 .display_valid(1'b1),.state(4'd0),.settings_mode(1'b0),.error_code(3'd0),
 .ticker_text_length(5'd0),.title_text_length(5'd0),.source_width_bcd(16'h1920),.source_height_bcd(16'h1080));
initial begin
 repeat(3)@(negedge clk);rst=0;repeat(3)@(negedge clk);
 for(py=23;py<=40;py=py+1)begin
  for(px=399;px<640;px=px+1)begin
   @(negedge clk);x=px;y=py;@(posedge clk);#1;
   if(px>=400 && px<544 && py>=24 && py<40)begin
    slot=(px-400)/16;
    case(slot)0:expected=2;1:expected=10;2:expected=3;3:expected=1;4:expected=71;5:expected=2;6:expected=1;7:expected=9;8:expected=1;endcase
    if(!dut.text_region || dut.glyph_id!==expected || dut.font_col!==(px-400)%16 || dut.font_row!==py-24)
     $fatal(1,"resolution glyph moved incorrectly at %d,%d",px,py);
   end else if(dut.text_region)$fatal(1,"resolution spills into menu/gap at %d,%d",px,py);
  end
 end
 $display("PASS resolution 1920x1080 at HDMI x800..1087, clear gap and launcher x1152..1255");$finish;
end
endmodule
