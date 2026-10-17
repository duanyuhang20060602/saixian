// Eleven live showcase effects. Keep source ownership until the final full frame.
module water_transition(
 input clk,rst,frame_tick,frame_ready_toggle,input[1:0] ready_buf_idx,input ready_slide_right,
 output reg[1:0] active_buf_idx,slide_new_buf_idx,output reg frame_commit_toggle,display_valid,
 output reg transition_active,output reg[3:0] transition_mode,output reg[10:0] slide_offset,
 output reg slide_right,output reg[8:0] water_progress,output reg[5:0] transition_level);
localparam FX_WATER=6,FX_SCROLL=0,FX_FLIP=1,FX_RIBBONS=2,FX_COLUMNS=3,FX_ACCORDION=4,FX_METAL=5,FX_PORTAL=7,FX_GLASS=8,FX_TUNNEL=9,FX_TEAR=10;
reg ready_sync0,ready_sync1,ready_seen,ready_right_sync0,ready_right_sync1;
reg[1:0] ready_buf_sync0,ready_buf_sync1;
reg[5:0] animation_step;reg[16:0] phase;
wire[16:0] next_phase=phase+17'd1873;
wire[8:0] next_progress=next_phase[16:8];
function[3:0] next_effect;input[3:0] previous_effect;
 begin case(previous_effect)
  FX_WATER:next_effect=FX_SCROLL;FX_SCROLL:next_effect=FX_FLIP;
  FX_FLIP:next_effect=FX_RIBBONS;FX_RIBBONS:next_effect=FX_COLUMNS;
  FX_COLUMNS:next_effect=FX_ACCORDION;FX_ACCORDION:next_effect=FX_METAL;
  FX_METAL:next_effect=FX_PORTAL;FX_PORTAL:next_effect=FX_GLASS;
  FX_GLASS:next_effect=FX_TUNNEL;FX_TUNNEL:next_effect=FX_TEAR;default:next_effect=FX_WATER;
 endcase end
endfunction
always @(posedge clk or posedge rst)begin
 if(rst)begin
  ready_sync0<=0;ready_sync1<=0;ready_seen<=0;ready_right_sync0<=0;ready_right_sync1<=0;
  ready_buf_sync0<=0;ready_buf_sync1<=0;active_buf_idx<=0;slide_new_buf_idx<=0;
  frame_commit_toggle<=0;display_valid<=0;transition_active<=0;transition_mode<=FX_TEAR;
  slide_offset<=0;slide_right<=0;water_progress<=0;transition_level<=0;animation_step<=0;phase<=0;
 end else begin
  ready_sync0<=frame_ready_toggle;ready_sync1<=ready_sync0;
  ready_buf_sync0<=ready_buf_idx;ready_buf_sync1<=ready_buf_sync0;
  ready_right_sync0<=ready_slide_right;ready_right_sync1<=ready_right_sync0;
  if(frame_tick)begin
   transition_level<=0;
   if(!transition_active&&ready_sync1!=ready_seen)begin
    ready_seen<=ready_sync1;slide_new_buf_idx<=ready_buf_sync1;
    if(!display_valid)begin
     active_buf_idx<=ready_buf_sync1;frame_commit_toggle<=~frame_commit_toggle;display_valid<=1;
    end else begin
     transition_active<=1;transition_mode<=next_effect(transition_mode);slide_right<=ready_right_sync1;
     animation_step<=0;phase<=0;water_progress<=0;slide_offset<=0;
    end
   end else if(transition_active)begin
    if(animation_step==35)begin
     active_buf_idx<=slide_new_buf_idx;frame_commit_toggle<=~frame_commit_toggle;
     transition_active<=0;water_progress<=0;slide_offset<=0;
    end else begin
     animation_step<=animation_step+1'b1;phase<=next_phase;water_progress<=next_progress;
     slide_offset<=({2'd0,next_progress}<<2)+next_progress;
    end
   end
  end
 end
end
endmodule
