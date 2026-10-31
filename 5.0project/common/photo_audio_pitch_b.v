`timescale 1ns/1ps
// B owns repair -> pitch -> a bounded PCM queue. SPI only consumes completed
// frames, so the effect's variable background search cannot miss a word edge.
// Cue mixing and output volume remain at the consumer, after the effect.
module photo_audio_pitch_b #(
 parameter COMPACT_DRY=1,SLOW_COMPUTE=0
)(
 input clk,rst,stream_clear,enable,repair_enable,
 input [2:0] requested_mode,
 input [13:0] raw_used,input [31:0] raw_pcm,output raw_read,
 input output_read,output [31:0] output_pcm,output [13:0] output_used,
 output ready,overrun,output [2:0] active_mode,input compute_clk
);
wire clear=rst || stream_clear;
localparam IDLE=0,READ_WAIT=1,SUBMIT=2,WAIT_RESULT=3;
reg [1:0] state;
wire [8:0] queued;
wire queue_empty,queue_full;
// This engine is the only reader of the raw FIFO. It cannot issue another
// read until the current sample has completed its multi-cycle processing.
// A registered availability flag therefore adds one startup clock without
// risking a second read after the last word, and cuts the FIFO count loop.
reg raw_available;
always @(posedge clk or posedge rst)
 if(rst)raw_available<=0;
 else if(stream_clear)raw_available<=0;
 else raw_available<=raw_used!=0;
assign raw_read=!clear && enable && state==IDLE && raw_available && !queue_full;
wire repaired_valid,pitch_valid,core_valid,core_ready,core_overrun;
wire[2:0] core_mode,compute_mode;wire compute_enable,compute_valid;
wire[31:0] compute_pcm,core_pcm,finished_pcm;
wire engine_clk=SLOW_COMPUTE ? compute_clk:clk;
wire engine_rst,engine_clear;
wire signed [15:0] repaired_l,repaired_r;
generate if(SLOW_COMPUTE)begin:slow_compute
 (* async_reg="true" *)reg[2:0] reset_pipe;
 always @(posedge compute_clk or posedge clear)
  if(clear)reset_pipe<=3'b111;else reset_pipe<={reset_pipe[1:0],1'b0};
 assign engine_rst=reset_pipe[2];assign engine_clear=1'b0;
 wire input_ready;
 wire[35:0] input_bundle;
 photo_font_mailbox #(.W(36)) input_sample(
  .source_clk(clk),.source_rst(clear),.source_valid(state==SUBMIT && !clear),
  .source_data({requested_mode,repair_enable,raw_pcm}),.source_ready(input_ready),
  .destination_clk(compute_clk),.destination_rst(engine_rst),.destination_valid(compute_valid),
  .destination_data(input_bundle),.destination_ready(1'b1));
 assign {compute_mode,compute_enable,compute_pcm}=input_bundle;
 wire result_ready;
 photo_font_mailbox #(.W(32)) output_sample(
  .source_clk(compute_clk),.source_rst(engine_rst),.source_valid(core_valid),.source_data(core_pcm),.source_ready(result_ready),
  .destination_clk(clk),.destination_rst(clear),.destination_valid(pitch_valid),.destination_data(finished_pcm),.destination_ready(1'b1));
 reg input_overflow,result_overflow;
 always @(posedge clk or posedge clear)
  if(clear)input_overflow<=0;else if(state==SUBMIT && !input_ready)input_overflow<=1;
 always @(posedge compute_clk or posedge engine_rst)
  if(engine_rst)result_overflow<=0;else if(core_valid && !result_ready)result_overflow<=1;
 (* async_reg="true" *)reg ready_meta,ready_sync,error_meta,error_sync;
 (* async_reg="true" *)reg[2:0] mode_meta,mode_sync;
 always @(posedge clk or posedge clear)
  if(clear)begin ready_meta<=0;ready_sync<=0;error_meta<=0;error_sync<=0;mode_meta<=0;mode_sync<=0;end
  else begin ready_meta<=core_ready;ready_sync<=ready_meta;error_meta<=core_overrun || result_overflow;
   error_sync<=error_meta;mode_meta<=core_mode;mode_sync<=mode_meta;end
 assign ready=ready_sync;assign overrun=error_sync || input_overflow;assign active_mode=mode_sync;
end else begin:fast_compute
 assign engine_rst=rst;assign engine_clear=stream_clear;
 assign compute_valid=state==SUBMIT && !clear;assign compute_mode=requested_mode;
 assign compute_enable=repair_enable;assign compute_pcm=raw_pcm;
 assign pitch_valid=core_valid;assign finished_pcm=core_pcm;
 assign ready=core_ready;assign overrun=core_overrun;assign active_mode=core_mode;
end endgenerate
saixian_audio_repair repair(.clk(engine_clk),.rst(engine_rst),.clear(engine_clear),
 .sample_valid(compute_valid && !engine_rst),.enable(compute_enable),
 .left_in(compute_pcm[15:0]),.right_in(compute_pcm[31:16]),
 .left_out(repaired_l),.right_out(repaired_r),.out_valid(repaired_valid));
saixian_audio_pitch #(.COMPACT_DRY(COMPACT_DRY)) pitch(
 .clk(engine_clk),.rst(engine_rst),.clear(engine_clear),.sample_valid(repaired_valid && !engine_rst && !engine_clear),
 .left_in(repaired_l),.right_in(repaired_r),.requested_mode(compute_mode),
 .left_out(core_pcm[15:0]),.right_out(core_pcm[31:16]),.out_valid(core_valid),
 .ready(core_ready),.overrun(core_overrun),.active_mode(core_mode));
photo_audio_fifo #(.DEPTH(256),.AW(8)) completed(
 .clk(clk),.rst(clear),.write_en(pitch_valid && state==WAIT_RESULT && !clear),
 .write_data(finished_pcm),.read_en(output_read && !clear),
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
