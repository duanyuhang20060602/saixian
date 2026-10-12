module saixian_transition(
    input  wire       clk,
    input  wire       rst,
    input  wire       frame_tick,
    input  wire       frame_ready_toggle,
    input  wire [1:0] ready_buf_idx,
    input  wire       ready_slide_right,
    output reg  [1:0] active_buf_idx,
    output reg  [1:0] slide_new_buf_idx,
    output reg        frame_commit_toggle,
    output reg        display_valid,
    output reg        transition_active,
    output reg  [2:0] transition_mode,
    output reg [10:0] slide_offset,
    output reg        slide_right,
    output reg  [5:0] transition_level
);

localparam FX_SLIDE    = 3'd0;
localparam FX_CENTER   = 3'd1;
localparam FX_BLINDS   = 3'd2;
localparam FX_DIAGONAL = 3'd3;
localparam FX_DISSOLVE = 3'd4;
localparam FX_FADE     = 3'd5;

reg       ready_sync0;
reg       ready_sync1;
reg       ready_seen;
reg [1:0] ready_buf_sync0;
reg [1:0] ready_buf_sync1;
reg       ready_right_sync0;
reg       ready_right_sync1;
reg [4:0] slide_step;
reg       end_hold;
reg [7:0] effect_lfsr;

function [10:0] ease_offset;
    input [4:0] step;
    begin
        case (step)
            5'd0:  ease_offset = 11'd0;
            5'd1:  ease_offset = 11'd14;
            5'd2:  ease_offset = 11'd54;
            5'd3:  ease_offset = 11'd118;
            5'd4:  ease_offset = 11'd200;
            5'd5:  ease_offset = 11'd300;
            5'd6:  ease_offset = 11'd414;
            5'd7:  ease_offset = 11'd534;
            5'd8:  ease_offset = 11'd640;
            5'd9:  ease_offset = 11'd746;
            5'd10: ease_offset = 11'd866;
            5'd11: ease_offset = 11'd980;
            5'd12: ease_offset = 11'd1080;
            5'd13: ease_offset = 11'd1162;
            5'd14: ease_offset = 11'd1226;
            5'd15: ease_offset = 11'd1266;
            default: ease_offset = 11'd1280;
        endcase
    end
endfunction

function [5:0] fade_darkness;
    input [4:0] step;
    begin
        if (step <= 5'd8)
            fade_darkness = {step,2'b00};
        else if (step < 5'd16)
            fade_darkness = {(5'd16-step),2'b00};
        else
            fade_darkness = 6'd0;
    end
endfunction

function [2:0] choose_effect;
    input [7:0] random_value;
    input [2:0] previous_effect;
    reg [2:0] candidate;
    begin
        case (random_value[2:0])
            3'd6: candidate = FX_CENTER;
            3'd7: candidate = FX_DISSOLVE;
            default: candidate = random_value[2:0];
        endcase
        if (candidate == previous_effect)
            choose_effect = (candidate == FX_FADE) ? FX_SLIDE : candidate + 3'd1;
        else
            choose_effect = candidate;
    end
endfunction

always @(posedge clk or posedge rst) begin
    if (rst) begin
        ready_sync0         <= 1'b0;
        ready_sync1         <= 1'b0;
        ready_seen          <= 1'b0;
        ready_buf_sync0     <= 2'd0;
        ready_buf_sync1     <= 2'd0;
        ready_right_sync0   <= 1'b0;
        ready_right_sync1   <= 1'b0;
        active_buf_idx      <= 2'd0;
        slide_new_buf_idx   <= 2'd0;
        frame_commit_toggle <= 1'b0;
        display_valid       <= 1'b0;
        transition_active   <= 1'b0;
        transition_mode     <= FX_SLIDE;
        slide_offset        <= 11'd0;
        slide_right         <= 1'b0;
        slide_step          <= 5'd0;
        end_hold            <= 1'b0;
        transition_level    <= 6'd0;
        effect_lfsr         <= 8'hA7;
    end else begin
        ready_sync0       <= frame_ready_toggle;
        ready_sync1       <= ready_sync0;
        ready_buf_sync0   <= ready_buf_idx;
        ready_buf_sync1   <= ready_buf_sync0;
        ready_right_sync0 <= ready_slide_right;
        ready_right_sync1 <= ready_right_sync0;

        if (frame_tick) begin
            effect_lfsr <= {effect_lfsr[6:0],
                            effect_lfsr[7] ^ effect_lfsr[5] ^ effect_lfsr[4] ^ effect_lfsr[3]};

            if (!transition_active && (ready_sync1 != ready_seen)) begin
                ready_seen        <= ready_sync1;
                slide_new_buf_idx <= ready_buf_sync1;

                if (!display_valid) begin
                    active_buf_idx      <= ready_buf_sync1;
                    frame_commit_toggle <= ~frame_commit_toggle;
                    display_valid       <= 1'b1;
                    slide_offset        <= 11'd0;
                    transition_level    <= 6'd0;
                end else begin
                    transition_active <= 1'b1;
                    transition_mode   <= choose_effect(effect_lfsr, transition_mode);
                    slide_right       <= ready_right_sync1;
                    slide_step        <= 5'd0;
                    slide_offset      <= 11'd0;
                    transition_level  <= 6'd0;
                    end_hold          <= 1'b0;
                end
            end else if (transition_active) begin
                if (end_hold) begin
                    active_buf_idx      <= slide_new_buf_idx;
                    frame_commit_toggle <= ~frame_commit_toggle;
                    transition_active   <= 1'b0;
                    slide_offset        <= 11'd0;
                    slide_step          <= 5'd0;
                    transition_level    <= 6'd0;
                    end_hold            <= 1'b0;
                end else if (slide_step >= 5'd15) begin
                    slide_step       <= 5'd16;
                    slide_offset     <= 11'd1280;
                    transition_level <= 6'd0;
                    end_hold         <= 1'b1;
                end else begin
                    slide_step       <= slide_step + 1'b1;
                    slide_offset     <= ease_offset(slide_step + 1'b1);
                    transition_level <= (transition_mode == FX_FADE) ?
                                        fade_darkness(slide_step + 1'b1) : 6'd0;
                end
            end else begin
                transition_level <= 6'd0;
            end
        end
    end
end

endmodule