// Align PCM data and its strobe after the player's registered output.
// Diagnostics preserve the same HDMI/ACR clocking as normal music playback.
module water_audio_output(input clk,rst,sample_tick,cycle_mode,
 input[23:0] source_left,source_right,output reg pcm_valid,
 output reg[23:0] pcm_left,pcm_right,output reg[1:0] mode);
reg tick_q;reg[5:0] phase;reg signed[15:0] sine[0:47];
initial $readmemh("water_tone.hex",sine);
always @(posedge clk)begin
 if(rst)begin tick_q<=0;pcm_valid<=0;pcm_left<=0;pcm_right<=0;mode<=0;phase<=0;end
 else begin
  tick_q<=sample_tick;pcm_valid<=tick_q;
  if(cycle_mode)begin mode<=mode==2 ? 0:mode+1'b1;phase<=0;end
  if(tick_q)begin
   phase<=phase==47 ? 0:phase+1'b1;
   case(mode)
    1:begin pcm_left<=0;pcm_right<=0;end
    2:begin pcm_left<={sine[phase],8'd0};pcm_right<={sine[phase],8'd0};end
    default:begin pcm_left<=source_left;pcm_right<=source_right;end
   endcase
  end
 end
end
endmodule
