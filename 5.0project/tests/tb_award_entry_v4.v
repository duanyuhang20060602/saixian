`timescale 1ns/1ps
module tb_award_entry_v4;
reg clk=0;always #5 clk=~clk;
reg rst=1,enable=0,pause=0,tick=0;wire [23:0] rgb;
photo_award_render dut(.clk(clk),.rst(rst),.enable(enable),.pause(pause),.frame_tick(tick),.x(11'd640),.y(10'd250),.tagged_rgb(24'hb09040),.rgb(rgb),.menu_rgb());
task frame;
 begin @(negedge clk);tick=1;@(negedge clk);tick=0;repeat(6)@(negedge clk);end
endtask
integer n;reg [9:0] saved;reg [10:0] increment;
initial begin
 repeat(5)@(negedge clk);rst=0;enable=1;repeat(5)@(negedge clk);
 if(!dut.effect.live)$fatal(1,"award still has a startup hold");
 saved=dut.effect.motion;frame();if(saved==dut.effect.motion)$fatal(1,"first active frame did not move");
 for(n=0;n<363;n=n+1)begin
  saved=dut.effect.motion;frame();increment=(dut.effect.motion-saved)&1023;
  if(increment!=2 && increment!=3)$fatal(1,"motion stalled or changed speed");
 end
 if(dut.effect.motion!=0 || dut.effect.fraction!=0)$fatal(1,"original 364-frame animation loop changed");
 pause=1;repeat(5)@(negedge clk);saved=dut.effect.motion;repeat(20)frame();
 if(dut.effect.motion!=saved)$fatal(1,"pause broken");
 pause=0;repeat(5)@(negedge clk);frame();if(dut.effect.motion==saved)$fatal(1,"resume broken");
 enable=0;repeat(5)@(negedge clk);enable=1;repeat(5)@(negedge clk);frame();
 if(dut.effect.motion==0)$fatal(1,"re-entry static hold returned");
 $display("PASS award first-frame motion, 364-frame original speed/loop, no entry or re-entry hold, pause/resume");$finish;
end
endmodule
