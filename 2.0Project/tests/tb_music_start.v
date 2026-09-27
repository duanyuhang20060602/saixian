`timescale 1ns/1ps
module tb_music_start;
reg clk=0;always #5 clk=~clk;
reg rst=1,valid=0,de=0,busy=0,carousel=1,resume_ready=0;
reg [3:0] event_state=0;
top dut();
task step;begin @(negedge clk);end endtask
initial begin
 force dut.video_clk=clk;force dut.rst_video=rst;
 force dut.display_valid=valid;force dut.battle_de=de;force dut.battle_busy=busy;
 force dut.carousel_mode=carousel;force dut.event_state=event_state;
 force dut.bgm_resume_ready=resume_ready;
 repeat(3)step;rst=0;
 repeat(20)step;if(dut.bgm_play_enable) $fatal(1,"music before picture commitment");
 valid=1;repeat(5)step;if(dut.bgm_play_enable) $fatal(1,"music during first-frame blanking");
 de=1;step;de=0;step;if(!dut.bgm_play_enable) $fatal(1,"music failed to start with first visible picture");
 repeat(5)step;if(!dut.bgm_play_enable) $fatal(1,"music paused in picture blanking");
 busy=1;step;if(dut.bgm_play_enable) $fatal(1,"result did not pause music");
 busy=0;carousel=0;event_state=4'd8;step;
 if(dut.bgm_play_enable) $fatal(1,"finish wait ignored");
 resume_ready=1;step;if(!dut.bgm_play_enable) $fatal(1,"finish resume missing");
 rst=1;step;if(dut.bgm_play_enable) $fatal(1,"restart latch not reset");
 $display("PASS music waits for first displayed picture; blanking, result pause, finish resume, reset");$finish;
end
endmodule
