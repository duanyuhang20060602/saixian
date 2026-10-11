`timescale 1ns/1ps
module tb_video_handoff;
reg clk=0,rst=1,tick=0,show=0,tf_vs=0,photo_vs=0,de=0;
always #5 clk=~clk;
top dut();
reg previous_vs=0,previous_select=0;integer edges=0;
always @(negedge clk)if(!rst)begin
 if(dut.axis_vs && !previous_vs)edges=edges+1;
 if(dut.tf_output_select!=previous_select && de)$fatal(1,"switched active line");
 previous_vs=dut.axis_vs;previous_select=dut.tf_output_select;
end
task blank;
begin
 @(negedge clk);de=0;photo_vs=1;tick=1;
 @(negedge clk);tick=0;
 repeat(5)@(negedge clk);tf_vs=1;
 repeat(65)@(negedge clk);
 @(negedge clk);photo_vs=0;tf_vs=0;
 repeat(5)@(negedge clk);de=1;
end endtask
initial begin
 force dut.video_clk=clk;force dut.rst_video=rst;force dut.frame_tick=tick;
 force dut.tf_display=show;force dut.tf_vs=tf_vs;force dut.battle_vs=photo_vs;
 force dut.tf_de=de;force dut.battle_de=de;
 repeat(3)@(negedge clk);rst=0;de=1;
 show=1;repeat(80)@(negedge clk);
 if(dut.tf_output_select)$fatal(1,"entry switched before vertical blank");
 blank;if(!dut.tf_output_select || edges!=1)$fatal(1,"entry duplicated sync or lost request");
 show=0;repeat(80)@(negedge clk);
 if(!dut.tf_output_select)$fatal(1,"exit switched before vertical blank");
 blank;if(dut.tf_output_select || edges!=2)$fatal(1,"exit duplicated sync or lost request");
 $display("PASS video handoff: entry/exit only in vertical blank, VS pipeline offsets create no extra sync edge, no active-line splice");$finish;
end
endmodule
