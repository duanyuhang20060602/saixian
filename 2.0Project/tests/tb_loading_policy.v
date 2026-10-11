`timescale 1ns/1ps
module tb_loading_policy;
reg clk=0,rst=1,active=0,show=0,valid=0;
reg [2:0] error=0;
always #5 clk=~clk;
top dut();
initial begin
 force dut.video_clk=clk;force dut.rst_video=rst;
 force dut.tf_active=active;force dut.display_valid=valid;
 force dut.tf_display=show;
 force dut.tf_output_select=show;
 force dut.error_code=error;force dut.battle_rgb=24'h38e8ff;
 force dut.tf_rgb=24'h123456;
 repeat(3)@(negedge clk);rst=0;@(negedge clk);
 if(dut.axis_rgb!==24'h38e8ff)$fatal(1,"power-on indicator changed");
 active=1;@(negedge clk);
 if(dut.axis_rgb!==0)$fatal(1,"unprepared TF selected");
 valid=1;#1;if(dut.axis_rgb!==24'h38e8ff)$fatal(1,"waiting podium changed");
 show=1;@(negedge clk);
 if(dut.axis_rgb!==24'h123456)$fatal(1,"TF output changed");
 active=0;show=0;@(negedge clk);
 if(dut.axis_rgb!==24'h38e8ff)$fatal(1,"retained photo did not resume immediately");
 valid=0;
 repeat(5)@(negedge clk);
 if(dut.axis_rgb!==0)$fatal(1,"loading suppression lost");
 valid=1;#1;if(dut.axis_rgb!==24'h38e8ff)$fatal(1,"photo did not resume");
 valid=0;error=3'd5;#1;
 if(dut.axis_rgb!==24'h38e8ff)$fatal(1,"error display suppressed");
 rst=1;error=0;@(negedge clk);rst=0;@(negedge clk);
 if(dut.axis_rgb!==24'h38e8ff)$fatal(1,"new boot indicator lost");
 $display("PASS loading policy: preserve initial boot/errors, suppress exit spinner, restore photos, reset history");$finish;
end
endmodule
