`timescale 1ns/1ps
module tb_boot;
reg clk=0;always #5 clk=~clk;
reg rst=1,pub=0,slot=0;reg [31:0] head=32'h07e0f800;reg empty=1;
wire pop,commit,frame,active,visible,underflow,de,vs;wire [23:0] rgb;
delta_video #(.SHOW_BOOT_SPINNER(1),.MIN_BOOT_FRAMES(96)) dut(clk,rst,pub,slot,head,empty,pop,rgb,de,vs,commit,frame,active,visible,underflow,1'b0);
integer i;reg [23:0] old;
task tick;
 begin @(negedge clk);dut.h=0;dut.v=0;@(negedge clk);dut.h=1;dut.v=0;end
endtask
task sample;
 input integer hh,vv;
 begin @(negedge clk);dut.h=hh;dut.v=vv;@(posedge clk);#1;end
endtask
initial begin
 repeat(5)@(negedge clk);rst=0;
 // A completely absent TF card: empty FIFO, no publish, still valid video.
 sample(900,345);if(rgb!==24'hffffff || !de || pop || visible)$fatal(1,"no-card spinner absent");
 for(i=0;i<6;i=i+1)tick;
 sample(900,345);if(rgb!==24'h404040)$fatal(1,"spinner phase did not move");
 sample(928,357);if(rgb!==24'hffffff)$fatal(1,"new spinner head missing");
 if(underflow)$fatal(1,"boot incorrectly consumes SDRAM FIFO");
 // A prepared first frame must wait for the startup spinner dwell.
 pub=1;repeat(6)@(negedge clk);
 for(i=0;i<85;i=i+1)tick;
 if(visible || commit)$fatal(1,"first frame bypasses spinner dwell");
 repeat(10)tick;
 if(!visible || !commit)$fatal(1,"prepared first frame never committed");
 empty=0;sample(660,145);if(rgb!==24'hff0000)$fatal(1,"first pixel from TF image mismatch");
 @(negedge clk);dut.h=661;dut.v=145;#1;if(!pop)$fatal(1,"second pixel did not consume the pair");
 @(posedge clk);#1;if(rgb!==24'h00ff00)$fatal(1,"second pixel mismatch");
 sample(400,145);if(rgb!==0)$fatal(1,"image black border mismatch");
 // Later commits proceed at a frame boundary without repeating the spinner.
 slot=1;pub=0;repeat(6)@(negedge clk);tick;
 if(!active || commit || !visible)$fatal(1,"animation buffer transition failed");
 $display("PASS boot: animated spinner without TF/FIFO, minimum dwell, prepared first-frame commit, exact RGB565 pixels/black border, seamless later commit");$finish;
end
initial begin #100000;$fatal(1,"boot test timeout");end
endmodule
