module saixian_settings_controller #(
    parameter integer CLK_FREQ_HZ = 25_000_000,
    parameter integer TIMEOUT_SECONDS = 60,
    parameter integer IMAGE_MENU = 0
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       carousel_mode,
    input  wire       key_next_item,
    input  wire       key_decrease,
    input  wire       key_enter_exit,
    input  wire       key_increase,
    input  wire       hmi_setting_valid,
    input  wire [2:0] hmi_setting_id,
    input  wire [7:0] hmi_setting_value,
    input  wire       hmi_reset_defaults,
    input  wire       effect_valid,
    input  wire [2:0] effect_value,
    input  wire       auto_valid,
    input  wire       auto_value,
    output reg        settings_mode,
    output reg [3:0]  setting_item,
    output reg [2:0]  effect_select,
    output reg        auto_enable,
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
        auto_enable        <= 1'b0;
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
        auto_enable        <= 1'b0;
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
        if (effect_value <= 6) effect_select <= effect_value;
        idle_timer <= 33'd0;
    end else if (auto_valid) begin
        auto_enable <= auto_value;
        idle_timer <= 33'd0;
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
        if (key_next_item || key_decrease || key_enter_exit || key_increase)
            idle_timer <= 33'd0;
        else if (idle_timer >= TIMEOUT_CYCLES - 1'b1) begin
            idle_timer    <= 33'd0;
            settings_mode <= 1'b0;
        end else
            idle_timer <= idle_timer + 1'b1;

        if (key_enter_exit)
            settings_mode <= 1'b0;
        else if (key_next_item)
            setting_item <= (setting_item == 4'd9) ? (IMAGE_MENU ? 4'd1:4'd0) : setting_item + 1'b1;
        else if (key_decrease) begin
            case (setting_item)
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
            endcase
        end else if (key_increase) begin
            case (setting_item)
                2'd0: if (volume_setting     < 8) volume_setting     <= volume_setting + 1'b1;
                2'd1: if (brightness_setting < 8) brightness_setting <= brightness_setting + 1'b1;
                2'd2: if (contrast_setting   < 8) contrast_setting   <= contrast_setting + 1'b1;
                2'd3: if (sharpness_setting  < 3) sharpness_setting  <= sharpness_setting + 1'b1;
                3'd4: if (saturation_setting < 8) saturation_setting <= saturation_setting + 1'b1;
                3'd5: invert_setting <= 1'b1;
                3'd6: vintage_setting <= 1'b1;
                3'd7: if(enhancement_setting<2) enhancement_setting<=enhancement_setting+1'b1;
                4'd8: if(effect_select<6) effect_select<=effect_select+1'b1;
                4'd9: auto_enable<=1'b1;
            endcase
        end
    end
end
endmodule

module saixian_adaptive_enhance #(
    parameter integer WIDTH=1280, SPLIT_X=640, PHOTO_SMOOTH=0, EXTERNAL_GAIN=0
)(
    input wire clk,rst,de,vs,frame_tick,statistics_enable,
    input wire [10:0] x,input wire [9:0] y,
    input wire [23:0] rgb_in,input wire [1:0] mode,strength,external_gain,
    output reg [23:0] rgb_out,
    output wire de_out,vs_out,
    output wire [10:0] x_out,output wire [9:0] y_out,
    output wire [1:0] gain_out
);
wire [9:0] luma_sum={2'd0,rgb_in[23:16]}+{1'b0,rgb_in[15:8],1'b0}+{2'd0,rgb_in[7:0]};
wire [7:0] luma=luma_sum[9:2];
reg [7:0] line1 [0:WIDTH-1]; /* fehdl force_ram=1, ram_style="bram" */
reg [7:0] line2 [0:WIDTH-1]; /* fehdl force_ram=1, ram_style="bram" */
reg [7:0] above,above2;
reg [6:0] de_pipe,vs_pipe;
reg [10:0] xp [0:6];reg [9:0] yp [0:6];
reg [23:0] rgb0,rgb_tap,rgb1,rgb2,rgb3,rgb4;
reg [7:0] y0,y_tap,y1,y2;
reg [8:0] p0_q,p1_q,p2_q,p3_q;
reg [7:0] l0,ll0,l1,ll1,l2,ll2;
reg [11:0] neighborhood;
reg signed [9:0] detail;
reg [15:0] curve_product;
reg signed [8:0] correction;
reg signed [4:0] detail_q;
reg [6:0] tone_q;
reg bypass_q;
reg [1:0] gain;
reg [20:0] stat_sum;
reg [12:0] stat_count;
wire [20:0] stat_count_ext={8'd0,stat_count};
assign gain_out=gain;
assign de_out=de_pipe[6];assign vs_out=vs_pipe[6];
assign x_out=xp[6];assign y_out=yp[6];
function [7:0] tap;
    input [7:0] a,b;input valid;
    reg [8:0] difference;
    begin
        // One subtraction covers both signs. In unsigned 9-bit arithmetic,
        // [-24,-1] maps to [488,511]; avoid two subtractors and an abs mux.
        difference={1'b0,a}-{1'b0,b};
        tap=(valid && (difference<=9'd24 || difference>=9'd488)) ? b : a;
    end
endfunction
function [7:0] clamp_enhanced;
    input signed [12:0] v;
    begin clamp_enhanced=(v<0) ? 0 : ((v>255) ? 255 : v[7:0]);end
endfunction
wire [7:0] t0=tap(y0,l0,xp[0]>0);
wire [7:0] t1=tap(y0,ll0,xp[0]>1);
wire [7:0] t2=tap(y0,above,yp[0]>0);
wire [7:0] t3=tap(y0,l1,yp[0]>0 && xp[0]>0);
wire [7:0] t4=tap(y0,ll1,yp[0]>0 && xp[0]>1);
wire [7:0] t5=tap(y0,above2,yp[0]>1);
wire [7:0] t6=tap(y0,l2,yp[0]>1 && xp[0]>0);
wire [7:0] t7=tap(y0,ll2,yp[0]>1 && xp[0]>1);
// Balanced partial sums keep eight range decisions off a long adder chain.
wire [8:0] p0={1'b0,t0}+t1,p1={1'b0,t2}+t3,p2={1'b0,t4}+t5,p3={1'b0,t6}+t7;
wire [9:0] pair0={1'b0,p0_q}+p1_q,pair1={1'b0,p2_q}+p3_q;
wire signed [9:0] residual=$signed({1'b0,y1})-$signed({1'b0,neighborhood[11:4]});
reg signed [9:0] detail_term;
reg signed [7:0] tone_term;
// Clamp outside the useful range before the narrow arithmetic. This keeps
// the exact signed rounding and +/-12 bound without a wide add/negate/clamp.
wire signed [5:0] small_detail=detail[5:0];
wire signed [5:0] smooth_positive=-((small_detail+6'sd1)>>>1);
wire signed [5:0] smooth_negative=((-small_detail+6'sd1)>>>1);
wire signed [4:0] sharp_pair=$signed(detail[4:0])+($signed(detail[4:0])>>>1);
always @* begin
    if(PHOTO_SMOOTH && strength==1) begin
        if(detail>=23) detail_term=-10'sd12;
        else if(detail<=-23) detail_term=10'sd12;
        else detail_term=detail>0 ? smooth_positive : smooth_negative;
    end else if(detail>=-3 && detail<=3) detail_term=0;
    else case(strength)
        0:detail_term=0;
        1:detail_term=detail>=24 ? 10'sd12 : (detail<=-23 ? -10'sd12 : (small_detail>>>1));
        2:detail_term=detail>=12 ? 10'sd12 : (detail<=-12 ? -10'sd12 : detail);
        default:detail_term=detail>=8 ? 10'sd12 : (detail<=-8 ? -10'sd12 : sharp_pair);
    endcase
    case(gain)
        0:tone_term=0;
        // Half the previous lift: retain more mid-tone contrast/headroom.
        1:tone_term=$signed({2'b0,curve_product[15:10]});
        2:tone_term=$signed({1'b0,curve_product[15:9]});
        default:tone_term=$signed({1'b0,curve_product[15:9]})+$signed({2'b0,curve_product[15:10]});
    endcase
end
integer i;
// RAM has no reset: row/column validity masks exclude old/uninitialised taps.
always @(posedge clk) begin
    if(de && x<WIDTH) begin above<=line1[x];above2<=line2[x];line1[x]<=luma;end
    if(de_pipe[0] && xp[0]<WIDTH) line2[xp[0]]<=above;
end
always @(posedge clk or posedge rst) begin
    if(rst) begin
        de_pipe<=0;vs_pipe<=0;rgb0<=0;rgb_tap<=0;rgb1<=0;rgb2<=0;rgb3<=0;rgb4<=0;rgb_out<=0;
        detail_q<=0;tone_q<=0;bypass_q<=0;
        y0<=0;y_tap<=0;y1<=0;y2<=0;p0_q<=0;p1_q<=0;p2_q<=0;p3_q<=0;
        l0<=0;ll0<=0;l1<=0;ll1<=0;l2<=0;ll2<=0;
        neighborhood<=0;detail<=0;curve_product<=0;correction<=0;
        gain<=1;stat_sum<=0;stat_count<=0;
        for(i=0;i<7;i=i+1) begin xp[i]<=0;yp[i]<=0;end
    end else begin
        de_pipe<={de_pipe[5:0],de};vs_pipe<={vs_pipe[5:0],vs};
        xp[0]<=x;yp[0]<=y;
        for(i=1;i<7;i=i+1) begin xp[i]<=xp[i-1];yp[i]<=yp[i-1];end
        rgb0<=rgb_in;y0<=luma;
        rgb_tap<=rgb0;y_tap<=y0;p0_q<=p0;p1_q<=p1;p2_q<=p2;p3_q<=p3;
        rgb1<=rgb_tap;y1<=y_tap;
        if(de_pipe[0]) begin
            if(xp[0]==0) begin ll0<=y0;ll1<=above;ll2<=above2;end
            else begin ll0<=l0;ll1<=l1;ll2<=l2;end
            l0<=y0;l1<=above;l2<=above2;
        end
        neighborhood<=({4'd0,y_tap}<<3)+{2'd0,pair0}+{2'd0,pair1};
        rgb2<=rgb1;y2<=y1;detail<=residual;
        curve_product<=y1*(8'd255-y1);
        rgb3<=rgb2;
        detail_q<=detail_term[4:0];tone_q<=tone_term[6:0];
        bypass_q<=((mode==0) || (mode==2 && xp[3]<SPLIT_X));
        rgb4<=rgb3;
        correction<=bypass_q ? 9'sd0 : $signed({2'b0,tone_q})+$signed({{4{detail_q[4]}},detail_q});
        rgb_out<=de_pipe[5] ? {clamp_enhanced($signed({1'b0,rgb4[23:16]})+correction),
                               clamp_enhanced($signed({1'b0,rgb4[15:8]})+correction),
                               clamp_enhanced($signed({1'b0,rgb4[7:0]})+correction)} : 24'd0;
        // 1/256 spatial sampling; no per-pixel divider or histogram storage.
        if(EXTERNAL_GAIN) gain<=external_gain;
        else if(frame_tick) begin
            if(stat_count>32) begin
                if(stat_sum<(stat_count_ext<<6)) gain<=3;
                else if(stat_sum<((stat_count_ext<<6)+(stat_count_ext<<5))) gain<=2;
                else if(stat_sum<((stat_count_ext<<7)+(stat_count_ext<<4))) gain<=1;
                else gain<=0;
            end
            stat_sum<=0;stat_count<=0;
        end else if(de && statistics_enable && x[3:0]==0 && y[3:0]==0) begin
            stat_sum<=stat_sum+luma;stat_count<=stat_count+1'b1;
        end
    end
end
endmodule

module saixian_picture_adjust_pipe(
    input wire clk, input wire rst, input wire de, input wire [10:0] x,
    input wire [23:0] rgb_in,
    input wire [3:0] brightness_setting, input wire [3:0] contrast_setting,
    input wire [3:0] saturation_setting, input wire [1:0] sharpness_setting,
    output reg [23:0] rgb_out
);
reg [23:0] previous_rgb;
reg [23:0] rgb_in_s0;
reg        de_s0;
reg [10:0] x_s0;
// Conservative full-control ranges: contrast/brightness [-607,863],
// saturation [-447,701]. Eleven signed bits retain exact integer results.
reg signed [10:0] red_work_s1, green_work_s1, blue_work_s1;
reg [7:0] red_pre_s2, green_pre_s2, blue_pre_s2;
reg signed [8:0] luma_s2;
reg signed [10:0] red_work_comb, green_work_comb, blue_work_comb;
reg signed [11:0] red_delta_comb, green_delta_comb, blue_delta_comb;
reg signed [11:0] red_delta_s1, green_delta_s1, blue_delta_s1;
reg [7:0] red_base_s1, green_base_s1, blue_base_s1;
reg signed [10:0] brightness_offset_comb;
reg signed [10:0] brightness_offset_s1;
reg [10:0] contrast_config_s1, saturation_config_s2;
// Separate subtract, DSP multiply, Q4 rounding/add and clamp. Total latency: 8 clocks.
reg signed [8:0] red_sat_delta_s3, green_sat_delta_s3, blue_sat_delta_s3;
reg [10:0] saturation_config_s3;
reg signed [8:0] luma_s3, luma_s4;
reg signed [14:0] red_product_s4, green_product_s4, blue_product_s4;
reg [3:0] saturation_bias_s4;
reg red_carry_s4, green_carry_s4, blue_carry_s4;
reg signed [10:0] red_sat_s5, green_sat_s5, blue_sat_s5;

function gain_carry;
    input signed [8:0] value; input [1:0] selector;
    begin
        gain_carry=selector==1 ? value[2]&value[0] :
                   selector==2 ? value[1]&value[0] : 1'b0;
    end
endfunction

function signed [10:0] finish_saturation;
    input signed [14:0] product; input [3:0] bias;
    input carry_bit; input signed [8:0] luma_value;
    reg signed [14:0] rounded;
    begin
        rounded=product+$signed({1'b0,bias});
        finish_saturation=luma_value+(rounded>>>4)-$signed({1'b0,carry_bit});
    end
endfunction

// Decode frame-stable controls before the pixel multiplier path. Bits are
// {positive Q4 coefficient, rounding bias, low-bit correction selector}.
function [10:0] gain_config;
    input [3:0] level;input saturation;
    reg [4:0] coefficient;reg [3:0] bias;reg [1:0] carry_select;
    begin
        bias=0;carry_select=0;
        if(saturation) begin
            case(level)
                0:coefficient=0;1:coefficient=4;2:coefficient=8;
                3:begin coefficient=12;bias=12;end
                4:coefficient=16;5:coefficient=18;6:coefficient=20;7:coefficient=24;
                default:begin coefficient=28;carry_select=2;end
            endcase
        end else begin
            case(level)
                0:coefficient=8;1:begin coefficient=10;carry_select=1;end
                2:begin coefficient=12;carry_select=2;end
                3:begin coefficient=14;bias=14;end
                4:coefficient=16;5:coefficient=18;6:coefficient=20;7:coefficient=24;
                default:begin coefficient=28;carry_select=2;end
            endcase
        end
        gain_config={coefficient,bias,carry_select};
    end
endfunction
function signed [10:0] decoded_gain;
    input signed [10:0] value;input [10:0] config_bits;
    reg signed [16:0] product;reg carry_bit;
    begin
        product=value*$signed({1'b0,config_bits[10:6]});
        carry_bit=config_bits[1:0]==1 ? value[2]&value[0] :
                  config_bits[1:0]==2 ? value[1]&value[0] : 1'b0;
        decoded_gain=((product+$signed({1'b0,config_bits[5:2]}))>>>4)-$signed({1'b0,carry_bit});
    end
endfunction

function signed [10:0] contrast_scale_pipe;
    input signed [10:0] value; input [3:0] level;
    reg [4:0] coefficient;
    reg [3:0] rounding_bias;
    reg correction_bit;
    reg signed [16:0] product;
    begin
        rounding_bias=0;correction_bit=0;
        case(level)
            0:coefficient=8;
            1:begin coefficient=10;correction_bit=value[2]&value[0];end
            2:begin coefficient=12;correction_bit=value[1]&value[0];end
            3:begin coefficient=14;rounding_bias=14;end
            4:coefficient=16;5:coefficient=18;
            6:coefficient=20;7:coefficient=24;
            default:begin coefficient=28;correction_bit=value[1]&value[0];end
        endcase
        product=value*$signed({1'b0,coefficient});
        // Bias/carry correction preserves the old separate arithmetic-shift
        // rounding exactly, including negative inputs (not approximate gain).
        contrast_scale_pipe=((product+$signed({1'b0,rounding_bias}))>>>4)-$signed({1'b0,correction_bit});
    end
endfunction
function signed [10:0] saturation_scale_pipe;
    input signed [10:0] value; input [3:0] level;
    reg [4:0] coefficient;
    reg [3:0] rounding_bias;
    reg correction_bit;
    reg signed [16:0] product;
    begin
        rounding_bias=0;correction_bit=0;
        case(level)
            0:coefficient=0;1:coefficient=4;2:coefficient=8;
            3:begin coefficient=12;rounding_bias=12;end
            4:coefficient=16;5:coefficient=18;
            6:coefficient=20;7:coefficient=24;
            default:begin coefficient=28;correction_bit=value[1]&value[0];end
        endcase
        product=value*$signed({1'b0,coefficient});
        saturation_scale_pipe=((product+$signed({1'b0,rounding_bias}))>>>4)-$signed({1'b0,correction_bit});
    end
endfunction
function [7:0] clamp_pipe;
    input signed [10:0] value;
    begin
        if(value[10]) clamp_pipe=8'd0;
        else if(|value[9:8]) clamp_pipe=8'd255;
        else clamp_pipe=value[7:0];
    end
endfunction

wire [7:0] red_pre_wire=clamp_pipe(red_work_s1);
wire [7:0] green_pre_wire=clamp_pipe(green_work_s1);
wire [7:0] blue_pre_wire=clamp_pipe(blue_work_s1);
wire signed [10:0] luma_wire=($signed({1'b0,red_pre_wire})+
    ($signed({1'b0,green_pre_wire})<<<1)+$signed({1'b0,blue_pre_wire}))>>>2;

always @* begin
    case(brightness_setting)
        0:brightness_offset_comb=-11'sd64; 1:brightness_offset_comb=-11'sd48;
        2:brightness_offset_comb=-11'sd32; 3:brightness_offset_comb=-11'sd16;
        4:brightness_offset_comb=11'sd0; 5:brightness_offset_comb=11'sd16;
        6:brightness_offset_comb=11'sd32; 7:brightness_offset_comb=11'sd48;
        default:brightness_offset_comb=11'sd64;
    endcase
    red_delta_comb=$signed({1'b0,rgb_in_s0[23:16]})-$signed({1'b0,previous_rgb[23:16]});
    green_delta_comb=$signed({1'b0,rgb_in_s0[15:8]})-$signed({1'b0,previous_rgb[15:8]});
    blue_delta_comb=$signed({1'b0,rgb_in_s0[7:0]})-$signed({1'b0,previous_rgb[7:0]});
    if(!de_s0||(x_s0==0)) begin red_delta_comb=0; green_delta_comb=0; blue_delta_comb=0; end
    case(sharpness_setting)
        0:begin red_delta_comb=0;green_delta_comb=0;blue_delta_comb=0;end
        1:begin red_delta_comb=red_delta_comb>>>2;green_delta_comb=green_delta_comb>>>2;blue_delta_comb=blue_delta_comb>>>2;end
        2:begin red_delta_comb=red_delta_comb>>>1;green_delta_comb=green_delta_comb>>>1;blue_delta_comb=blue_delta_comb>>>1;end
        default:;
    endcase
    red_work_comb=decoded_gain($signed({1'b0,red_base_s1})+red_delta_s1-13'sd128,contrast_config_s1)+13'sd128+brightness_offset_s1;
    green_work_comb=decoded_gain($signed({1'b0,green_base_s1})+green_delta_s1-13'sd128,contrast_config_s1)+13'sd128+brightness_offset_s1;
    blue_work_comb=decoded_gain($signed({1'b0,blue_base_s1})+blue_delta_s1-13'sd128,contrast_config_s1)+13'sd128+brightness_offset_s1;
end

always @(posedge clk or posedge rst) begin
    if(rst) begin
        previous_rgb<=0; rgb_in_s0<=0; de_s0<=0; x_s0<=0;
        red_delta_s1<=0; green_delta_s1<=0; blue_delta_s1<=0;
        red_base_s1<=0; green_base_s1<=0; blue_base_s1<=0;
        brightness_offset_s1<=0;contrast_config_s1<=gain_config(4'd4,1'b0);
        saturation_config_s2<=gain_config(4'd4,1'b1);
        red_work_s1<=0; green_work_s1<=0; blue_work_s1<=0;
        red_pre_s2<=0; green_pre_s2<=0; blue_pre_s2<=0; luma_s2<=0; rgb_out<=0;
        red_sat_delta_s3<=0; green_sat_delta_s3<=0; blue_sat_delta_s3<=0;
        saturation_config_s3<=gain_config(4'd4,1'b1); luma_s3<=0; luma_s4<=0;
        red_product_s4<=0; green_product_s4<=0; blue_product_s4<=0;
        saturation_bias_s4<=0; red_carry_s4<=0; green_carry_s4<=0; blue_carry_s4<=0;
        red_sat_s5<=0; green_sat_s5<=0; blue_sat_s5<=0;
    end else begin
        rgb_in_s0<=rgb_in; de_s0<=de; x_s0<=x;
        brightness_offset_s1<=brightness_offset_comb;
        contrast_config_s1<=gain_config(contrast_setting,1'b0);
        saturation_config_s2<=gain_config(saturation_setting,1'b1);
        if(de_s0) previous_rgb<=rgb_in_s0;
        red_delta_s1<=red_delta_comb; green_delta_s1<=green_delta_comb; blue_delta_s1<=blue_delta_comb;
        red_base_s1<=rgb_in_s0[23:16]; green_base_s1<=rgb_in_s0[15:8]; blue_base_s1<=rgb_in_s0[7:0];
        red_work_s1<=red_work_comb; green_work_s1<=green_work_comb; blue_work_s1<=blue_work_comb;
        red_pre_s2<=red_pre_wire; green_pre_s2<=green_pre_wire; blue_pre_s2<=blue_pre_wire; luma_s2<=luma_wire;
        red_sat_delta_s3<=$signed({1'b0,red_pre_s2})-luma_s2;
        green_sat_delta_s3<=$signed({1'b0,green_pre_s2})-luma_s2;
        blue_sat_delta_s3<=$signed({1'b0,blue_pre_s2})-luma_s2;
        luma_s3<=luma_s2; saturation_config_s3<=saturation_config_s2;
        red_product_s4<=red_sat_delta_s3*$signed({1'b0,saturation_config_s3[10:6]});
        green_product_s4<=green_sat_delta_s3*$signed({1'b0,saturation_config_s3[10:6]});
        blue_product_s4<=blue_sat_delta_s3*$signed({1'b0,saturation_config_s3[10:6]});
        luma_s4<=luma_s3; saturation_bias_s4<=saturation_config_s3[5:2];
        red_carry_s4<=gain_carry(red_sat_delta_s3,saturation_config_s3[1:0]);
        green_carry_s4<=gain_carry(green_sat_delta_s3,saturation_config_s3[1:0]);
        blue_carry_s4<=gain_carry(blue_sat_delta_s3,saturation_config_s3[1:0]);
        red_sat_s5<=finish_saturation(red_product_s4,saturation_bias_s4,red_carry_s4,luma_s4);
        green_sat_s5<=finish_saturation(green_product_s4,saturation_bias_s4,green_carry_s4,luma_s4);
        blue_sat_s5<=finish_saturation(blue_product_s4,saturation_bias_s4,blue_carry_s4,luma_s4);
        rgb_out<={clamp_pipe(red_sat_s5),clamp_pipe(green_sat_s5),clamp_pipe(blue_sat_s5)};
    end
end
endmodule

module saixian_picture_adjust(
    input  wire        clk,
    input  wire        rst,
    input  wire        de,
    input  wire [9:0]  x,
    input  wire [23:0] rgb_in,
    input  wire [3:0]  brightness_setting,
    input  wire [3:0]  contrast_setting,
    input  wire [3:0]  saturation_setting,
    input  wire [1:0]  sharpness_setting,
    output reg  [23:0] rgb_out
);
reg [23:0] previous_rgb;
reg signed [12:0] red_work, green_work, blue_work;
reg signed [11:0] red_delta, green_delta, blue_delta;
reg signed [10:0] brightness_offset;
reg [7:0] red_pre, green_pre, blue_pre;
reg signed [12:0] luma_work;
reg signed [12:0] red_sat, green_sat, blue_sat;

function signed [12:0] contrast_scale;
    input signed [12:0] value;
    input [3:0] level;
    begin
        case (level)
            4'd0: contrast_scale = value >>> 1;
            4'd1: contrast_scale = (value >>> 1) + (value >>> 3);
            4'd2: contrast_scale = (value >>> 1) + (value >>> 2);
            4'd3: contrast_scale = value - (value >>> 3);
            4'd4: contrast_scale = value;
            4'd5: contrast_scale = value + (value >>> 3);
            4'd6: contrast_scale = value + (value >>> 2);
            4'd7: contrast_scale = value + (value >>> 1);
            default: contrast_scale = value + (value >>> 1) + (value >>> 2);
        endcase
    end
endfunction

function signed [12:0] saturation_scale;
    input signed [12:0] value;
    input [3:0] level;
    begin
        case (level)
            4'd0: saturation_scale = 13'sd0;
            4'd1: saturation_scale = value >>> 2;
            4'd2: saturation_scale = value >>> 1;
            4'd3: saturation_scale = value - (value >>> 2);
            4'd4: saturation_scale = value;
            4'd5: saturation_scale = value + (value >>> 3);
            4'd6: saturation_scale = value + (value >>> 2);
            4'd7: saturation_scale = value + (value >>> 1);
            default: saturation_scale = value + (value >>> 1) + (value >>> 2);
        endcase
    end
endfunction

function [7:0] clamp_channel;
    input signed [12:0] value;
    begin
        if (value < 0)
            clamp_channel = 8'd0;
        else if (value > 13'sd255)
            clamp_channel = 8'd255;
        else
            clamp_channel = value[7:0];
    end
endfunction

always @(posedge clk or posedge rst) begin
    if (rst)
        previous_rgb <= 24'd0;
    else if (de)
        previous_rgb <= rgb_in;
end

always @* begin
    case (brightness_setting)
        4'd0: brightness_offset = -11'sd64;
        4'd1: brightness_offset = -11'sd48;
        4'd2: brightness_offset = -11'sd32;
        4'd3: brightness_offset = -11'sd16;
        4'd4: brightness_offset =  11'sd0;
        4'd5: brightness_offset =  11'sd16;
        4'd6: brightness_offset =  11'sd32;
        4'd7: brightness_offset =  11'sd48;
        default: brightness_offset = 11'sd64;
    endcase

    red_delta   = $signed({1'b0,rgb_in[23:16]}) - $signed({1'b0,previous_rgb[23:16]});
    green_delta = $signed({1'b0,rgb_in[15:8]})  - $signed({1'b0,previous_rgb[15:8]});
    blue_delta  = $signed({1'b0,rgb_in[7:0]})   - $signed({1'b0,previous_rgb[7:0]});
    if (!de || (x == 0)) begin
        red_delta = 0; green_delta = 0; blue_delta = 0;
    end

    case (sharpness_setting)
        2'd0: begin red_delta = 0; green_delta = 0; blue_delta = 0; end
        2'd1: begin red_delta = red_delta >>> 2; green_delta = green_delta >>> 2; blue_delta = blue_delta >>> 2; end
        2'd2: begin red_delta = red_delta >>> 1; green_delta = green_delta >>> 1; blue_delta = blue_delta >>> 1; end
        default: ;
    endcase

    red_work   = contrast_scale($signed({1'b0,rgb_in[23:16]}) + red_delta - 13'sd128, contrast_setting)
                 + 13'sd128 + brightness_offset;
    green_work = contrast_scale($signed({1'b0,rgb_in[15:8]}) + green_delta - 13'sd128, contrast_setting)
                 + 13'sd128 + brightness_offset;
    blue_work  = contrast_scale($signed({1'b0,rgb_in[7:0]}) + blue_delta - 13'sd128, contrast_setting)
                 + 13'sd128 + brightness_offset;
    red_pre   = clamp_channel(red_work);
    green_pre = clamp_channel(green_work);
    blue_pre  = clamp_channel(blue_work);
    luma_work = ($signed({1'b0,red_pre}) + ($signed({1'b0,green_pre}) <<< 1)
                 + $signed({1'b0,blue_pre})) >>> 2;
    red_sat   = luma_work + saturation_scale($signed({1'b0,red_pre}) - luma_work, saturation_setting);
    green_sat = luma_work + saturation_scale($signed({1'b0,green_pre}) - luma_work, saturation_setting);
    blue_sat  = luma_work + saturation_scale($signed({1'b0,blue_pre}) - luma_work, saturation_setting);
    rgb_out = {clamp_channel(red_sat),clamp_channel(green_sat),clamp_channel(blue_sat)};
end
endmodule

module saixian_hmi_color_style(
    input wire [23:0] rgb_in,
    input wire invert, vintage,
    output wire [23:0] rgb_out
);
wire [9:0] luma_sum={2'b0,rgb_in[23:16]}+
                    {1'b0,rgb_in[15:8],1'b0}+{2'b0,rgb_in[7:0]};
wire [7:0] luma=luma_sum[9:2];
wire [7:0] warm_r=(luma>8'd223) ? 8'd255 : luma+8'd32;
wire [7:0] warm_b=luma-(luma>>2);
wire [23:0] warm=vintage ? {warm_r,luma,warm_b} : rgb_in;
assign rgb_out=invert ? ~warm : warm;
endmodule

module saixian_hmi_status_tx #(
    parameter integer CLK_FREQ_HZ = 75_000_000,
    parameter integer BAUD_RATE = 115_200,
    parameter integer ENHANCEMENT_FEEDBACK = 0,
    parameter integer BYTE_STREAM = 0
)(
    input wire clk, rst,
    input wire [2:0] image_count,
    input wire [2:0] audio_count,
    input wire [2:0] error_code,
    input wire initializing,
    input wire [2:0] page_id,
    input wire refresh_request,
    input wire [1:0] sharpness,
    input wire [3:0] brightness, contrast, saturation, volume,
    input wire invert, vintage,
    input wire [1:0] enhancement,
    input wire [3:0] event_state,
    input wire [6:0] minutes,
    input wire [5:0] seconds,
    output reg uart_tx,
    output reg command_sent_pulse,
    output wire byte_valid, output wire [7:0] byte_data, input wire byte_ready
);
localparam integer CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;
localparam [1:0] TX_IDLE=0, TX_START=1, TX_DATA=2, TX_STOP=3;
reg [1:0] tx_state;
reg [4:0] next_field;
reg [2:0] active_page;
localparam integer REFRESH_COUNT_BITS = CLK_FREQ_HZ/4>1 ? $clog2(CLK_FREQ_HZ/4):1;
reg [REFRESH_COUNT_BITS-1:0] refresh_count;
reg [15:0] baud_count;
reg [4:0] message_id, prepared_id;
reg [7:0] command_rom [0:1023];
reg [7:0] prefix_byte;
integer rom_index;
reg [47:0] message_suffix, prepared_suffix;
reg [4:0] prefix_length;
reg [2:0] suffix_length;
reg [5:0] message_len, prepared_len, byte_index;
wire [4:0] next_byte_index=byte_index[4:0]+5'd1;
reg [2:0] bit_index;
reg [7:0] shift_byte;
assign byte_valid=BYTE_STREAM && tx_state==TX_DATA;
assign byte_data=shift_byte;
reg [6:0] minutes_snapshot;
reg [5:0] seconds_snapshot;
reg [3:0] state_snapshot;
reg [4:0] field_count;
reg refresh_pending;
reg [21:0] settings_seen;
wire [1:0] feedback_enhancement=ENHANCEMENT_FEEDBACK ? enhancement:2'd0;
wire [21:0] settings_live={feedback_enhancement,sharpness,brightness,contrast,saturation,volume,invert,vintage};
reg [7:0] value;
integer prefix_len;

// Fixed ASCII prefixes use one synchronous block ROM instead of wide muxes.
initial begin
    for(rom_index=0;rom_index<1024;rom_index=rom_index+1) command_rom[rom_index]=8'h00;
    command_rom[0]=8'h73;
    command_rom[1]=8'h65;
    command_rom[2]=8'h74;
    command_rom[3]=8'h74;
    command_rom[4]=8'h69;
    command_rom[5]=8'h6e;
    command_rom[6]=8'h67;
    command_rom[7]=8'h73;
    command_rom[8]=8'h2e;
    command_rom[9]=8'h68;
    command_rom[10]=8'h5f;
    command_rom[11]=8'h73;
    command_rom[12]=8'h68;
    command_rom[13]=8'h61;
    command_rom[14]=8'h72;
    command_rom[15]=8'h70;
    command_rom[16]=8'h2e;
    command_rom[17]=8'h76;
    command_rom[18]=8'h61;
    command_rom[19]=8'h6c;
    command_rom[20]=8'h3d;
    command_rom[32]=8'h73;
    command_rom[33]=8'h65;
    command_rom[34]=8'h74;
    command_rom[35]=8'h74;
    command_rom[36]=8'h69;
    command_rom[37]=8'h6e;
    command_rom[38]=8'h67;
    command_rom[39]=8'h73;
    command_rom[40]=8'h2e;
    command_rom[41]=8'h6e;
    command_rom[42]=8'h5f;
    command_rom[43]=8'h73;
    command_rom[44]=8'h68;
    command_rom[45]=8'h61;
    command_rom[46]=8'h72;
    command_rom[47]=8'h70;
    command_rom[48]=8'h2e;
    command_rom[49]=8'h76;
    command_rom[50]=8'h61;
    command_rom[51]=8'h6c;
    command_rom[52]=8'h3d;
    command_rom[64]=8'h73;
    command_rom[65]=8'h65;
    command_rom[66]=8'h74;
    command_rom[67]=8'h74;
    command_rom[68]=8'h69;
    command_rom[69]=8'h6e;
    command_rom[70]=8'h67;
    command_rom[71]=8'h73;
    command_rom[72]=8'h2e;
    command_rom[73]=8'h68;
    command_rom[74]=8'h5f;
    command_rom[75]=8'h62;
    command_rom[76]=8'h72;
    command_rom[77]=8'h69;
    command_rom[78]=8'h67;
    command_rom[79]=8'h68;
    command_rom[80]=8'h74;
    command_rom[81]=8'h2e;
    command_rom[82]=8'h76;
    command_rom[83]=8'h61;
    command_rom[84]=8'h6c;
    command_rom[85]=8'h3d;
    command_rom[96]=8'h73;
    command_rom[97]=8'h65;
    command_rom[98]=8'h74;
    command_rom[99]=8'h74;
    command_rom[100]=8'h69;
    command_rom[101]=8'h6e;
    command_rom[102]=8'h67;
    command_rom[103]=8'h73;
    command_rom[104]=8'h2e;
    command_rom[105]=8'h6e;
    command_rom[106]=8'h5f;
    command_rom[107]=8'h62;
    command_rom[108]=8'h72;
    command_rom[109]=8'h69;
    command_rom[110]=8'h67;
    command_rom[111]=8'h68;
    command_rom[112]=8'h74;
    command_rom[113]=8'h2e;
    command_rom[114]=8'h76;
    command_rom[115]=8'h61;
    command_rom[116]=8'h6c;
    command_rom[117]=8'h3d;
    command_rom[128]=8'h73;
    command_rom[129]=8'h65;
    command_rom[130]=8'h74;
    command_rom[131]=8'h74;
    command_rom[132]=8'h69;
    command_rom[133]=8'h6e;
    command_rom[134]=8'h67;
    command_rom[135]=8'h73;
    command_rom[136]=8'h2e;
    command_rom[137]=8'h68;
    command_rom[138]=8'h5f;
    command_rom[139]=8'h63;
    command_rom[140]=8'h6f;
    command_rom[141]=8'h6e;
    command_rom[142]=8'h74;
    command_rom[143]=8'h72;
    command_rom[144]=8'h61;
    command_rom[145]=8'h73;
    command_rom[146]=8'h74;
    command_rom[147]=8'h2e;
    command_rom[148]=8'h76;
    command_rom[149]=8'h61;
    command_rom[150]=8'h6c;
    command_rom[151]=8'h3d;
    command_rom[160]=8'h73;
    command_rom[161]=8'h65;
    command_rom[162]=8'h74;
    command_rom[163]=8'h74;
    command_rom[164]=8'h69;
    command_rom[165]=8'h6e;
    command_rom[166]=8'h67;
    command_rom[167]=8'h73;
    command_rom[168]=8'h2e;
    command_rom[169]=8'h6e;
    command_rom[170]=8'h5f;
    command_rom[171]=8'h63;
    command_rom[172]=8'h6f;
    command_rom[173]=8'h6e;
    command_rom[174]=8'h74;
    command_rom[175]=8'h72;
    command_rom[176]=8'h61;
    command_rom[177]=8'h73;
    command_rom[178]=8'h74;
    command_rom[179]=8'h2e;
    command_rom[180]=8'h76;
    command_rom[181]=8'h61;
    command_rom[182]=8'h6c;
    command_rom[183]=8'h3d;
    command_rom[192]=8'h73;
    command_rom[193]=8'h65;
    command_rom[194]=8'h74;
    command_rom[195]=8'h74;
    command_rom[196]=8'h69;
    command_rom[197]=8'h6e;
    command_rom[198]=8'h67;
    command_rom[199]=8'h73;
    command_rom[200]=8'h2e;
    command_rom[201]=8'h68;
    command_rom[202]=8'h5f;
    command_rom[203]=8'h73;
    command_rom[204]=8'h61;
    command_rom[205]=8'h74;
    command_rom[206]=8'h75;
    command_rom[207]=8'h72;
    command_rom[208]=8'h61;
    command_rom[209]=8'h74;
    command_rom[210]=8'h69;
    command_rom[211]=8'h6f;
    command_rom[212]=8'h6e;
    command_rom[213]=8'h2e;
    command_rom[214]=8'h76;
    command_rom[215]=8'h61;
    command_rom[216]=8'h6c;
    command_rom[217]=8'h3d;
    command_rom[224]=8'h73;
    command_rom[225]=8'h65;
    command_rom[226]=8'h74;
    command_rom[227]=8'h74;
    command_rom[228]=8'h69;
    command_rom[229]=8'h6e;
    command_rom[230]=8'h67;
    command_rom[231]=8'h73;
    command_rom[232]=8'h2e;
    command_rom[233]=8'h6e;
    command_rom[234]=8'h5f;
    command_rom[235]=8'h73;
    command_rom[236]=8'h61;
    command_rom[237]=8'h74;
    command_rom[238]=8'h75;
    command_rom[239]=8'h72;
    command_rom[240]=8'h61;
    command_rom[241]=8'h74;
    command_rom[242]=8'h69;
    command_rom[243]=8'h6f;
    command_rom[244]=8'h6e;
    command_rom[245]=8'h2e;
    command_rom[246]=8'h76;
    command_rom[247]=8'h61;
    command_rom[248]=8'h6c;
    command_rom[249]=8'h3d;
    command_rom[256]=8'h73;
    command_rom[257]=8'h65;
    command_rom[258]=8'h74;
    command_rom[259]=8'h74;
    command_rom[260]=8'h69;
    command_rom[261]=8'h6e;
    command_rom[262]=8'h67;
    command_rom[263]=8'h73;
    command_rom[264]=8'h2e;
    command_rom[265]=8'h68;
    command_rom[266]=8'h5f;
    command_rom[267]=8'h76;
    command_rom[268]=8'h6f;
    command_rom[269]=8'h6c;
    command_rom[270]=8'h75;
    command_rom[271]=8'h6d;
    command_rom[272]=8'h65;
    command_rom[273]=8'h2e;
    command_rom[274]=8'h76;
    command_rom[275]=8'h61;
    command_rom[276]=8'h6c;
    command_rom[277]=8'h3d;
    command_rom[288]=8'h73;
    command_rom[289]=8'h65;
    command_rom[290]=8'h74;
    command_rom[291]=8'h74;
    command_rom[292]=8'h69;
    command_rom[293]=8'h6e;
    command_rom[294]=8'h67;
    command_rom[295]=8'h73;
    command_rom[296]=8'h2e;
    command_rom[297]=8'h6e;
    command_rom[298]=8'h5f;
    command_rom[299]=8'h76;
    command_rom[300]=8'h6f;
    command_rom[301]=8'h6c;
    command_rom[302]=8'h75;
    command_rom[303]=8'h6d;
    command_rom[304]=8'h65;
    command_rom[305]=8'h2e;
    command_rom[306]=8'h76;
    command_rom[307]=8'h61;
    command_rom[308]=8'h6c;
    command_rom[309]=8'h3d;
    command_rom[320]=8'h73;
    command_rom[321]=8'h65;
    command_rom[322]=8'h74;
    command_rom[323]=8'h74;
    command_rom[324]=8'h69;
    command_rom[325]=8'h6e;
    command_rom[326]=8'h67;
    command_rom[327]=8'h73;
    command_rom[328]=8'h2e;
    command_rom[329]=8'h62;
    command_rom[330]=8'h74;
    command_rom[331]=8'h5f;
    command_rom[332]=8'h69;
    command_rom[333]=8'h6e;
    command_rom[334]=8'h76;
    command_rom[335]=8'h65;
    command_rom[336]=8'h72;
    command_rom[337]=8'h74;
    command_rom[338]=8'h2e;
    command_rom[339]=8'h76;
    command_rom[340]=8'h61;
    command_rom[341]=8'h6c;
    command_rom[342]=8'h3d;
    command_rom[352]=8'h73;
    command_rom[353]=8'h65;
    command_rom[354]=8'h74;
    command_rom[355]=8'h74;
    command_rom[356]=8'h69;
    command_rom[357]=8'h6e;
    command_rom[358]=8'h67;
    command_rom[359]=8'h73;
    command_rom[360]=8'h2e;
    command_rom[361]=8'h62;
    command_rom[362]=8'h74;
    command_rom[363]=8'h5f;
    command_rom[364]=8'h76;
    command_rom[365]=8'h69;
    command_rom[366]=8'h6e;
    command_rom[367]=8'h74;
    command_rom[368]=8'h61;
    command_rom[369]=8'h67;
    command_rom[370]=8'h65;
    command_rom[371]=8'h2e;
    command_rom[372]=8'h76;
    command_rom[373]=8'h61;
    command_rom[374]=8'h6c;
    command_rom[375]=8'h3d;
    command_rom[384]=8'h67;
    command_rom[385]=8'h61;
    command_rom[386]=8'h6d;
    command_rom[387]=8'h65;
    command_rom[388]=8'h2e;
    command_rom[389]=8'h74;
    command_rom[390]=8'h34;
    command_rom[391]=8'h2e;
    command_rom[392]=8'h74;
    command_rom[393]=8'h78;
    command_rom[394]=8'h74;
    command_rom[395]=8'h3d;
    command_rom[396]=8'h22;
    command_rom[416]=8'h67;
    command_rom[417]=8'h61;
    command_rom[418]=8'h6d;
    command_rom[419]=8'h65;
    command_rom[420]=8'h2e;
    command_rom[421]=8'h74;
    command_rom[422]=8'h33;
    command_rom[423]=8'h2e;
    command_rom[424]=8'h74;
    command_rom[425]=8'h78;
    command_rom[426]=8'h74;
    command_rom[427]=8'h3d;
    command_rom[428]=8'h22;
    command_rom[448]=8'h67;
    command_rom[449]=8'h61;
    command_rom[450]=8'h6d;
    command_rom[451]=8'h65;
    command_rom[452]=8'h2e;
    command_rom[453]=8'h6e;
    command_rom[454]=8'h5f;
    command_rom[455]=8'h73;
    command_rom[456]=8'h74;
    command_rom[457]=8'h61;
    command_rom[458]=8'h74;
    command_rom[459]=8'h65;
    command_rom[460]=8'h2e;
    command_rom[461]=8'h76;
    command_rom[462]=8'h61;
    command_rom[463]=8'h6c;
    command_rom[464]=8'h3d;
    command_rom[480]=8'h68;
    command_rom[481]=8'h6f;
    command_rom[482]=8'h6d;
    command_rom[483]=8'h65;
    command_rom[484]=8'h2e;
    command_rom[485]=8'h74;
    command_rom[486]=8'h5f;
    command_rom[487]=8'h70;
    command_rom[488]=8'h2e;
    command_rom[489]=8'h74;
    command_rom[490]=8'h78;
    command_rom[491]=8'h74;
    command_rom[492]=8'h3d;
    command_rom[493]=8'h22;
    command_rom[512]=8'h68;
    command_rom[513]=8'h6f;
    command_rom[514]=8'h6d;
    command_rom[515]=8'h65;
    command_rom[516]=8'h2e;
    command_rom[517]=8'h74;
    command_rom[518]=8'h5f;
    command_rom[519]=8'h6d;
    command_rom[520]=8'h2e;
    command_rom[521]=8'h74;
    command_rom[522]=8'h78;
    command_rom[523]=8'h74;
    command_rom[524]=8'h3d;
    command_rom[525]=8'h22;
    command_rom[544]=8'h68;
    command_rom[545]=8'h6f;
    command_rom[546]=8'h6d;
    command_rom[547]=8'h65;
    command_rom[548]=8'h2e;
    command_rom[549]=8'h74;
    command_rom[550]=8'h5f;
    command_rom[551]=8'h65;
    command_rom[552]=8'h2e;
    command_rom[553]=8'h74;
    command_rom[554]=8'h78;
    command_rom[555]=8'h74;
    command_rom[556]=8'h3d;
    command_rom[557]=8'h22;
    command_rom[576]=8'h73;
    command_rom[577]=8'h65;
    command_rom[578]=8'h74;
    command_rom[579]=8'h74;
    command_rom[580]=8'h69;
    command_rom[581]=8'h6e;
    command_rom[582]=8'h67;
    command_rom[583]=8'h73;
    command_rom[584]=8'h2e;
    command_rom[585]=8'h68;
    command_rom[586]=8'h5f;
    command_rom[587]=8'h65;
    command_rom[588]=8'h6e;
    command_rom[589]=8'h68;
    command_rom[590]=8'h61;
    command_rom[591]=8'h6e;
    command_rom[592]=8'h63;
    command_rom[593]=8'h65;
    command_rom[594]=8'h2e;
    command_rom[595]=8'h76;
    command_rom[596]=8'h61;
    command_rom[597]=8'h6c;
    command_rom[598]=8'h3d;
    command_rom[608]=8'h73;
    command_rom[609]=8'h65;
    command_rom[610]=8'h74;
    command_rom[611]=8'h74;
    command_rom[612]=8'h69;
    command_rom[613]=8'h6e;
    command_rom[614]=8'h67;
    command_rom[615]=8'h73;
    command_rom[616]=8'h2e;
    command_rom[617]=8'h6e;
    command_rom[618]=8'h5f;
    command_rom[619]=8'h65;
    command_rom[620]=8'h6e;
    command_rom[621]=8'h68;
    command_rom[622]=8'h61;
    command_rom[623]=8'h6e;
    command_rom[624]=8'h63;
    command_rom[625]=8'h65;
    command_rom[626]=8'h2e;
    command_rom[627]=8'h76;
    command_rom[628]=8'h61;
    command_rom[629]=8'h6c;
    command_rom[630]=8'h3d;
end
always @(posedge clk) prefix_byte<=command_rom[{message_id,next_byte_index}];

// Reverse mapping chooses a stable representative of the FPGA's 0..8 levels.
function [7:0] percent;
    input [3:0] level;
    begin
        case(level)
            0:percent=0; 1:percent=13; 2:percent=25; 3:percent=38;
            4:percent=50; 5:percent=63; 6:percent=75; 7:percent=88;
            default:percent=100;
        endcase
    end
endfunction

// Format a constant prefix and short numeric suffix separately.
// Numeric settings always use three decimal digits (000..100).
always @* begin
    prepared_suffix=0; prepared_len=0; prepared_id=0; prefix_len=0; value=0;
    field_count=3;
    case(active_page)
        3'd1: begin
            field_count=ENHANCEMENT_FEEDBACK ? 14:12;
            case(next_field)
                0:begin prepared_id=5'd0;prefix_len=21;value={6'd0,sharpness};end
                1:begin prepared_id=5'd1;prefix_len=21;value={6'd0,sharpness};end
                2:begin prepared_id=5'd2;prefix_len=22;value=percent(brightness);end
                3:begin prepared_id=5'd3;prefix_len=22;value=percent(brightness);end
                4:begin prepared_id=5'd4;prefix_len=24;value=percent(contrast);end
                5:begin prepared_id=5'd5;prefix_len=24;value=percent(contrast);end
                6:begin prepared_id=5'd6;prefix_len=26;value=percent(saturation);end
                7:begin prepared_id=5'd7;prefix_len=26;value=percent(saturation);end
                8:begin prepared_id=5'd8;prefix_len=22;value=percent(volume);end
                9:begin prepared_id=5'd9;prefix_len=22;value=percent(volume);end
                10:begin prepared_id=5'd10;prefix_len=23;value={7'd0,invert};end
                11:begin prepared_id=5'd11;prefix_len=24;value={7'd0,vintage};end
                12:begin prepared_id=5'd18;prefix_len=23;value={6'd0,enhancement};end
                default:begin prepared_id=5'd19;prefix_len=23;value={6'd0,enhancement};end
            endcase
        end
        3'd2: begin
            field_count=3;
            case(next_field)
                0:begin prepared_id=5'd12;prefix_len=13;end
                1:begin prepared_id=5'd13;prefix_len=13;end
                default:begin prepared_id=5'd14;prefix_len=17;value={4'd0,state_snapshot};end
            endcase
        end
        3'd0: begin
            case(next_field)
                0:begin prepared_id=5'd15;prefix_len=14;end
                1:begin prepared_id=5'd16;prefix_len=14;end
                default:begin prepared_id=5'd17;prefix_len=14;end
            endcase
        end
        default:field_count=0; // settlement/keyboard pages have no telemetry targets
    endcase
    prepared_len=prefix_len;
    if(active_page==1 || (active_page==2 && next_field==2)) begin
        prepared_suffix={8'h30+value/8'd100,
            8'h30+(value/8'd10)%8'd10,8'h30+value%8'd10,24'd0};
        prepared_len=prefix_len+3;
    end else if(active_page==2) begin
        prepared_suffix={8'h30+{1'b0,minutes_snapshot}/8'd10,
            8'h30+{1'b0,minutes_snapshot}%8'd10,8'h3a,
            8'h30+{2'd0,seconds_snapshot}/8'd10,8'h30+{2'd0,seconds_snapshot}%8'd10,8'h22};
        prepared_len=prefix_len+6;
    end else if(active_page==0) begin
        case(next_field)
            0:begin
                prepared_suffix={8'h30+{5'd0,image_count},8'h22,32'd0};
                prepared_len=prefix_len+2;
            end
            1:begin
                prepared_suffix={{5'b00110,audio_count},8'h22,32'd0};
                prepared_len=prefix_len+2;
            end
            default:begin
                prepared_suffix={
                    error_code==0?(initializing?8'h49:8'h4f):8'h45,
                    error_code==0?(initializing?8'h4e:8'h4b):(8'h30+{5'd0,error_code}),8'h22,24'd0};
                prepared_len=prefix_len+3;
            end
        endcase
    end
    prepared_len=prepared_len+3;
end

always @(posedge clk or posedge rst) begin
    if(rst) begin
        uart_tx<=1;command_sent_pulse<=0;tx_state<=TX_IDLE;
        active_page<=0;next_field<=0;refresh_count<=0;
        baud_count<=0;message_id<=0;message_suffix<=0;prefix_length<=0;suffix_length<=0;message_len<=0;byte_index<=0;
        bit_index<=0;shift_byte<=0;
        minutes_snapshot<=0;seconds_snapshot<=0;state_snapshot<=0;
        refresh_pending<=0;settings_seen<=0;
    end else begin
        command_sent_pulse<=0;
        settings_seen<=settings_live;
        if(refresh_request || settings_seen!=settings_live) refresh_pending<=1;
        if(refresh_count>=CLK_FREQ_HZ/4-1) refresh_count<=0;
        else refresh_count<=refresh_count+1'b1;
        case(tx_state)
            TX_IDLE: begin
                // Page changes cannot cut a command in half. Reload at next idle.
                if(page_id<=4 && active_page!=page_id) begin
                    active_page<=page_id;next_field<=0;refresh_pending<=0;
                    minutes_snapshot<=minutes;seconds_snapshot<=seconds;state_snapshot<=event_state;
                end else if(next_field<field_count) begin
                    message_id<=prepared_id;message_suffix<=prepared_suffix;
                    prefix_length<=prefix_len;suffix_length<=prepared_len-prefix_len-3;message_len<=prepared_len;
                    next_field<=next_field+1'b1;byte_index<=0;
                    shift_byte<=(active_page==1 ? 8'h73 : active_page==2 ? 8'h67 : 8'h68);bit_index<=0;
                    baud_count<=0;uart_tx<=BYTE_STREAM ? 1'b1:1'b0;tx_state<=TX_START;
                end else if(refresh_pending || (refresh_count==0 && active_page!=1)) begin
                    refresh_pending<=0;
                    next_field<=0;
                    minutes_snapshot<=minutes;seconds_snapshot<=seconds;state_snapshot<=event_state;
                end
            end
            TX_START: if(BYTE_STREAM) tx_state<=TX_DATA;
            else if(baud_count==CLKS_PER_BIT-1) begin
                baud_count<=0;uart_tx<=shift_byte[0];shift_byte<=shift_byte>>1;
                bit_index<=0;tx_state<=TX_DATA;
            end else baud_count<=baud_count+1'b1;
            TX_DATA: if(BYTE_STREAM) begin
                if(byte_ready) begin
                    if(byte_index+1'b1<message_len) begin
                        if(byte_index+1'b1<prefix_length) shift_byte<=prefix_byte;
                        else if(byte_index+1'b1<prefix_length+suffix_length)
                            begin shift_byte<=message_suffix[47:40];message_suffix<={message_suffix[39:0],8'd0};end
                        else shift_byte<=8'hff;
                        byte_index<=byte_index+1'b1;tx_state<=TX_START;
                    end else begin command_sent_pulse<=1;tx_state<=TX_IDLE;end
                end
            end else if(baud_count==CLKS_PER_BIT-1) begin
                baud_count<=0;
                if(bit_index==7) begin uart_tx<=1;tx_state<=TX_STOP;end
                else begin uart_tx<=shift_byte[0];shift_byte<=shift_byte>>1;bit_index<=bit_index+1'b1;end
            end else baud_count<=baud_count+1'b1;
            TX_STOP: if(baud_count==CLKS_PER_BIT-1) begin
                baud_count<=0;
                if(byte_index+1'b1<message_len) begin
                    if(byte_index+1'b1<prefix_length)
                        shift_byte<=prefix_byte;
                    else if(byte_index+1'b1<prefix_length+suffix_length)
                        begin shift_byte<=message_suffix[47:40];message_suffix<={message_suffix[39:0],8'd0};end
                    else shift_byte<=8'hff;
                    byte_index<=byte_index+1'b1;uart_tx<=0;tx_state<=TX_START;
                end else begin uart_tx<=1;command_sent_pulse<=1;tx_state<=TX_IDLE;end
            end else baud_count<=baud_count+1'b1;
            default:tx_state<=TX_IDLE;
        endcase
    end
end
endmodule
