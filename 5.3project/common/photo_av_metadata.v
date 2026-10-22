`timescale 1ns/1ps
// B analyzes the exact post-mix words loaded into the audio transport.
// Publish only at a metadata request boundary; banks stay stable throughout
// the request. Sequence tags refer to the last transmitted PCM at that boundary.
module photo_av_metadata_b #(parameter EDGE_METADATA=0)(
 input clk,rst,pcm_sent,snapshot,input [31:0] pcm,
 input [8:0] address,output reg [31:0] data
);
reg [31:0] sent_position,snapshot_position;
// Analyze each transmitted post-mix sample once on B. A publishes this
// envelope with the same playback-position eligibility as the FFT/wave data.
reg [18:0] edge_envelope;
reg [7:0] snapshot_edge;
wire signed [16:0] edge_sum=$signed({pcm[15],pcm[15:0]})+$signed({pcm[31],pcm[31:16]});
wire signed [16:0] edge_mono=edge_sum>>>1;
wire [16:0] edge_magnitude=edge_mono<0 ? -edge_mono:edge_mono;
wire [7:0] edge_target=edge_envelope>8191 ? 8'd255:edge_envelope[12:5];
always @(posedge clk or posedge rst)
 if(rst)begin edge_envelope<=0;snapshot_edge<=0;end
 else begin
  if(EDGE_METADATA && pcm_sent)begin
   if(edge_magnitude>edge_envelope)edge_envelope<=edge_envelope+((edge_magnitude-edge_envelope)>>6);
   else edge_envelope<=edge_envelope-((edge_envelope-edge_magnitude)>>10);
  end
  if(snapshot)snapshot_edge<=edge_target;
 end
wire [6:0] height,peak;wire [31:0] extrema;wire fft_valid,wave_valid;
always @(posedge clk or posedge rst)
 if(rst)begin sent_position<=0;snapshot_position<=0;end
 else begin
  if(pcm_sent)sent_position<=sent_position+1'b1;
  if(snapshot)snapshot_position<=sent_position;
 end
wire [8:0] wave_address=address-9'd34;
saixian_av_fft #(.SMALL_RAM(1)) fft(.clk(clk),.rst(rst),.frame_tick(snapshot),
 .sample_valid(pcm_sent),.left(pcm[15:0]),.right(pcm[31:16]),
 .read_band(address[4:0]-5'd2),.read_height(height),.read_peak(peak),.valid(fft_valid),.block_done());
saixian_av_wave #(.SMALL_RAM(1)) wave(.clk(clk),.rst(rst),.frame_tick(snapshot),
 .sample_valid(pcm_sent),.left(pcm[15:0]),.right(pcm[31:16]),
 .read_index(wave_address[7:0]),.read_extrema(extrema),.valid(wave_valid));
// address is held for most of a 32-bit SPI word before the transport latch.
always @* begin
 if(address==0)data=EDGE_METADATA ? {16'h4132,snapshot_edge,6'd0,wave_valid,fft_valid}:
                                  {24'h415631,6'd0,wave_valid,fft_valid};
 else if(address==1)data=snapshot_position;
 else if(address<34)data={18'd0,peak,height};
 else data=extrema;
end
endmodule

