module saixian_osd_overlay(
    input  wire        clk,
    input  wire        rst,
    input  wire        de_i,
    input  wire [9:0]  x_i,
    input  wire [8:0]  y_i,
    input  wire [23:0] rgb_in_i,
    input  wire        display_valid,
    input  wire [2:0]  loading_phase,
    input  wire [3:0]  state,
    input  wire [1:0]  project_id,
    input  wire [6:0]  minutes,
    input  wire [5:0]  seconds,
    input  wire [3:0]  countdown_value,
    input  wire [9:0]  ticker_x,
    input  wire [15:0] source_width_bcd,
    input  wire [15:0] source_height_bcd,
    input  wire [2:0]  error_code,
    input  wire        transition_active,
    input  wire [5:0]  transition_level,
    input  wire [7:0]  audio_level,
    input  wire        spectrum_active,
    input  wire [4:0]  spectrum_tone_bin,
    input  wire        settings_mode,
    input  wire [1:0]  setting_item,
    input  wire [3:0]  volume_setting,
    input  wire [3:0]  brightness_setting,
    input  wire [3:0]  contrast_setting,
    input  wire [1:0]  sharpness_setting,
    output reg  [23:0] rgb_out
);

localparam ST_CAROUSEL = 4'd0;
localparam ST_PREPARE  = 4'd1;
localparam ST_COUNT3   = 4'd2;
localparam ST_COUNT2   = 4'd3;
localparam ST_COUNT1   = 4'd4;
localparam ST_START    = 4'd5;
localparam ST_RUNNING  = 4'd6;
localparam ST_PAUSED   = 4'd7;
localparam ST_FINISH   = 4'd8;

reg [6:0] glyph_id;
reg [3:0] font_row;
reg [3:0] font_col;
reg       text_region;
reg [23:0] text_color;
reg [3:0] slot;
reg [9:0] local_x;
reg [8:0] local_y;
reg [23:0] base_rgb;
reg [9:0] progress_width;
reg [4:0] fade_rank;
reg [4:0] spectrum_bin;
reg [6:0] spectrum_h3;
reg [7:0] spectrum_h5;
reg [5:0] spectrum_height;
reg [3:0] setting_value;
reg [9:0] setting_bar_width;
reg       spinner_pixel;
reg [2:0] spinner_segment;
reg [6:0] glyph_id_q;
reg [3:0] font_row_q;
reg [3:0] font_col_q;
reg       text_region_q;
reg       text_enable_q;
reg [23:0] text_color_q;
reg [23:0] render_rgb_q;
reg [7:0] audio_level_q;
reg       spectrum_active_q;
reg [4:0] spectrum_tone_bin_q;
reg [3:0]  font_col_q2;
reg        text_region_q2;
reg        text_enable_q2;
reg [23:0] text_color_q2;
reg [23:0] render_rgb_q2;
reg [23:0] rgb_comb;
reg        de;
reg [9:0]  x;
reg [8:0]  y;
reg [23:0] rgb_in;
wire [15:0] font_bits;
wire font_pixel_q = font_bits[15-font_col_q2];
wire [10:0] ticker_local_x = {1'b0, x} + 11'd224 - {1'b0, ticker_x};

saixian_font_rom u_font_rom(
    .clk     (clk),
    .glyph_id(glyph_id_q),
    .row     (font_row_q),
    .bits    (font_bits)
);

function [6:0] digit_glyph;
    input [3:0] digit;
    begin
        digit_glyph = {3'd0,digit} + 7'd1;
    end
endfunction

function [6:0] project_glyph;
    input [1:0] project;
    input [3:0] index;
    begin
        project_glyph = 7'd0;
        case (project)
            2'd0: case (index)
                0: project_glyph=7'd2; 1: project_glyph=7'd1;
                2: project_glyph=7'd1; 3: project_glyph=7'd37;
                default: project_glyph=7'd0;
            endcase
            2'd1: case (index)
                0: project_glyph=7'd38; 1: project_glyph=7'd39;
                default: project_glyph=7'd0;
            endcase
            2'd2: case (index)
                0: project_glyph=7'd40; 1: project_glyph=7'd41;
                2: project_glyph=7'd42; 3: project_glyph=7'd40;
                default: project_glyph=7'd0;
            endcase
            default: case (index)
                0: project_glyph=7'd43; 1: project_glyph=7'd44;
                2: project_glyph=7'd45; 3: project_glyph=7'd46;
                default: project_glyph=7'd0;
            endcase
        endcase
    end
endfunction

function [6:0] state_glyph;
    input [3:0] current_state;
    input [3:0] index;
    begin
        state_glyph = 7'd0;
        case (current_state)
            ST_CAROUSEL: case(index)
                0:state_glyph=7'd15; 1:state_glyph=7'd16; 2:state_glyph=7'd17;
                3:state_glyph=7'd18; 4:state_glyph=7'd19; 5:state_glyph=7'd20;
                default:state_glyph=7'd0;
            endcase
            ST_PREPARE: case(index)
                0:state_glyph=7'd47; 1:state_glyph=7'd48;
                2:state_glyph=7'd21; 3:state_glyph=7'd22;
                default:state_glyph=7'd0;
            endcase
            ST_COUNT3,ST_COUNT2,ST_COUNT1: case(index)
                0:state_glyph=7'd23; 1:state_glyph=7'd24; 2:state_glyph=7'd25;
                default:state_glyph=7'd0;
            endcase
            ST_START: case(index)
                0:state_glyph=7'd70; 1:state_glyph=7'd15;
                2:state_glyph=7'd26; 3:state_glyph=7'd27;
                default:state_glyph=7'd0;
            endcase
            ST_RUNNING: case(index)
                0:state_glyph=7'd70; 1:state_glyph=7'd15; 2:state_glyph=7'd28;
                3:state_glyph=7'd29; 4:state_glyph=7'd30;
                default:state_glyph=7'd0;
            endcase
            ST_PAUSED: case(index)
                0:state_glyph=7'd70; 1:state_glyph=7'd15;
                2:state_glyph=7'd31; 3:state_glyph=7'd32;
                default:state_glyph=7'd0;
            endcase
            ST_FINISH: case(index)
                0:state_glyph=7'd70; 1:state_glyph=7'd15;
                2:state_glyph=7'd35; 3:state_glyph=7'd36;
                default:state_glyph=7'd0;
            endcase
            default: state_glyph=7'd0;
        endcase
    end
endfunction

function [6:0] ticker_glyph;
    input [1:0] project;
    input [3:0] index;
    begin
        ticker_glyph = 7'd0;
        case (index)
            0: ticker_glyph = 7'd80; // 转
            1: ticker_glyph = 7'd20; // 播
            2: ticker_glyph = 7'd11; // :
            default: begin
                case (project)
                    2'd0: case (index)
                        3:ticker_glyph=7'd2; 4:ticker_glyph=7'd1;
                        5:ticker_glyph=7'd1; 6:ticker_glyph=7'd37;
                        default:ticker_glyph=7'd0;
                    endcase
                    2'd1: case (index)
                        3:ticker_glyph=7'd38; 4:ticker_glyph=7'd39;
                        default:ticker_glyph=7'd0;
                    endcase
                    2'd2: case (index)
                        3:ticker_glyph=7'd40; 4:ticker_glyph=7'd41;
                        5:ticker_glyph=7'd42; 6:ticker_glyph=7'd40;
                        default:ticker_glyph=7'd0;
                    endcase
                    default: case (index)
                        3:ticker_glyph=7'd43; 4:ticker_glyph=7'd44;
                        5:ticker_glyph=7'd45; 6:ticker_glyph=7'd46;
                        default:ticker_glyph=7'd0;
                    endcase
                endcase
            end
        endcase
    end
endfunction

function [6:0] error_glyph;
    input [2:0] code;
    input [3:0] index;
    begin
        error_glyph = 7'd0;
        case (code)
            3'd1: case(index)
                0:error_glyph=7'd50; 1:error_glyph=7'd51; 2:error_glyph=7'd49;
                default:error_glyph=7'd0;
            endcase
            3'd2: case(index)
                0:error_glyph=7'd53; 1:error_glyph=7'd54;
                2:error_glyph=7'd55; 3:error_glyph=7'd56;
                default:error_glyph=7'd0;
            endcase
            3'd3: case(index)
                0:error_glyph=7'd57; 1:error_glyph=7'd58; 2:error_glyph=7'd59;
                default:error_glyph=7'd0;
            endcase
            3'd4: case(index)
                0:error_glyph=7'd60; 1:error_glyph=7'd61;
                2:error_glyph=7'd55; 3:error_glyph=7'd56;
                default:error_glyph=7'd0;
            endcase
            default: case(index)
                0:error_glyph=7'd62; 1:error_glyph=7'd63;
                2:error_glyph=7'd64; 3:error_glyph=7'd63;
                default:error_glyph=7'd0;
            endcase
        endcase
    end
endfunction

always @* begin
    glyph_id   = 7'd0;
    font_row   = 4'd0;
    font_col   = 4'd0;
    text_region = 1'b0;
    text_color = 24'hFFFFFF;
    slot       = 4'd0;
    local_x    = 10'd0;
    local_y    = 9'd0;

    if (error_code != 0) begin
        if ((x >= 10'd224) && (x < 10'd416) && (y >= 9'd96) && (y < 9'd160)) begin
            local_x = x - 10'd224;
            slot = local_x[9:6];
            font_col = local_x[5:2];
            font_row = (y - 9'd96) >> 2;
            case(slot)
                0:glyph_id=7'd12;
                1:glyph_id=7'd1;
                2:glyph_id=digit_glyph({1'b0,error_code});
                default:glyph_id=7'd0;
            endcase
            text_region=1'b1;
            text_color=24'hFFD166;
        end else if ((x >= 10'd192) && (x < 10'd448) && (y >= 9'd208) && (y < 9'd272)) begin
            local_x = x - 10'd192;
            slot = local_x[9:6];
            font_col = local_x[5:2];
            font_row = (y - 9'd208) >> 2;
            glyph_id = error_glyph(error_code,slot);
            text_region=1'b1;
        end
    end else if (display_valid && settings_mode) begin
        // Settings title: 设置
        if ((x >= 10'd288) && (x < 10'd352) && (y >= 9'd84) && (y < 9'd116)) begin
            local_x = x - 10'd288;
            slot = local_x[8:5];
            font_col = local_x[4:1];
            font_row = (y - 9'd84) >> 1;
            glyph_id = (slot == 0) ? 7'd72 : ((slot == 1) ? 7'd73 : 7'd0);
            text_region = 1'b1;
            text_color = 24'h7DE3FF;
        end else if ((x >= 10'd160) && (x < 10'd224) &&
                     (((y >= 9'd144) && (y < 9'd176)) ||
                      ((y >= 9'd200) && (y < 9'd232)) ||
                      ((y >= 9'd256) && (y < 9'd288)) ||
                      ((y >= 9'd312) && (y < 9'd344)))) begin
            local_x = x - 10'd160;
            slot = local_x[8:5];
            font_col = local_x[4:1];
            if (y < 9'd176) begin
                font_row = (y - 9'd144) >> 1;
                glyph_id = (slot == 0) ? 7'd74 : ((slot == 1) ? 7'd75 : 7'd0); // 音量
            end else if (y < 9'd232) begin
                font_row = (y - 9'd200) >> 1;
                glyph_id = (slot == 0) ? 7'd76 : ((slot == 1) ? 7'd77 : 7'd0); // 亮度
            end else if (y < 9'd288) begin
                font_row = (y - 9'd256) >> 1;
                glyph_id = (slot == 0) ? 7'd78 : ((slot == 1) ? 7'd70 : 7'd0); // 对比
            end else begin
                font_row = (y - 9'd312) >> 1;
                glyph_id = (slot == 0) ? 7'd79 : ((slot == 1) ? 7'd77 : 7'd0); // 锐度
            end
            text_region = 1'b1;
            text_color = 24'hFFFFFF;
        end else if ((x >= 10'd464) && (x < 10'd496) &&
                     (((y >= 9'd144) && (y < 9'd176)) ||
                      ((y >= 9'd200) && (y < 9'd232)) ||
                      ((y >= 9'd256) && (y < 9'd288)) ||
                      ((y >= 9'd312) && (y < 9'd344)))) begin
            font_col = (x - 10'd464) >> 1;
            if (y < 9'd176) begin font_row = (y - 9'd144) >> 1; glyph_id = digit_glyph(volume_setting); end
            else if (y < 9'd232) begin font_row = (y - 9'd200) >> 1; glyph_id = digit_glyph(brightness_setting); end
            else if (y < 9'd288) begin font_row = (y - 9'd256) >> 1; glyph_id = digit_glyph(contrast_setting); end
            else begin font_row = (y - 9'd312) >> 1; glyph_id = digit_glyph({2'd0,sharpness_setting}); end
            text_region = 1'b1;
            text_color = 24'hFFD166;
        end
    end else if (display_valid) begin
        if ((state == ST_CAROUSEL) &&
                     (ticker_local_x < 11'd224) &&
                     (y >= 9'd432) && (y < 9'd464)) begin
            local_x = ticker_local_x[9:0];
            slot = local_x[8:5];
            font_col = local_x[4:1];
            font_row = (y - 9'd432) >> 1;
            glyph_id = ticker_glyph(project_id,slot);
            text_region=1'b1;
            text_color=(slot >= 3) ? 24'hFFD166 : 24'hFFFFFF;
        end else if ((x >= 10'd20) && (x < 10'd148) && (y >= 9'd16) && (y < 9'd48)) begin
            local_x = x - 10'd20;
            slot = local_x[8:5];
            font_col = local_x[4:1];
            font_row = (y - 9'd16) >> 1;
            glyph_id = project_glyph(project_id,slot);
            text_region=1'b1;
        end else if ((state != ST_CAROUSEL) && (x >= 10'd460) && (x < 10'd620) && (y >= 9'd16) && (y < 9'd48)) begin
            local_x = x - 10'd460;
            slot = local_x[8:5];
            font_col = local_x[4:1];
            font_row = (y - 9'd16) >> 1;
            case(slot)
                0:glyph_id=digit_glyph(minutes / 10);
                1:glyph_id=digit_glyph(minutes % 10);
                2:glyph_id=7'd11;
                3:glyph_id=digit_glyph(seconds / 10);
                4:glyph_id=digit_glyph(seconds % 10);
                default:glyph_id=7'd0;
            endcase
            text_region=1'b1;
        end else if ((state == ST_CAROUSEL) && (x >= 10'd488) && (x < 10'd632) && (y >= 9'd24) && (y < 9'd40)) begin
            // Source BMP dimensions: four digits, 'x', four digits.
            local_x = x - 10'd488;
            slot = local_x[7:4];
            font_col = local_x[3:0];
            // In this branch y is 24..39; this is exactly y-24 without an adder.
            font_row = {~y[3], y[2:0]};
            case(slot)
                0:glyph_id=(source_width_bcd[15:12] == 0) ? 7'd0 : digit_glyph(source_width_bcd[15:12]);
                1:glyph_id=((source_width_bcd[15:12] == 0) && (source_width_bcd[11:8] == 0)) ? 7'd0 : digit_glyph(source_width_bcd[11:8]);
                2:glyph_id=((source_width_bcd[15:8] == 0) && (source_width_bcd[7:4] == 0)) ? 7'd0 : digit_glyph(source_width_bcd[7:4]);
                3:glyph_id=digit_glyph(source_width_bcd[3:0]);
                4:glyph_id=7'd71;
                5:glyph_id=(source_height_bcd[15:12] == 0) ? 7'd0 : digit_glyph(source_height_bcd[15:12]);
                6:glyph_id=((source_height_bcd[15:12] == 0) && (source_height_bcd[11:8] == 0)) ? 7'd0 : digit_glyph(source_height_bcd[11:8]);
                7:glyph_id=((source_height_bcd[15:8] == 0) && (source_height_bcd[7:4] == 0)) ? 7'd0 : digit_glyph(source_height_bcd[7:4]);
                8:glyph_id=digit_glyph(source_height_bcd[3:0]);
                default:glyph_id=7'd0;
            endcase
            text_region=1'b1;
            text_color=24'h9FE7FF;
        end else if ((x >= 10'd180) && (x < 10'd372) && (y >= 9'd16) && (y < 9'd48)) begin
            // Keep the normal state label inside the top OSD bar so carousel
            // images remain unobstructed. Six 16x16 glyphs are scaled 2x.
            local_x = x - 10'd180;
            slot = local_x[8:5];
            font_col = local_x[4:1];
            font_row = (y - 9'd16) >> 1;
            glyph_id = state_glyph(state,slot);
            text_region=1'b1;
            case(state)
                ST_RUNNING: text_color=24'h5CFF8A;
                ST_PAUSED : text_color=24'hFFD166;
                ST_FINISH : text_color=24'hFF6B6B;
                default   : text_color=24'hFFFFFF;
            endcase
        end else if ((state >= ST_COUNT3) && (state <= ST_COUNT1) &&
                     (x >= 10'd256) && (x < 10'd384) && (y >= 9'd210) && (y < 9'd338)) begin
            local_x = x - 10'd256;
            font_col = local_x[6:3];
            font_row = (y - 9'd210) >> 3;
            glyph_id = digit_glyph(countdown_value);
            text_region=1'b1;
            text_color=24'hFFD166;
        end
    end
end

always @* begin
    progress_width = seconds * 10'd8;
    fade_rank = {x[2]^y[0], x[1]^y[2], x[0]^y[1], x[2]^y[2], x[1]^y[0]};
    spectrum_bin = 5'd0;
    spectrum_h3 = 7'd0;
    spectrum_h5 = 8'd0;
    spectrum_height = 6'd0;
    setting_value = 4'd0;
    setting_bar_width = 10'd0;
    spinner_pixel = 1'b0;
    spinner_segment = 3'd0;

    if (!de)
        base_rgb = 24'd0;
    else if (error_code != 0)
        base_rgb = {8'h38 + {5'd0,y[4:2]},8'h08,8'h12};
    else if (!display_valid)
        base_rgb = {8'h08,8'h18 + {5'd0,y[4:2]},8'h30};
    else
        base_rgb = rgb_in;

    rgb_comb = base_rgb;
    if (de && display_valid && (transition_level != 6'd0) &&
        ({1'b0,fade_rank} < transition_level))
        rgb_comb = 24'd0;

    // Eight-spoke boot spinner. One bright spoke advances at 10 Hz while the
    // remaining spokes stay dim, making SD scan/first-frame progress visible.
    else if (de && (error_code == 0) && !display_valid) begin
        if ((x >= 10'd314) && (x < 10'd326) && (y >= 9'd178) && (y < 9'd204)) begin
            spinner_pixel = 1'b1; spinner_segment = 3'd0;
        end else if ((x >= 10'd342) && (x < 10'd360) && (y >= 9'd194) && (y < 9'd212)) begin
            spinner_pixel = 1'b1; spinner_segment = 3'd1;
        end else if ((x >= 10'd350) && (x < 10'd376) && (y >= 9'd226) && (y < 9'd238)) begin
            spinner_pixel = 1'b1; spinner_segment = 3'd2;
        end else if ((x >= 10'd342) && (x < 10'd360) && (y >= 9'd252) && (y < 9'd270)) begin
            spinner_pixel = 1'b1; spinner_segment = 3'd3;
        end else if ((x >= 10'd314) && (x < 10'd326) && (y >= 9'd260) && (y < 9'd286)) begin
            spinner_pixel = 1'b1; spinner_segment = 3'd4;
        end else if ((x >= 10'd280) && (x < 10'd298) && (y >= 9'd252) && (y < 9'd270)) begin
            spinner_pixel = 1'b1; spinner_segment = 3'd5;
        end else if ((x >= 10'd264) && (x < 10'd290) && (y >= 9'd226) && (y < 9'd238)) begin
            spinner_pixel = 1'b1; spinner_segment = 3'd6;
        end else if ((x >= 10'd280) && (x < 10'd298) && (y >= 9'd194) && (y < 9'd212)) begin
            spinner_pixel = 1'b1; spinner_segment = 3'd7;
        end

        if (spinner_pixel)
            rgb_comb = (spinner_segment == loading_phase) ? 24'h38E8FF : 24'h23506A;
    end

    else if (de && display_valid && settings_mode && (error_code == 0)) begin
        if ((x >= 10'd112) && (x < 10'd528) && (y >= 9'd64) && (y < 9'd384))
            rgb_comb = 24'h101827;

        if (((y >= 9'd136) && (y < 9'd184)) ||
            ((y >= 9'd192) && (y < 9'd240)) ||
            ((y >= 9'd248) && (y < 9'd296)) ||
            ((y >= 9'd304) && (y < 9'd352))) begin
            if (y < 9'd184) begin setting_value = volume_setting; setting_bar_width = volume_setting * 10'd24; end
            else if (y < 9'd240) begin setting_value = brightness_setting; setting_bar_width = brightness_setting * 10'd24; end
            else if (y < 9'd296) begin setting_value = contrast_setting; setting_bar_width = contrast_setting * 10'd24; end
            else begin setting_value = {2'd0,sharpness_setting}; setting_bar_width = sharpness_setting * 10'd64; end

            if ((setting_item == 0 && y < 9'd184) ||
                (setting_item == 1 && y >= 9'd192 && y < 9'd240) ||
                (setting_item == 2 && y >= 9'd248 && y < 9'd296) ||
                (setting_item == 3 && y >= 9'd304)) begin
                if ((x >= 10'd128) && (x < 10'd512)) rgb_comb = 24'h203B5A;
            end

            if ((x >= 10'd248) && (x < 10'd440) &&
                (((y >= 9'd154) && (y < 9'd166)) ||
                 ((y >= 9'd210) && (y < 9'd222)) ||
                 ((y >= 9'd266) && (y < 9'd278)) ||
                 ((y >= 9'd322) && (y < 9'd334)))) begin
                if ((x - 10'd248) < setting_bar_width)
                    rgb_comb = 24'h34D6FF;
                else
                    rgb_comb = 24'h35445A;
            end
        end
    end

    // FPGA-generated lower-third ticker.  It is independent of the BMP frame
    // buffers, so image swaps cannot leave stale text or tear the banner.
    else if (de && display_valid && (error_code == 0) && !settings_mode &&
        (state == ST_CAROUSEL) && (y >= 9'd424) && (y < 9'd472)) begin
        if (y < 9'd428)
            rgb_comb = 24'h36C7FF;
        else
            rgb_comb = {1'b0,rgb_comb[23:17],1'b0,rgb_comb[15:9],1'b0,rgb_comb[7:1]};
    end

    else if (de && display_valid && (error_code == 0) && !settings_mode) begin
        if (y < 9'd64)
            rgb_comb = {1'b0,rgb_comb[23:17],1'b0,rgb_comb[15:9],1'b0,rgb_comb[7:1]};

        if ((state == ST_RUNNING || state == ST_PAUSED) &&
            ((x < 10'd6) || (x > 10'd633) || (y < 9'd6) || (y > 9'd473))) begin
            if (state == ST_PAUSED || seconds[0])
                rgb_comb = (state == ST_PAUSED) ? 24'hFFB000 : 24'h00D46A;
        end

        // The progress and audio bars belong to the event UI.  Keep the
        // carousel image clean until KEY1 starts the event flow.
        if ((state != ST_CAROUSEL) &&
            (y >= 9'd398) && (y < 9'd414) && (x >= 10'd80) && (x < 10'd560)) begin
            // Carry-free colour overlay keeps the photograph visible while
            // avoiding three 8-bit adders in the 75 MHz pixel critical path.
            if ((state == ST_RUNNING) && ((x - 10'd80) < progress_width))
                rgb_comb = rgb_comb | 24'h0C703D;
            else
                rgb_comb = rgb_comb | 24'h121A23;
        end

        // Lightweight 32-bin spectrum. The cue generator supplies the known
        // fundamental, while adjacent leakage and the weak odd harmonics of
        // its triangle wave keep the result sparse and physically plausible.
        // High frequencies are on the left and low frequencies on the right.
        if ((state != ST_CAROUSEL) &&
            (y >= 9'd416) && (y < 9'd468) && (x >= 10'd64) && (x < 10'd576)) begin
            spectrum_bin = 5'd31 - ((x - 10'd64) >> 4);
            spectrum_h3 = {2'd0,spectrum_tone_bin_q} + ({2'd0,spectrum_tone_bin_q} << 1);
            spectrum_h5 = {3'd0,spectrum_tone_bin_q} + ({3'd0,spectrum_tone_bin_q} << 2);
            spectrum_height = 6'd4;
            if (spectrum_active_q && (audio_level_q != 8'd0)) begin
                if (spectrum_bin == spectrum_tone_bin_q)
                    spectrum_height = 6'd8 + {1'b0,audio_level_q[7:3]};
                else if (((spectrum_tone_bin_q != 5'd0) &&
                          (spectrum_bin == (spectrum_tone_bin_q - 5'd1))) ||
                         ((spectrum_tone_bin_q != 5'd31) &&
                          (spectrum_bin == (spectrum_tone_bin_q + 5'd1))))
                    spectrum_height = 6'd4 + {2'd0,audio_level_q[7:4]};
                else if ((spectrum_h3 <= 7'd31) &&
                         ({2'd0,spectrum_bin} == spectrum_h3))
                    spectrum_height = 6'd4 + {3'd0,audio_level_q[7:5]};
                else if ((spectrum_h5 <= 8'd31) &&
                         ({3'd0,spectrum_bin} == spectrum_h5))
                    spectrum_height = 6'd4 + {4'd0,audio_level_q[7:6]};
            end
            if ((x[3:0] < 4'd12) &&
                (y >= (9'd468 - {3'd0,spectrum_height}))) begin
                if (spectrum_bin >= 5'd22)
                    rgb_comb = 24'h37DFFF;
                else if (spectrum_bin >= 5'd11)
                    rgb_comb = 24'h36E58D;
                else if (spectrum_bin >= 5'd4)
                    rgb_comb = 24'hFFD05A;
                else
                    rgb_comb = 24'hFF625F;
            end
        end
    end

end

// Split coordinate/text decoding and font lookup across two pixel clocks.
// This removes the former x/y -> glyph ROM -> RGB path that could not meet
// the 75 MHz 720p clock.
always @(posedge clk or posedge rst) begin
    if (rst) begin
        de <= 1'b0;
        x <= 10'd0;
        y <= 9'd0;
        rgb_in <= 24'd0;
        glyph_id_q <= 7'd0;
        font_row_q <= 4'd0;
        font_col_q <= 4'd0;
        text_region_q <= 1'b0;
        text_enable_q <= 1'b0;
        text_color_q <= 24'd0;
        render_rgb_q <= 24'd0;
        audio_level_q <= 8'd0;
        spectrum_active_q <= 1'b0;
        spectrum_tone_bin_q <= 5'd0;
        font_col_q2 <= 4'd0;
        text_region_q2 <= 1'b0;
        text_enable_q2 <= 1'b0;
        text_color_q2 <= 24'd0;
        render_rgb_q2 <= 24'd0;
        rgb_out <= 24'd0;
    end else begin
        // Cut the top-level coordinate subtraction away from the large OSD
        // decode cone before the 75 MHz rendering pipeline.
        de <= de_i;
        x <= x_i;
        y <= y_i;
        rgb_in <= rgb_in_i;
        glyph_id_q <= glyph_id;
        font_row_q <= font_row;
        font_col_q <= font_col;
        text_region_q <= text_region;
        text_enable_q <= display_valid || (error_code != 0);
        text_color_q <= text_color;
        render_rgb_q <= rgb_comb;
        // Isolate the long volume-control cone from the 75 MHz OSD renderer.
        // One pixel-clock of spectrum-control latency is visually irrelevant
        // and preserves the existing video/font pipeline alignment.
        audio_level_q <= audio_level;
        spectrum_active_q <= spectrum_active;
        spectrum_tone_bin_q <= spectrum_tone_bin;
        // The font ROM has a registered BRAM output; the column select and
        // colour mux remain in the following stage.
        font_col_q2 <= font_col_q;
        text_region_q2 <= text_region_q;
        text_enable_q2 <= text_enable_q;
        text_color_q2 <= text_color_q;
        render_rgb_q2 <= render_rgb_q;
        rgb_out <= (text_region_q2 && font_pixel_q && text_enable_q2) ?
                   text_color_q2 : render_rgb_q2;
    end
end

endmodule
