`timescale 1ns/1ps
module tb_result_text_geometry;
reg clk=0;always #5 clk=~clk;
reg rst=1,ft=0;reg [3:0] state_value=0;
reg [7:0] frame_value=0;reg [9:0] row=0;
saixian_battle_result_fx dut(.clk(clk),.rst(rst),.frame_tick(ft),.trigger(1'b0),
 .select_blue(1'b0),.select_red(1'b0),.select_sprint(1'b0),.x_in(11'd0),.y_in(10'd0),
 .de_in(1'b0),.vs_in(1'b0),.rgb_in(24'd0),.sprint_background_valid(1'b1));
function integer shift_ref(input integer f,onset);
 integer age;
 begin
  age=f-onset;
  if(f<onset)shift_ref=1200;
  else if(age<24)shift_ref=(24-age)*50;
  else shift_ref=0;
 end
endfunction
integer mode,y,i,f,origin,id,expected_shift;reg expected_text;
initial begin
 for(f=0;f<256;f=f+1)for(i=0;i<256;i=i+1)
  if(dut.slide_shift(f,i)!==11'(shift_ref(f,i)))$fatal(1,"Shared slide arithmetic f=%0d onset=%0d",f,i);
 repeat(4)@(negedge clk);rst=0;
 force dut.state=state_value;force dut.raster_y=row;force dut.result_frame=frame_value;
 for(mode=0;mode<3;mode=mode+1)begin
  state_value=mode==1?3:mode==2?5:0;
  for(y=0;y<1024;y=y+1)begin
   @(negedge clk);row=y;id=8;origin=0;
   if(mode==1)for(i=0;i<8;i=i+1)if(y>=143+i*55 && y<187+i*55)begin id=i;origin=151+i*55;end
   if(mode==2)for(i=0;i<3;i=i+1)if(y>=180+i*135 && y<276+i*135)begin id=i;origin=214+i*135;end
   expected_text=id<8 && y>=origin && y<origin+28;
   #1;if(dut.row_text_valid!==expected_text)$fatal(1,"Text band mismatch mode=%d y=%d",mode,y);
   @(posedge clk);#1;if(dut.pre_row_text_valid!==expected_text)$fatal(1,"Text register alignment");
  end
 end
 state_value=5;
 for(f=0;f<256;f=f+1)begin
  @(negedge clk);frame_value=f;
  // Allow the production frame-level base multiply to pre-register before
  // the next frame boundary, matching the real result_frame cadence.
  @(posedge clk);@(negedge clk);ft=1;
  @(negedge clk);ft=0;
  for(i=0;i<3;i=i+1)begin
   row=180+i*135;#1;expected_shift=200+shift_ref(f,(2-i)*16);
   if(dut.row_shift!==12'(expected_shift))$fatal(1,"Biased podium offset mismatch f=%d row=%d",f,i);
  end
 end
 $display("PASS independent text-band reference: all 1024 rows in three modes; all 256 frames x 3 podium offsets, no added raster delay");$finish;
end
initial begin #1000000;$fatal(1,"Timeout");end
endmodule
