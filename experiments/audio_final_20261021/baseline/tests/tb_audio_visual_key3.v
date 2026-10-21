`timescale 1ns/1ps
module tb_audio_visual_key3;
reg clk=0,rst=1,key_n=1,eligible=1,frame_tick=0;
wire short_pulse,mode;
integer shorts=0;
always #5 clk=~clk;
saixian_av_key3 #(.CLK_HZ(1000),.DEBOUNCE_MS(4)) dut(.*);
always @(posedge clk) if(short_pulse) shorts=shorts+1;
task frame;begin frame_tick=1;@(negedge clk);frame_tick=0;@(negedge clk);end endtask
initial begin
    repeat(3) @(negedge clk);rst=0;
    key_n=0;repeat(2) @(negedge clk);key_n=1;repeat(12) @(negedge clk);
    if(shorts!=0) $fatal(1,"bounce generated short");
    key_n=0;repeat(40) @(negedge clk);key_n=1;repeat(12) @(negedge clk);
    if(shorts!=1 || mode) $fatal(1,"short release classification");
    key_n=0;repeat(1100) @(negedge clk);
    if(mode || shorts!=1) $fatal(1,"long changed outside frame/entered settings");
    frame; if(!mode) $fatal(1,"no frame-atomic long toggle");
    repeat(1200) @(negedge clk);frame;if(!mode) $fatal(1,"held key toggles twice");
    key_n=1;repeat(12) @(negedge clk);if(shorts!=1) $fatal(1,"long leaked short");
    key_n=0;repeat(300) @(negedge clk);eligible=0;repeat(50) @(negedge clk);
    eligible=1;repeat(1100) @(negedge clk);frame;key_n=1;repeat(12) @(negedge clk);
    if(shorts!=1 || !mode) $fatal(1,"cancelled gesture leaked");
    eligible=0;key_n=0;repeat(1100) @(negedge clk);frame;
    key_n=1;repeat(12) @(negedge clk);if(!mode || shorts!=1) $fatal(1,"ineligible gesture");
    eligible=1;key_n=0;repeat(1100) @(negedge clk);frame;
    if(mode) $fatal(1,"second gesture did not toggle");
    $display("PASS KEY3 debounce, short release, 1s long, single toggle, frame publication and context cancellation");$finish;
end
endmodule
