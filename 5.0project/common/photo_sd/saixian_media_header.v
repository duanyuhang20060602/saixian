// Streaming predicates retain every header byte relevant to acceptance.
// Fields used only in equality/range tests are not stored as wide integers.
// Wide sector/length arithmetic and the complete low 16 geometry bits remain.
module saixian_media_header(
    input clk, rst, valid, scan_audio,
    input [5:0] index,
    input [7:0] data,
    output reg bmp_b, bmp_m, dib_ok, planes_ok, bits24_ok, compression_zero,
    output reg sprint_x_ok, sprint_y_ok,
    output reg audio_magic_ok, rate_ok, bits16_ok, stereo_ok,
    output reg [31:0] file_len, pixel_offset, audio_data_len,
    output [31:0] width, height
);
reg [15:0] width_low, height_low;
reg width_high_zero, height_high_zero;
// Rejected upper bits need an exact zero/nonzero predicate, not their value.
assign width={width_high_zero ? 16'd0 : 16'hffff,width_low};
assign height={height_high_zero ? 16'd0 : 16'hffff,height_low};
always @(posedge clk or posedge rst) begin
    if(rst) begin
        bmp_b<=0;bmp_m<=0;dib_ok<=0;planes_ok<=0;bits24_ok<=0;
        compression_zero<=1;sprint_x_ok<=0;sprint_y_ok<=0;
        file_len<=0;pixel_offset<=54;width_low<=0;height_low<=0;
        width_high_zero<=1;height_high_zero<=1;
    end else if(valid) begin
        case(index)
             0:bmp_b<=data==8'h42;
             1:bmp_m<=data==8'h4d;
             2:file_len[7:0]<=data;
             3:file_len[15:8]<=data;
             4:file_len[23:16]<=data;
             5:file_len[31:24]<=data;
            10:pixel_offset[7:0]<=data;
            11:pixel_offset[15:8]<=data;
            12:pixel_offset[23:16]<=data;
            13:pixel_offset[31:24]<=data;
            14:dib_ok<=data>=8'd40;
            15,16,17:dib_ok<=dib_ok || data!=0;
            18:width_low[7:0]<=data;
            19:width_low[15:8]<=data;
            20:width_high_zero<=data==0;
            21:width_high_zero<=width_high_zero && data==0;
            22:height_low[7:0]<=data;
            23:height_low[15:8]<=data;
            24:height_high_zero<=data==0;
            25:height_high_zero<=height_high_zero && data==0;
            26:planes_ok<=data==1;
            27:planes_ok<=planes_ok && data==0;
            28:bits24_ok<=data==24;
            29:bits24_ok<=bits24_ok && data==0;
            30:compression_zero<=data==0;
            31,32,33:compression_zero<=compression_zero && data==0;
            38:sprint_x_ok<=data==8'h39;
            39:sprint_x_ok<=sprint_x_ok && data==8'h30;
            40,41:sprint_x_ok<=sprint_x_ok && data==0;
            42:sprint_y_ok<=data==8'h31;
            43:sprint_y_ok<=sprint_y_ok && data==8'hd4;
            44,45:sprint_y_ok<=sprint_y_ok && data==0;
            default:;
        endcase
    end
end
always @(posedge clk or posedge rst) begin
    if(rst) begin
        audio_magic_ok<=0;audio_data_len<=0;rate_ok<=0;bits16_ok<=0;stereo_ok<=0;
    end else if(valid && scan_audio) begin
        case(index)
             0:audio_magic_ok<=data==8'h53;
             1:audio_magic_ok<=audio_magic_ok && data==8'h58;
             2:audio_magic_ok<=audio_magic_ok && data==8'h41;
             3:audio_magic_ok<=audio_magic_ok && data==8'h55;
             4:audio_magic_ok<=audio_magic_ok && data==8'h44;
             5,6:audio_magic_ok<=audio_magic_ok && data==8'h30;
             7:audio_magic_ok<=audio_magic_ok && data==8'h31;
             8:audio_data_len[7:0]<=data;
             9:audio_data_len[15:8]<=data;
            10:audio_data_len[23:16]<=data;
            11:audio_data_len[31:24]<=data;
            12:rate_ok<=data==8'h80;
            13:rate_ok<=rate_ok && data==8'hbb;
            14,15:rate_ok<=rate_ok && data==0;
            16:bits16_ok<=data==16;
            17:bits16_ok<=bits16_ok && data==0;
            18:stereo_ok<=data==2;
            19:stereo_ok<=stereo_ok && data==0;
            default:;
        endcase
    end
end
endmodule
