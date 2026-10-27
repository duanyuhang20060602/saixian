`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,tick=0,transition=0,enabled=1;reg[10:0] px=200;reg[9:0] py=150;wire[76:0] cfg;
always #5 clk=~clk;
water_scene #(.POINTER_CENTER(1)) d(.clk(clk),.rst(rst),.frame_tick(tick),.display_valid(1'b1),.transition_active(transition),
 .wave_enable(1'b1),.manual_drop(1'b0),.progress(9'd100),.cfg(cfg),.pointer_enabled(enabled),.pointer_x(px),.pointer_y(py));
task frame;begin @(negedge clk);tick=1;@(negedge clk);tick=0;end endtask
initial begin
 repeat(5)@(negedge clk);rst=0;frame;transition=1;#1;
 if(cfg[74:64]!=200 || cfg[52:43]!=150 || cfg[76:75]!=0)$fatal(1,"transition did not capture pointer");
 px=1000;py=600;repeat(10)frame;
 if(cfg[74:64]!=200 || cfg[52:43]!=150)$fatal(1,"moving pointer tore active transition");
 transition=0;frame;transition=1;#1;
 if(cfg[74:64]!=1000 || cfg[52:43]!=600)$fatal(1,"next transition did not use new pointer");
 transition=0;px=2047;py=1023;frame;transition=1;#1;
 if(cfg[74:64]!=1279 || cfg[52:43]!=719)$fatal(1,"pointer bounds not clamped");
 transition=0;enabled=0;frame;transition=1;#1;
 if(cfg[74:64]!=640 || cfg[52:43]!=360)$fatal(1,"disabled pointer did not use screen center");
 $display("PASS transition pointer origin snapshot, next-switch update, corner clamp and disabled fallback");$finish;
end
endmodule
