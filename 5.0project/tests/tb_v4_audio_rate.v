`timescale 1ns/1ps
module v4_audio_rate_case #(parameter HZ=75000000)(input clk,rst,output reg [31:0] checks=0);
wire valid;
reg [3:0] volume=5;
reg [31:0] reference_phase=0;
reg expected=0;
photo_audio_spi_a #(.CLK_HZ(HZ),.FIFO_AW(10)) dut(
 .clk(clk),.rst(rst),.next_track(1'b0),.bg_enable(1'b1),.repair_enable(1'b0),
 .playback_hold(1'b0),.volume(volume),.cue_event(4'd0),.spi_miso(1'b0),.sample_valid(valid),.av_available(1'b0));
always @(posedge clk)begin
 if(rst)begin reference_phase=0;checks=0;expected=0;end
 else begin
  expected=reference_phase>=HZ-48000;
  reference_phase=expected ? reference_phase-(HZ-48000):reference_phase+48000;
  checks=checks+1;
 end
 #1;
 if(valid!==expected)$fatal(1,"48kHz sample edge changed HZ=%0d cycle=%0d",HZ,checks);
 if(dut.sample_phase*dut.RATE_GCD!==reference_phase)$fatal(1,"phase changed HZ=%0d",HZ);
end
// Control changes flush packets, but must not reset the audio master phase.
always @(negedge clk)if(!rst && checks%19001==0)volume<=volume==5 ? 4:5;
endmodule
module tb_v4_audio_rate;
reg clk=0,rst=1;always #5 clk=~clk;
wire [31:0] a,b,c,d;
v4_audio_rate_case #(.HZ(75000000)) ca(clk,rst,a);
v4_audio_rate_case #(.HZ(50000000)) cb(clk,rst,b);
v4_audio_rate_case #(.HZ(48000000)) cc(clk,rst,c);
v4_audio_rate_case #(.HZ(50000003)) cd(clk,rst,d);
initial begin
 repeat(4)@(negedge clk);rst=0;repeat(200000)@(negedge clk);
 $display("PASS 800000 exact 48kHz phase/sample cycles, production clocks and coprime clock, control flushes");$finish;
end
endmodule
