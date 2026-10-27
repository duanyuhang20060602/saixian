`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,tick=0,memory_ready=0,scan=0,frame_ready=0,audio_ready=0,font_ready=0;
reg present=1;wire active;wire[23:0] rgb;
always #5 clk=~clk;
photo_boot_screen #(.VIDEO_DELAY(6),.MIN_FRAMES(1),.STAGED_LOADING(1),.COMPLETE_SCAN(1)) d(
 .clk(clk),.rst(rst),.frame_tick(tick),.x(12'd421),.y(11'd380),
 .memory_ready(memory_ready),.catalog_ready(scan),.animation_ready(1'b1),.audio_ready(audio_ready),.frame_ready(frame_ready),
 .scan_ready(scan),.font_ready(font_ready),.photo_present(present),.music_present(present),.font_present(present),.active(active),.rgb(rgb));
task frames;input integer n;integer k;begin
 for(k=0;k<n;k=k+1)begin @(negedge clk);tick=1;@(negedge clk);tick=0;repeat(8)@(negedge clk);end
end endtask
integer i;reg[23:0] still_color;
initial begin
 repeat(5)@(negedge clk);rst=0;frames(5);
 if(!active || d.progress!=0)$fatal(1,"boot started without photo");
 memory_ready=1;frame_ready=1;frames(25);
 if(!active || d.progress!=160)$fatal(1,"photo milestone is not one third");
 audio_ready=1;frames(25);
 if(!active || d.progress!=320)$fatal(1,"music milestone is not two thirds");
 scan=1;frames(100);
 if(!active || d.progress!=320)$fatal(1,"boot exited before A font publication");
 if(d.pipeline_character(2,5)!="1" || d.pipeline_character(3,5)!="2" || d.pipeline_character(5,4)!="3")$fatal(1,"stage label mismatch");
 if(d.pipeline_character(2,6)!="/" || d.pipeline_character(3,7)!="3")$fatal(1,"fraction label mismatch");
 still_color=rgb;for(i=0;i<80;i=i+1)begin frames(1);if(rgb!==still_color)$fatal(1,"removed moving white stripe returned");end
 font_ready=1;frames(25);if(active || d.progress!=480)$fatal(1,"ready font did not finish boot");
 // Confirmed-absent resources settle as blank instead of deadlocking.
 rst=1;@(negedge clk);present=0;rst=0;frames(70);
 if(active)$fatal(1,"confirmed empty catalog deadlocked startup");
 for(i=0;i<8;i=i+1)if(d.pipeline_character(2,i)!=" " || d.pipeline_character(3,i)!=" " || d.pipeline_character(5,i)!=" ")$fatal(1,"absent resource label not blank");
 $display("PASS scan/font boot gate, 1/3-2/3-3/3 milestones, blank missing resources and stationary progress bar");$finish;
end
initial begin #1000000;$fatal(1,"boot test timeout");end
endmodule
