module saixian_transition #(parameter ALLOW_IMMEDIATE=0)(
    input wire fluid_enable,
    input  wire       clk,
    input  wire       rst,
    input  wire       frame_tick,
    input  wire       frame_ready_toggle,
    input  wire [1:0] ready_buf_idx,
    input  wire       ready_slide_right,
    input wire ready_immediate,
    input  wire [4:0] effect_select, // 0=random, 1..6=legacy effects, 7=water, 8=metal, 9=curl, 10=columns, 11=card, 12=accordion, 13=ribbons
    output reg  [1:0] active_buf_idx,
    output reg  [1:0] slide_new_buf_idx,
    output reg        frame_commit_toggle,
    output reg        display_valid,
    output reg        transition_active,
    output reg  [4:0] transition_mode,
    output reg [10:0] slide_offset,
    output reg [8:0] fluid_progress,
    output reg        slide_right,
    output reg  [5:0] transition_level
);

localparam FX_SLIDE    = 3'd0;
localparam FX_CENTER   = 3'd1;
localparam FX_BLINDS   = 3'd2;
localparam FX_DIAGONAL = 3'd3;
localparam FX_DISSOLVE = 3'd4;
localparam FX_FADE     = 3'd5;
localparam FX_WATER    = 3'd6;

reg       ready_sync0;
reg       ready_sync1;
reg       ready_seen;
reg [1:0] ready_buf_sync0;
reg [1:0] ready_buf_sync1;
reg       ready_right_sync0;
reg       ready_right_sync1;
reg [5:0] slide_step;
reg       end_hold;
reg [7:0] effect_lfsr;

// 48 frame-paced increments. Tables are logic, not animation/frame RAM.
function [10:0] ease_offset;
    input [5:0] step;
    begin case(step)
        6'd0:ease_offset=11'd0;
        6'd1:ease_offset=11'd2;
        6'd2:ease_offset=11'd6;
        6'd3:ease_offset=11'd14;
        6'd4:ease_offset=11'd25;
        6'd5:ease_offset=11'd39;
        6'd6:ease_offset=11'd55;
        6'd7:ease_offset=11'd74;
        6'd8:ease_offset=11'd95;
        6'd9:ease_offset=11'd118;
        6'd10:ease_offset=11'd144;
        6'd11:ease_offset=11'd171;
        6'd12:ease_offset=11'd200;
        6'd13:ease_offset=11'd231;
        6'd14:ease_offset=11'd263;
        6'd15:ease_offset=11'd297;
        6'd16:ease_offset=11'd332;
        6'd17:ease_offset=11'd368;
        6'd18:ease_offset=11'd405;
        6'd19:ease_offset=11'd443;
        6'd20:ease_offset=11'd481;
        6'd21:ease_offset=11'd521;
        6'd22:ease_offset=11'd560;
        6'd23:ease_offset=11'd600;
        6'd24:ease_offset=11'd640;
        6'd25:ease_offset=11'd680;
        6'd26:ease_offset=11'd720;
        6'd27:ease_offset=11'd759;
        6'd28:ease_offset=11'd799;
        6'd29:ease_offset=11'd837;
        6'd30:ease_offset=11'd875;
        6'd31:ease_offset=11'd912;
        6'd32:ease_offset=11'd948;
        6'd33:ease_offset=11'd983;
        6'd34:ease_offset=11'd1017;
        6'd35:ease_offset=11'd1049;
        6'd36:ease_offset=11'd1080;
        6'd37:ease_offset=11'd1109;
        6'd38:ease_offset=11'd1136;
        6'd39:ease_offset=11'd1162;
        6'd40:ease_offset=11'd1185;
        6'd41:ease_offset=11'd1206;
        6'd42:ease_offset=11'd1225;
        6'd43:ease_offset=11'd1241;
        6'd44:ease_offset=11'd1255;
        6'd45:ease_offset=11'd1266;
        6'd46:ease_offset=11'd1274;
        6'd47:ease_offset=11'd1278;
        6'd48:ease_offset=11'd1280;
        default:ease_offset=11'd1280;
    endcase end
endfunction

// Fluid geometry already shapes its own front/columns; keep its phase linear.
function [8:0] phase_at_step;
    input [5:0] step;
    begin case(step)
        6'd0:phase_at_step=9'd0;
        6'd1:phase_at_step=9'd5;
        6'd2:phase_at_step=9'd11;
        6'd3:phase_at_step=9'd16;
        6'd4:phase_at_step=9'd21;
        6'd5:phase_at_step=9'd27;
        6'd6:phase_at_step=9'd32;
        6'd7:phase_at_step=9'd37;
        6'd8:phase_at_step=9'd43;
        6'd9:phase_at_step=9'd48;
        6'd10:phase_at_step=9'd53;
        6'd11:phase_at_step=9'd59;
        6'd12:phase_at_step=9'd64;
        6'd13:phase_at_step=9'd69;
        6'd14:phase_at_step=9'd75;
        6'd15:phase_at_step=9'd80;
        6'd16:phase_at_step=9'd85;
        6'd17:phase_at_step=9'd91;
        6'd18:phase_at_step=9'd96;
        6'd19:phase_at_step=9'd101;
        6'd20:phase_at_step=9'd107;
        6'd21:phase_at_step=9'd112;
        6'd22:phase_at_step=9'd117;
        6'd23:phase_at_step=9'd123;
        6'd24:phase_at_step=9'd128;
        6'd25:phase_at_step=9'd133;
        6'd26:phase_at_step=9'd139;
        6'd27:phase_at_step=9'd144;
        6'd28:phase_at_step=9'd149;
        6'd29:phase_at_step=9'd155;
        6'd30:phase_at_step=9'd160;
        6'd31:phase_at_step=9'd165;
        6'd32:phase_at_step=9'd171;
        6'd33:phase_at_step=9'd176;
        6'd34:phase_at_step=9'd181;
        6'd35:phase_at_step=9'd187;
        6'd36:phase_at_step=9'd192;
        6'd37:phase_at_step=9'd197;
        6'd38:phase_at_step=9'd203;
        6'd39:phase_at_step=9'd208;
        6'd40:phase_at_step=9'd213;
        6'd41:phase_at_step=9'd219;
        6'd42:phase_at_step=9'd224;
        6'd43:phase_at_step=9'd229;
        6'd44:phase_at_step=9'd235;
        6'd45:phase_at_step=9'd240;
        6'd46:phase_at_step=9'd245;
        6'd47:phase_at_step=9'd251;
        6'd48:phase_at_step=9'd256;
        default:phase_at_step=9'd256;
    endcase end
endfunction

function [5:0] fade_darkness;
    input [5:0] step;
    begin
        // Address ownership changes at the midpoint. Hide that change in black.
        if(step>=21 && step<=27)fade_darkness=6'd63;
        else if(step<21)fade_darkness=step*3;
        else if(step<48)fade_darkness=(6'd48-step)*3;
        else fade_darkness=0;
    end
endfunction

function [4:0] choose_effect;
    input [7:0] random_value;
    input [4:0] previous_effect;
    input water_allowed;
    reg [4:0] candidate;
    begin
        case (random_value[3:0])
            6,7,8,9,10,11,12:candidate=water_allowed ? {1'b0,random_value[3:0]}:FX_CENTER;
            13:candidate=FX_DISSOLVE;
            14:candidate=FX_BLINDS;
            15:candidate=FX_DIAGONAL;
            default:candidate={1'b0,random_value[3:0]};
        endcase
        if (candidate == previous_effect)
            choose_effect = (candidate == (water_allowed ? 5'd12:FX_FADE)) ? FX_SLIDE : candidate + 3'd1;
        else
            choose_effect = candidate;
    end
endfunction

function [4:0] selected_effect;
    input [4:0] selection;
    input [7:0] random_value;
    input [4:0] previous_effect;
    input water_allowed;
    begin
        case (selection)
            3'd1,3'd2,3'd3,3'd4,3'd5,3'd6: selected_effect=selection-3'd1;
            7,8,9,10,11,12,13:selected_effect=water_allowed ? selection-1'b1:FX_SLIDE;
            default: selected_effect=choose_effect(random_value,previous_effect,water_allowed);
        endcase
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
        fluid_progress      <= 9'd0;
        slide_right         <= 1'b0;
        slide_step          <= 6'd0;
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

                if (!display_valid || (ALLOW_IMMEDIATE && ready_immediate)) begin
                    active_buf_idx      <= ready_buf_sync1;
                    frame_commit_toggle <= ~frame_commit_toggle;
                    display_valid       <= 1'b1;
                    slide_offset        <= 11'd0;
                    fluid_progress      <= 9'd0;
                    transition_level    <= 6'd0;
                end else begin
                    transition_active <= 1'b1;
                    transition_mode   <= selected_effect(effect_select,effect_lfsr,transition_mode,fluid_enable);
                    slide_right       <= ready_right_sync1;
                    slide_step        <= 6'd0;
                    slide_offset      <= 11'd0;
                    fluid_progress<=9'd0;
                    transition_level  <= 6'd0;
                    end_hold          <= 1'b0;

                end
            end else if (transition_active) begin
                if (end_hold) begin
                    active_buf_idx      <= slide_new_buf_idx;
                    frame_commit_toggle <= ~frame_commit_toggle;
                    transition_active   <= 1'b0;
                    slide_offset        <= 11'd0;
                    fluid_progress      <= 9'd0;
                    slide_step          <= 6'd0;
                    transition_level    <= 6'd0;
                    end_hold            <= 1'b0;

                end else if (slide_step >= 6'd47) begin
                    slide_step       <= 6'd48;
                    slide_offset     <= 11'd1280;
                    fluid_progress<=9'd256;
                    transition_level <= 6'd0;
                    end_hold         <= 1'b1;
                end else begin
                    slide_step       <= slide_step + 1'b1;
                    slide_offset     <= ease_offset(slide_step + 6'd1);
                    fluid_progress<=phase_at_step(slide_step + 6'd1);
                    transition_level <= (transition_mode == FX_FADE) ?
                                        fade_darkness(slide_step + 6'd1) : 6'd0;
                end
            end else begin
                transition_level <= 6'd0;
            end
        end
    end
end

endmodule
