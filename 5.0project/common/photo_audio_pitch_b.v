`timescale 1ns/1ps
// B owns repair -> pitch -> a bounded PCM queue. SPI only consumes completed
// frames, so the effect's variable background search cannot miss a word edge.
// Cue mixing and output volume remain at the consumer, after the effect.
module photo_audio_pitch_b #(
 parameter COMPACT_DRY=1
)(
 input clk,rst,stream_clear,enable,repair_enable,
 input [2:0] requested_mode,
 input [13:0] raw_used,input [31:0] raw_pcm,output raw_read,
 input output_read,output [31:0] output_pcm,output [13:0] output_used,
 output ready,overrun,output [2:0] active_mode
);
wire clear=rst || stream_clear;
localparam IDLE=0,READ_WAIT=1,SUBMIT=2,WAIT_RESULT=3;
reg [1:0] state;
wire [8:0] queued;
wire queue_empty,queue_full;
assign raw_read=!clear && enable && state==IDLE && raw_used!=0 && !queue_full;
wire repaired_valid,pitch_valid;
wire signed [15:0] repaired_l,repaired_r,pitched_l,pitched_r;
saixian_audio_repair repair(.clk(clk),.rst(rst),.clear(stream_clear),
 .sample_valid(state==SUBMIT && !clear),.enable(repair_enable),
 .left_in(raw_pcm[15:0]),.right_in(raw_pcm[31:16]),
 .left_out(repaired_l),.right_out(repaired_r),.out_valid(repaired_valid));
saixian_audio_pitch #(.COMPACT_DRY(COMPACT_DRY)) pitch(
 .clk(clk),.rst(rst),.clear(stream_clear),.sample_valid(repaired_valid && !clear),
 .left_in(repaired_l),.right_in(repaired_r),.requested_mode(requested_mode),
 .left_out(pitched_l),.right_out(pitched_r),.out_valid(pitch_valid),
 .ready(ready),.overrun(overrun),.active_mode(active_mode));
photo_audio_fifo #(.DEPTH(256),.AW(8)) completed(
 .clk(clk),.rst(clear),.write_en(pitch_valid && state==WAIT_RESULT && !clear),
 .write_data({pitched_r,pitched_l}),.read_en(output_read && !clear),
 .data(output_pcm),.empty(queue_empty),.full(queue_full),.used(queued));
assign output_used={5'd0,queued};
always @(posedge clk or posedge rst)begin
 if(rst)state<=IDLE;
 else if(stream_clear)state<=IDLE;
 else case(state)
  IDLE:if(raw_read)state<=READ_WAIT;
  READ_WAIT:state<=SUBMIT;
  SUBMIT:state<=WAIT_RESULT;
  WAIT_RESULT:if(pitch_valid)state<=IDLE;
 endcase
end
endmodule

// B KEY2 short release: F0 -> F1 -> F2 -> F3 -> F4 -> F0.
// Hold for one second: F0. This does not change A's existing keys or wiring.
module photo_pitch_keys #(parameter CLK_HZ=100000000)(
 input clk,rst,key2_n,output reg [2:0] mode
);
wire short_release,long_press;
photo_key_hold #(.CLK_HZ(CLK_HZ)) key_control(
 .clk(clk),.rst(rst),.key_n(key2_n),.short_release(short_release),.long_press(long_press));
always @(posedge clk or posedge rst)begin
 if(rst)mode<=0;
 else if(long_press)mode<=0;
 else if(short_release)mode<=mode==4 ? 3'd0:mode+1'b1;
end
endmodule
