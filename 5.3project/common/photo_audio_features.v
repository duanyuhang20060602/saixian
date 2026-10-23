`timescale 1ns/1ps
// B advances cue synthesis once for each PCM frame prepared for transmission.
// TF/SPI burst timing does not change the cue pitch or duration at A's 48 kHz.
module photo_audio_processing_b #(parameter PAGE_CUE=0,TYPED_PAGE=0,SHARED_SCALE=0)(
 input clk,rst,prepare,request_valid,input [7:0] request_epoch,
 input request_bg,request_repair,input [3:0] request_volume,request_cue,
 input [31:0] raw_pcm,output reg [31:0] processed_pcm,output reg bg_enabled,
 input [2:0] page_cue_count,input background_available,
 input page_valid,input [3:0] page_style,output page_ready
);
reg [7:0] seen_epoch;reg [3:0] volume,cue_pulse;reg [3:0] prepare_pipe;
wire [23:0] cue_left,cue_right;wire cue_active,cue_busy;
reg [7:0] page_pending;
wire incoming_page=PAGE_CUE && !TYPED_PAGE && page_cue_count!=0;
wire queued_page,queue_full;wire [3:0] queue_style;reg [3:0] cue_style;
wire typed_start;
assign page_ready=!queue_full;
photo_page_type_queue pending_pages(.clk(clk),.rst(rst),.push(TYPED_PAGE && page_valid),.style_in(page_style),
 .pop(typed_start),.valid(queued_page),.full(queue_full),.style_out(queue_style),.overflow());
wire epoch_clear=request_valid && request_epoch!=seen_epoch;
assign typed_start=TYPED_PAGE && queued_page && !cue_busy && cue_pulse==0 && !epoch_clear;
wire start_page=PAGE_CUE && !TYPED_PAGE && page_pending!=0 && !cue_busy && cue_pulse==0 && !epoch_clear;
wire [8:0] page_total={1'b0,page_pending}+(incoming_page ? {6'd0,page_cue_count}:9'd0)-(start_page ? 9'd1:9'd0);
wire use_background=bg_enabled && (!PAGE_CUE || background_available);
photo_audio_cue_samples #(.PAGE_STYLES(TYPED_PAGE)) cue(.page_style(cue_style),.clk(clk),.rst(rst),.cue_event(cue_pulse),.sample_tick(prepare_pipe[0]),
 .audio_valid(),.audio_left(cue_left),.audio_right(cue_right),.audio_level(),
 .cue_busy(cue_busy),.spectrum_active(cue_active),.spectrum_tone_bin());
function signed [15:0] scale;
 input signed [15:0] value;input [3:0] level;
 begin case(level)
 0:scale=0;1:scale=value>>>4;2:scale=value>>>3;3:scale=value>>>2;4:scale=value>>>1;
 5:scale=(value>>>1)+(value>>>3);6:scale=(value>>>1)+(value>>>2);
 7:scale=value-(value>>>3);default:scale=value;
 endcase end
endfunction
wire signed [15:0] bg_l=use_background ? $signed(raw_pcm[15:0]):16'sd0;
wire signed [15:0] bg_r=use_background ? $signed(raw_pcm[31:16]):16'sd0;
wire signed [15:0] tone_l=$signed(cue_left[23:8]),tone_r=$signed(cue_right[23:8]);
reg signed [15:0] mix_l_q,mix_r_q,raw_l_q,raw_r_q,tone_l_q,tone_r_q;
reg cue_active_q;
wire signed [15:0] repaired_l,repaired_r;wire repaired_valid;
wire signed [15:0] piped_mix_l=cue_active_q ? (use_background ? (repaired_l>>>1)+(tone_l_q>>>1):tone_l_q):repaired_l;
wire signed [15:0] piped_mix_r=cue_active_q ? (use_background ? (repaired_r>>>1)+(tone_r_q>>>1):tone_r_q):repaired_r;
// SPI preparation begins 15 bits before the next word (~400 B clocks).
// The original single-board repair takes ~301 clocks. Never clock it from SPI.
reg repair_enable;
saixian_audio_repair repair(.clk(clk),.rst(rst),.clear(epoch_clear),
 .sample_valid(prepare_pipe[2]),.enable(repair_enable),
 .left_in(raw_l_q),.right_in(raw_r_q),.left_out(repaired_l),.right_out(repaired_r),.out_valid(repaired_valid));
reg mix_valid;reg [1:0] scale_phase;reg [15:0] scaled_left;reg [3:0] scale_volume;
wire signed [15:0] scale_operand=scale_phase==1 ? mix_l_q:mix_r_q;
wire [15:0] scaled_value=scale(scale_operand,scale_phase==1 ? volume:scale_volume);
always @(posedge clk or posedge rst)begin
 if(rst)begin scale_phase<=0;scaled_left<=0;scale_volume<=0;cue_style<=0;page_pending<=0;repair_enable<=0;mix_valid<=0;seen_epoch<=0;volume<=5;bg_enabled<=1;cue_pulse<=0;prepare_pipe<=0;
  mix_l_q<=0;mix_r_q<=0;raw_l_q<=0;raw_r_q<=0;tone_l_q<=0;tone_r_q<=0;cue_active_q<=0;processed_pcm<=0;end
 else begin
  mix_valid<=repaired_valid;
  if(request_valid)repair_enable<=request_repair;
  cue_pulse<=0;prepare_pipe<={prepare_pipe[2:0],prepare};
  if(TYPED_PAGE && typed_start)begin cue_pulse<=6;cue_style<=queue_style;end
  if(PAGE_CUE && !TYPED_PAGE)begin
   page_pending<=page_total[8] ? 8'hff:page_total[7:0];
   if(start_page)cue_pulse<=4'd6;
  end
  if(request_valid && request_epoch!=seen_epoch)begin
   seen_epoch<=request_epoch;volume<=request_volume>8 ? 4'd8:request_volume;
   bg_enabled<=request_bg;cue_pulse<=request_cue;
  end
  if(prepare_pipe[1])begin raw_l_q<=bg_l;raw_r_q<=bg_r;tone_l_q<=tone_l;tone_r_q<=tone_r;cue_active_q<=cue_active;end
  if(repaired_valid)begin mix_l_q<=piped_mix_l;mix_r_q<=piped_mix_r;end
  if(!SHARED_SCALE && mix_valid)processed_pcm<={scale(mix_r_q,volume),scale(mix_l_q,volume)};
  if(SHARED_SCALE)begin
   if(repaired_valid)scale_phase<=1;
   else case(scale_phase)
    1:begin scale_volume<=volume;scaled_left<=scaled_value;scale_phase<=2;end
    2:begin processed_pcm<={scaled_value,scaled_left};scale_phase<=0;end
    default:;
   endcase
  end
 end
end
endmodule

// transition_mode is already resolved from the random/fixed menu choice.
// Sample the rising active edge after mode and target have been registered.
module photo_transition_page_event(input clk,rst,enable,display_valid,transition_active,
 input [2:0] image,count,input [4:0] transition_mode,
 output reg page_event,output reg [3:0] page_style);
reg was_active;
always @(posedge clk or posedge rst)begin
 if(rst)begin was_active<=0;page_event<=0;page_style<=0;end
 else begin
  was_active<=transition_active;page_event<=0;
  if(enable && display_valid && image<count && transition_active && !was_active)begin
   page_event<=1;page_style<=transition_mode<=10 ? transition_mode[3:0]:4'd0;
  end
 end
end
endmodule

module photo_key_hold #(parameter CLK_HZ=75000000)(
 input clk,rst,key_n,output reg short_release,long_press
);
reg event_key_meta,key_sync,key_stable;reg [20:0] debounce;reg [26:0] hold_count;
reg fired;
always @(posedge clk or posedge rst)begin
 if(rst)begin event_key_meta<=1;key_sync<=1;key_stable<=1;debounce<=0;
  hold_count<=0;fired<=0;short_release<=0;long_press<=0;end
 else begin
  event_key_meta<=key_n;key_sync<=event_key_meta;short_release<=0;long_press<=0;
  if(key_sync==key_stable)debounce<=0;
  else if(debounce==CLK_HZ/50-1)begin
   debounce<=0;key_stable<=key_sync;
   if(key_sync && !fired && hold_count<CLK_HZ-1)short_release<=1;
  end else debounce<=debounce+1'b1;
  if(key_stable)begin hold_count<=0;fired<=0;end
  else if(!fired)begin
   if(hold_count==CLK_HZ-1)begin long_press<=1;fired<=1;end
   else hold_count<=hold_count+1'b1;
  end
 end
end
endmodule

// Actual committed photo changes, including cached and automatic navigation.
// Initial display, metadata refresh and the special award slot are silent.
module photo_page_change_event(input clk,rst,display_valid,
 input [2:0] image,count,output reg page_event);
reg have_photo;reg [2:0] last_image;
always @(posedge clk or posedge rst)begin
 if(rst)begin have_photo<=0;last_image<=0;page_event<=0;end
 else begin
  page_event<=0;
  if(count==0)have_photo<=0;
  else if(display_valid && image<count)begin
   page_event<=have_photo && image!=last_image;
   last_image<=image;have_photo<=1;
  end
 end
end
endmodule
