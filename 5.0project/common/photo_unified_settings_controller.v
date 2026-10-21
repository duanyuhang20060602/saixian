module photo_unified_settings_controller #(
    parameter integer CLK_FREQ_HZ = 25_000_000,
    parameter integer TIMEOUT_SECONDS = 60,
    parameter integer POINTER_CONTROL = 0,
    parameter integer INTERVAL_CONTROL = 0,
    parameter integer IMAGE_MENU = 0
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       carousel_mode,
    input wire pointer_valid,pointer_increase,
    input wire [3:0] pointer_item,
    input  wire       key_next_item,
    input  wire       key_decrease,
    input  wire       key_enter_exit,
    input  wire       key_increase,
    input  wire       hmi_setting_valid,
    input  wire [2:0] hmi_setting_id,
    input  wire [7:0] hmi_setting_value,
    input  wire       hmi_reset_defaults,
    input  wire       effect_valid,
    input  wire [4:0] effect_value,
    input  wire       auto_valid,
    input  wire       auto_value,
    input wire audio_view_valid,audio_view_value,
    input wire color_mode_valid,color_mode_value,
    input wire edge_valid,edge_value,output reg edge_enable,
    output reg high_color_requested,
    output reg waveform_mode,
    output reg audio_repair_enable,
    output reg        settings_mode,
    output reg [3:0]  setting_item,
    output reg [4:0]  effect_select,
    output reg        auto_enable,
    output reg [4:0]  auto_interval_seconds,
    output reg [3:0]  volume_setting,
    output reg [3:0]  brightness_setting,
    output reg [3:0]  contrast_setting,
    output reg [3:0]  saturation_setting,
    output reg [1:0]  sharpness_setting,
    output reg        invert_setting,
    output reg        vintage_setting,
    output reg [1:0]  enhancement_setting
);
localparam [32:0] TIMEOUT_CYCLES = 64'd1 * CLK_FREQ_HZ * TIMEOUT_SECONDS;
reg [32:0] idle_timer;
wire pointer_event=POINTER_CONTROL && pointer_valid && pointer_item<=(INTERVAL_CONTROL ? 14:13);

function [3:0] quantize_percent;
    input [7:0] value;
    begin
        if      (value <= 8'd6)  quantize_percent = 4'd0;
        else if (value <= 8'd18) quantize_percent = 4'd1;
        else if (value <= 8'd31) quantize_percent = 4'd2;
        else if (value <= 8'd43) quantize_percent = 4'd3;
        else if (value <= 8'd56) quantize_percent = 4'd4;
        else if (value <= 8'd68) quantize_percent = 4'd5;
        else if (value <= 8'd81) quantize_percent = 4'd6;
        else if (value <= 8'd93) quantize_percent = 4'd7;
        else                     quantize_percent = 4'd8;
    end
endfunction

always @(posedge clk or posedge rst) begin
    if (rst) begin
        settings_mode      <= 1'b0;
        setting_item       <= 4'd0;
        effect_select      <= 3'd0;
        auto_interval_seconds<=5'd5;auto_enable        <= 1'b0;waveform_mode<=0;high_color_requested<=0;audio_repair_enable<=0;edge_enable<=0;
        volume_setting     <= 4'd5;
        brightness_setting <= 4'd4;
        contrast_setting   <= 4'd4;
        saturation_setting <= 4'd4;
        sharpness_setting  <= 2'd1;
        invert_setting     <= 1'b0;
        vintage_setting    <= 1'b0;
        enhancement_setting <= 2'd1;
        idle_timer         <= 33'd0;
    end else if (hmi_reset_defaults) begin
        effect_select      <= 3'd0;
        auto_interval_seconds<=5'd5;auto_enable        <= 1'b0;waveform_mode<=0;high_color_requested<=0;audio_repair_enable<=0;edge_enable<=0;
        volume_setting     <= 4'd5;
        brightness_setting <= 4'd4;
        contrast_setting   <= 4'd4;
        saturation_setting <= 4'd4;
        sharpness_setting  <= 2'd1;
        invert_setting     <= 1'b0;
        vintage_setting    <= 1'b0;
        enhancement_setting <= 2'd1;
        idle_timer         <= 33'd0;
    end else if (effect_valid) begin
        if (effect_value <= 11) effect_select <= effect_value;
        idle_timer <= 33'd0;
    end else if(edge_valid)begin
        edge_enable<=edge_value;idle_timer<=0;
    end else if (auto_valid) begin
        auto_enable <= auto_value;
        idle_timer <= 33'd0;
    end else if(color_mode_valid)begin
        high_color_requested<=color_mode_value;idle_timer<=0;
    end else if(audio_view_valid)begin
        waveform_mode<=audio_view_value;idle_timer<=0;
    end else if (hmi_setting_valid) begin
        idle_timer <= 33'd0;
        case (hmi_setting_id)
            3'd0: sharpness_setting  <= (hmi_setting_value > 3) ? 2'd3 : hmi_setting_value[1:0];
            3'd1: brightness_setting <= quantize_percent(hmi_setting_value);
            3'd2: contrast_setting   <= quantize_percent(hmi_setting_value);
            3'd3: saturation_setting <= quantize_percent(hmi_setting_value);
            3'd4: volume_setting     <= quantize_percent(hmi_setting_value);
            3'd5: invert_setting     <= (hmi_setting_value != 0);
            3'd6: vintage_setting    <= (hmi_setting_value != 0);
            3'd7: enhancement_setting <= (hmi_setting_value>2) ? 2'd2 : hmi_setting_value[1:0];
            default: ;
        endcase
    end else if (!carousel_mode) begin
        settings_mode <= 1'b0;
        idle_timer    <= 33'd0;
    end else if (!settings_mode) begin
        idle_timer <= 33'd0;
        if (key_enter_exit) begin
            settings_mode <= 1'b1;
            setting_item  <= IMAGE_MENU ? 4'd1:4'd0;
        end
    end else begin
        if (key_next_item || key_decrease || key_enter_exit || key_increase || pointer_event)
            idle_timer <= 33'd0;
        else if (idle_timer >= TIMEOUT_CYCLES - 1'b1) begin
            idle_timer    <= 33'd0;
            settings_mode <= 1'b0;
        end else
            idle_timer <= idle_timer + 1'b1;

        if(pointer_event && pointer_item<=(INTERVAL_CONTROL ? 14:13))setting_item<=pointer_item;
        if (key_enter_exit)
            settings_mode <= 1'b0;
        else if (key_next_item)
            setting_item <= (setting_item == (INTERVAL_CONTROL ? 4'd14:4'd13)) ? (IMAGE_MENU ? 4'd1:4'd0) : setting_item + 1'b1;
        else if (key_decrease || (pointer_event && !pointer_increase)) begin
            case (pointer_event ? pointer_item:setting_item)
                2'd0: if (volume_setting     != 0) volume_setting     <= volume_setting - 1'b1;
                2'd1: if (brightness_setting != 0) brightness_setting <= brightness_setting - 1'b1;
                2'd2: if (contrast_setting   != 0) contrast_setting   <= contrast_setting - 1'b1;
                2'd3: if (sharpness_setting  != 0) sharpness_setting  <= sharpness_setting - 1'b1;
                3'd4: if (saturation_setting != 0) saturation_setting <= saturation_setting - 1'b1;
                3'd5: invert_setting <= 1'b0;
                3'd6: vintage_setting <= 1'b0;
                3'd7: if(enhancement_setting!=0) enhancement_setting<=enhancement_setting-1'b1;
                4'd8: if(effect_select!=0) effect_select<=effect_select-1'b1;
                4'd9: auto_enable<=1'b0;
                4'd10: waveform_mode<=0;
                4'd11: high_color_requested<=0;
                4'd12: audio_repair_enable<=0;
                4'd13: edge_enable<=0;
                4'd14: if(INTERVAL_CONTROL && auto_interval_seconds>1)auto_interval_seconds<=auto_interval_seconds-1'b1;
            endcase
        end else if (key_increase || (pointer_event && pointer_increase)) begin
            case (pointer_event ? pointer_item:setting_item)
                2'd0: if (volume_setting     < 8) volume_setting     <= volume_setting + 1'b1;
                2'd1: if (brightness_setting < 8) brightness_setting <= brightness_setting + 1'b1;
                2'd2: if (contrast_setting   < 8) contrast_setting   <= contrast_setting + 1'b1;
                2'd3: if (sharpness_setting  < 3) sharpness_setting  <= sharpness_setting + 1'b1;
                3'd4: if (saturation_setting < 8) saturation_setting <= saturation_setting + 1'b1;
                3'd5: invert_setting <= 1'b1;
                3'd6: vintage_setting <= 1'b1;
                3'd7: if(enhancement_setting<2) enhancement_setting<=enhancement_setting+1'b1;
                4'd8: if(effect_select<11) effect_select<=effect_select+1'b1;
                4'd9: auto_enable<=1'b1;
                4'd10: waveform_mode<=1;
                4'd11: high_color_requested<=1;
                4'd12: audio_repair_enable<=1;
                4'd13: edge_enable<=1;
                4'd14: if(INTERVAL_CONTROL && auto_interval_seconds<30)auto_interval_seconds<=auto_interval_seconds+1'b1;
            endcase
        end
    end
end
endmodule
