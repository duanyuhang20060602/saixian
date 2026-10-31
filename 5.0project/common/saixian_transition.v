module saixian_transition #(parameter ALLOW_IMMEDIATE=0)(
    input wire fluid_enable,
    input  wire       clk,
    input  wire       rst,
    input  wire       frame_tick,
    input  wire       frame_ready_toggle,
    input  wire [1:0] ready_buf_idx,
    input  wire       ready_slide_right,
    input wire ready_immediate,
    input  wire [4:0] effect_select, // 0=random; 1=water, 2=scroll, 3=flip, 4=ribbons, 5=columns, 6=accordion, 7=metal, 8=portal, 9=glass, 10=tunnel, 11=tear
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

localparam FX_SLIDE=5'd0; // Legacy reader fallback when fluid_enable is false.

reg       ready_sync0;
reg       ready_sync1;
reg       ready_seen;
reg [1:0] ready_buf_sync0;
reg [1:0] ready_buf_sync1;
reg       ready_right_sync0;
reg       ready_right_sync1;
reg [6:0] slide_step;
reg [4:0] color_fraction;
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

function [4:0] selected_effect;
    input [4:0] selection;
    input [7:0] random_value;
    input [4:0] previous_effect;
    input water_allowed;
    reg [4:0] candidate;
    begin
        candidate={1'b0,random_value[3:0]};
        if(candidate>10)candidate=candidate-11;
        if(candidate==previous_effect)candidate=candidate==10 ? 0:candidate+1'b1;
        if(!water_allowed)selected_effect=FX_SLIDE;
        else case(selection)
            1:selected_effect=6;
            2:selected_effect=0;
            3:selected_effect=1;
            4:selected_effect=2;
            5:selected_effect=3;
            6:selected_effect=4;
            7:selected_effect=5;
            8:selected_effect=7;
            9:selected_effect=8;
            10:selected_effect=9;
            11:selected_effect=10;
            default:selected_effect=candidate;
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
        slide_step          <= 7'd0;
        color_fraction      <= 0;
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
                    // Advance once per transition. A fixed photo interval must
                    // not sample only a short subset of the LFSR period.
                    effect_lfsr <= {effect_lfsr[6:0],
                                    effect_lfsr[7] ^ effect_lfsr[5] ^ effect_lfsr[4] ^ effect_lfsr[3]};
                    transition_active <= 1'b1;
                    transition_mode   <= selected_effect(effect_select,effect_lfsr,transition_mode,fluid_enable);
                    slide_right       <= ready_right_sync1;
                    slide_step        <= 7'd0;
                    color_fraction <= 0;
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
                    slide_step          <= 7'd0;
        color_fraction      <= 0;
                    transition_level    <= 6'd0;
                    end_hold            <= 1'b0;

                end else if (slide_step >= (transition_mode==6 ? 7'd83:7'd47)) begin
                    slide_step       <= transition_mode==6 ? 7'd84:7'd48;
                    slide_offset     <= 11'd1280;
                    fluid_progress<=9'd256;
                    transition_level <= 6'd0;
                    end_hold         <= 1'b1;
                end else begin
                    slide_step       <= slide_step + 1'b1;
                    slide_offset     <= ease_offset(slide_step[5:0] + 6'd1);
                    if(transition_mode==6)begin
                        fluid_progress<=fluid_progress+(color_fraction==20 ? 9'd4:9'd3);
                        color_fraction<=color_fraction==20 ? 0:color_fraction+1'b1;
                    end else fluid_progress<=phase_at_step(slide_step[5:0] + 6'd1);
                    transition_level <= 6'd0;
                end
            end else begin
                transition_level <= 6'd0;
            end
        end
    end
end

endmodule
