// Deterministic FFT/wave endpoints for the SPI integration test only.
// The separate metadata test uses the real FFT/wave RTL and native RAM model.
module saixian_av_fft #(parameter SMALL_RAM=0)(input clk,rst,frame_tick,sample_valid,
 input signed [15:0] left,right,input [4:0] read_band,output [6:0] read_height,read_peak,output valid,block_done);
assign read_height={2'd0,read_band};assign read_peak={2'd0,read_band}+7'd7;
assign valid=!rst;assign block_done=0;
endmodule
module saixian_av_wave #(parameter SMALL_RAM=0)(input clk,rst,frame_tick,sample_valid,
 input signed [15:0] left,right,input [7:0] read_index,output [31:0] read_extrema,output valid);
assign read_extrema={read_index,~read_index,read_index,~read_index};assign valid=!rst;
endmodule
