`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,key2_n=1;wire [2:0] mode;integer i;
always #5 clk=~clk;
photo_pitch_keys #(.CLK_HZ(1000)) dut(.*);
task short;
 begin key2_n=0;repeat(50)@(negedge clk);key2_n=1;repeat(50)@(negedge clk);end
endtask
initial begin
 repeat(5)@(negedge clk);rst=0;repeat(30)@(negedge clk);
 if(mode!==0)$fatal(1,"default");
 // Contact chatter shorter than debounce never changes the mode.
 repeat(5)begin key2_n=0;repeat(3)@(negedge clk);key2_n=1;repeat(3)@(negedge clk);end
 repeat(30)@(negedge clk);if(mode!==0)$fatal(1,"bounce");
 for(i=1;i<=5;i=i+1)begin short();if(mode!==i%5)$fatal(1,"cycle %0d",i);end
 short();short();if(mode!==2)$fatal(1,"setup");
 key2_n=0;repeat(1100)@(negedge clk);if(mode!==0)$fatal(1,"long hold restore");
 repeat(1100)@(negedge clk);key2_n=1;repeat(60)@(negedge clk);
 if(mode!==0)$fatal(1,"long release generated short");
 short();if(mode!==1)$fatal(1,"rearm");
 $display("PASS B KEY2 debounce, five modes, wrap, one-second restore, no duplicate on release");$finish;
end
endmodule
