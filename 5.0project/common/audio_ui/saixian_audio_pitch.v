// 48 kHz stereo time-domain pitch effect. Author-written experimental RTL.
// Mode-specific FIR and full-fraction cubic interpolation share one 21x18 multiplier.
// Filtered stereo retains 4096 frames; the compact 1152-frame dry delay retains 1153.
// Short smooth overlap, with stereo waveform-matched muted-head resets.
// Audio clock remains fixed: source playback speed/duration is unchanged.
module saixian_audio_pitch #(parameter RING_RAM32_LANES=8,COMPACT_DRY=1)(
    input clk,rst,clear,sample_valid,
    input signed [15:0] left_in,right_in,
    input [2:0] requested_mode,
    output reg signed [15:0] left_out,right_out,
    output reg out_valid,
    output wire ready,
    output reg overrun,
    output reg [2:0] active_mode
);
localparam IDLE=0,F_WRITE=1,F_READ=2,F_GET=3,F_WAIT_L=4,F_SET_R=5,
    F_WAIT_R=6,F_ACC=7,R_WRITE=8,R_READ=9,R_WAIT=10,R_GET=11,
    MAC_SET=12,MAC_WAIT=13,MAC_DONE=14,
    C_REF0=15,C_REF1=16,C_REF2=17,C_TGT0=18,C_TGT1=19,C_TGT2=20,
    I_COEFF=21,I_WAIT0=22,I_STEP0=23,I_WAIT1=24,I_STEP1=25,I_WAIT2=26,I_DONE=27,
    C_ABS=28,C_SUM=29,C_SCORE=30,I_SELECT=31,I_PART=32,MAC_CLIP=33,MAC_SELECT=34,C_COMPARE=35,
    F_ROUND=36,F_CLIP=37;
reg [5:0] state;
reg [5:0] fir_head,fir_anchor,tap;
reg [6:0] fir_count;
reg signed [15:0] input_l,input_r,center_l,center_r,filtered_l,filtered_r;
wire [31:0] fir_q;
wire [5:0] fir_read=fir_anchor-tap;
saixian_pitch_fir_ram fir_history(
    .clk(clk),.write_left(state==IDLE && sample_valid && !rst && !clear),
    .write_right(state==F_WRITE && !rst && !clear),.wa(fir_head),.ra(fir_read),
    .read_right(state!=F_READ),.left_data(left_in),.right_data(input_r),.rd(fir_q[15:0]));
assign fir_q[31:16]=fir_q[15:0];
wire signed[15:0] coefficient_q;
saixian_pitch_coeff coefficients(.clk(clk),.address({active_mode,tap}),.value(coefficient_q));
reg signed [20:0] mul_a;reg signed [17:0] mul_b;
reg signed [38:0] product;reg signed[31:0] product_l;
always @(posedge clk) product<=mul_a*mul_b;
reg signed [32:0] accumulator_l,accumulator_r;
wire signed [32:0] fir_total_l=accumulator_l+product_l;
wire signed [32:0] fir_total_r=accumulator_r+$signed(product[31:0]);
reg [11:0] write_index,read_addr;
reg [11:0] fill;
wire [63:0] ring_q;
reg [3:0] read_slot;
generate if(COMPACT_DRY)begin: compact_history
    // Only the final R_GET consumes raw samples. A 1153-frame circular
    // delay holds the current write and the sample exactly 1152 frames old.
    // Independent stereo ports pack its 1024-frame head into one RAM32K;
    // a byte-wide two-clock tail occupies one RAM9K. Filtered history and
    // all correlation/cubic addresses keep their original 4096 frames.
    saixian_pitch_dry_delay dry(.clk(clk),.rst(rst || clear),
        .write_frame(state==R_WRITE && !rst && !clear),
        .read_first(state==R_READ && read_slot==8),
        .read_second(state==R_WAIT && read_slot==8),
        .wd({center_r,center_l}),.rd(ring_q[31:0]));
    saixian_pitch_ram #(.WIDTH(32),.ADDR(12),.CAP_ADDR(11),.RAM_KIND("32K")) filtered(
        .clk(clk),.we(state==R_WRITE && !rst && !clear),.wa(write_index),.ra(read_addr),
        .wd({filtered_r,filtered_l}),.rd(ring_q[63:32]));
end else begin: full_history_reference
    saixian_pitch_ram #(.WIDTH(64),.ADDR(12),.CAP_ADDR(11),.RAM_KIND("32K"),.RAM32_LANES(RING_RAM32_LANES)) ring(
        .clk(clk),.we(state==R_WRITE && !rst && !clear),.wa(write_index),.ra(read_addr),
        .wd({filtered_r,filtered_l,center_r,center_l}),.rd(ring_q));
end endgenerate
reg [26:0] phase;
wire [26:0] phase_b=phase ^ 27'h4000000;
// Smooth piecewise-quadratic 256-sample phase crossfade; plateau elsewhere.
wire [10:0] pi=phase[26:16];
wire [16:0] fade_x={1'b0,phase[23:8]};
wire [16:0] fade_m=fade_x[15] ? 17'd65536-fade_x : fade_x;
reg [33:0] fade_square;
reg [16:0] head_weight;
always @(posedge clk) begin
    fade_square<=fade_m*fade_m;
    if(pi<256) head_weight<=fade_x[15] ? 17'd65536-(fade_square>>15) : fade_square>>15;
    else if(pi<1024) head_weight<=65536;
    else if(pi<1280) head_weight<=fade_x[15] ? fade_square>>15 : 17'd65536-(fade_square>>15);
    else head_weight<=0;
end
// Search one candidate per input transaction, only while its read head is muted.
// Both anchors are frozen: candidates compare the SAME 16 stereo sample pairs.
reg signed [8:0] offset_a,offset_b,best_offset;
reg corr_busy,corr_head,prev_mute_a,prev_mute_b;
reg [7:0] candidate;
reg [3:0] corr_tap;
reg [11:0] anchor_ref,anchor_target;
reg [23:0] corr_score,best_score;
reg signed [15:0] ref_l,ref_r;
wire mute_a=pi>=1280, mute_b=pi>=256 && pi<1024;
reg signed [16:0] dl,dr;
reg [17:0] distance_reg;
reg [23:0] score_total;
reg score_better;
wire [17:0] distance=(dl<0 ? -dl : dl)+(dr<0 ? -dr : dr);
wire [11:0] base_a=write_index-12'd128-{1'b0,phase[26:16]};
wire [11:0] base_b=write_index-12'd128-{1'b0,phase_b[26:16]};
wire [11:0] actual_a=base_a-{{3{offset_a[8]}},offset_a};
wire [11:0] actual_b=base_b-{{3{offset_b[8]}},offset_b};
wire signed [8:0] candidate_offset=$signed({1'b0,candidate})-9'sd64;
wire [11:0] corr_target_addr=anchor_target-{{3{candidate_offset[8]}},candidate_offset}-{6'd0,corr_tap,2'b0};
// One 16x32 distributed RAM replaces eight stereo registers and four
// independent read muxes. Read the cubic points over four idle DSP clocks.
reg [1:0] interp_channel,interp_point;
wire [31:0] point_pair;
wire signed [15:0] point_value=interp_channel[0] ? point_pair[31:16]:point_pair[15:0];
saixian_pitch_points points(.clk(clk),.we(state==R_GET && read_slot<8 && !rst && !clear),
 .wa(read_slot[2:0]),.wd(ring_q[63:32]),.ra({interp_channel[1],interp_point}),.rd(point_pair));
reg signed [20:0] cubic_c1,cubic_c2,cubic_y0;
reg signed [20:0] selected_m,selected_0,selected_1,selected_2;
reg signed [20:0] partial_30,partial_31,partial_20,partial_21;
wire signed [38:0] interp_value=$signed(cubic_y0)+((product+39'sd32768)>>>16);
reg [16:0] wet_gain;
reg [8:0] startup_gain;
wire [16:0] desired_gain=active_mode==0 ? 0 : active_mode>=3 ? 17'd32768 : 17'd65536;
wire [17:0] ratio=active_mode==1 ? 18'd82570 : active_mode==2 ? 18'd49097 :
                  active_mode==3 ? 18'd98193 : active_mode==4 ? 18'd131072 : 18'd65536;
wire signed [27:0] phase_step=28'sd65536-$signed({10'd0,ratio});
assign ready=fill>=2304 && startup_gain==256 && active_mode==requested_mode && wet_gain==desired_gain;
reg signed [15:0] dry_l,dry_r;
reg signed [15:0] head_a_l,head_a_r,head_b_l,head_b_r,wet_l,wet_r,mix_l,mix_r,ramped_l;
reg [5:0] operation_flags;
wire mac_heads=|operation_flags[1:0],mac_blend=|operation_flags[3:2];
reg signed [15:0] mac_base;
// The cubic path always enters operation 4. Select the two stereo sources
// before their one shared subtractor, rather than selecting four differences.
wire mac_right=|(operation_flags & 6'b101010);
wire signed[15:0] mac_head_a=mac_right ? head_a_r:head_a_l;
wire signed[15:0] mac_head_b=mac_right ? head_b_r:head_b_l;
wire signed[15:0] mac_dry=mac_right ? dry_r:dry_l;
wire signed[15:0] mac_wet=mac_right ? wet_r:wet_l;
wire signed[15:0] mac_mix=mac_right ? mix_r:mix_l;
wire signed[15:0] mac_source_a=mac_heads ? mac_head_b:mac_blend ? mac_dry:16'sd0;
wire signed[15:0] mac_source_b=mac_heads ? mac_head_a:mac_blend ? mac_wet:mac_mix;
wire signed[17:0] mac_difference=difference(mac_source_a,mac_source_b);
wire signed[17:0] mac_gain=mac_heads ? $signed({1'b0,head_weight}):
                                      mac_blend ? $signed({1'b0,wet_gain}):$signed({1'b0,startup_gain,8'd0});
wire signed [38:0] mac_value=$signed(mac_base)+((product+39'sd32768)>>>16);
// Separate the exact wide rounded sum from saturation and destination muxes.
// Twelve extra clocks per 48kHz stereo frame fit the original sample budget.
reg signed [38:0] mac_sum;
function signed [17:0] difference;
    input signed [15:0] a,b;
    begin difference=$signed({{2{b[15]}},b})-$signed({{2{a[15]}},a});end
endfunction
function signed [15:0] clip;
    input signed [39:0] value;
    begin clip=value>32767 ? 16'sd32767 : value < -32768 ? -16'sd32768 : value[15:0];end
endfunction
function signed [15:0] fir_clip;
    input signed [39:0] value;
    begin fir_clip=clip((value+40'sd16384)>>>15);end
endfunction
function signed [15:0] coefficient;
    input [5:0] index;input [2:0] mode;
    begin case({mode,index})
        9'd0:coefficient=-16'sd1;
        9'd1:coefficient=16'sd0;
        9'd2:coefficient=16'sd3;
        9'd3:coefficient=-16'sd9;
        9'd4:coefficient=16'sd16;
        9'd5:coefficient=-16'sd20;
        9'd6:coefficient=16'sd16;
        9'd7:coefficient=16'sd0;
        9'd8:coefficient=-16'sd28;
        9'd9:coefficient=16'sd62;
        9'd10:coefficient=-16'sd92;
        9'd11:coefficient=16'sd100;
        9'd12:coefficient=-16'sd71;
        9'd13:coefficient=16'sd0;
        9'd14:coefficient=16'sd107;
        9'd15:coefficient=-16'sd224;
        9'd16:coefficient=16'sd311;
        9'd17:coefficient=-16'sd322;
        9'd18:coefficient=16'sd221;
        9'd19:coefficient=16'sd0;
        9'd20:coefficient=-16'sd311;
        9'd21:coefficient=16'sd639;
        9'd22:coefficient=-16'sd877;
        9'd23:coefficient=16'sd907;
        9'd24:coefficient=-16'sd630;
        9'd25:coefficient=16'sd0;
        9'd26:coefficient=16'sd958;
        9'd27:coefficient=-16'sd2139;
        9'd28:coefficient=16'sd3373;
        9'd29:coefficient=-16'sd4456;
        9'd30:coefficient=16'sd5198;
        9'd31:coefficient=16'sd27306;
        9'd32:coefficient=16'sd5198;
        9'd33:coefficient=-16'sd4456;
        9'd34:coefficient=16'sd3373;
        9'd35:coefficient=-16'sd2139;
        9'd36:coefficient=16'sd958;
        9'd37:coefficient=16'sd0;
        9'd38:coefficient=-16'sd630;
        9'd39:coefficient=16'sd907;
        9'd40:coefficient=-16'sd877;
        9'd41:coefficient=16'sd639;
        9'd42:coefficient=-16'sd311;
        9'd43:coefficient=16'sd0;
        9'd44:coefficient=16'sd221;
        9'd45:coefficient=-16'sd322;
        9'd46:coefficient=16'sd311;
        9'd47:coefficient=-16'sd224;
        9'd48:coefficient=16'sd107;
        9'd49:coefficient=16'sd0;
        9'd50:coefficient=-16'sd71;
        9'd51:coefficient=16'sd100;
        9'd52:coefficient=-16'sd92;
        9'd53:coefficient=16'sd62;
        9'd54:coefficient=-16'sd28;
        9'd55:coefficient=16'sd0;
        9'd56:coefficient=16'sd16;
        9'd57:coefficient=-16'sd20;
        9'd58:coefficient=16'sd16;
        9'd59:coefficient=-16'sd9;
        9'd60:coefficient=16'sd3;
        9'd61:coefficient=16'sd0;
        9'd62:coefficient=-16'sd1;
        9'd64:coefficient=16'sd2;
        9'd65:coefficient=16'sd0;
        9'd66:coefficient=-16'sd6;
        9'd67:coefficient=16'sd9;
        9'd68:coefficient=16'sd0;
        9'd69:coefficient=-16'sd20;
        9'd70:coefficient=16'sd27;
        9'd71:coefficient=16'sd0;
        9'd72:coefficient=-16'sd48;
        9'd73:coefficient=16'sd62;
        9'd74:coefficient=16'sd0;
        9'd75:coefficient=-16'sd100;
        9'd76:coefficient=16'sd124;
        9'd77:coefficient=16'sd0;
        9'd78:coefficient=-16'sd185;
        9'd79:coefficient=16'sd224;
        9'd80:coefficient=16'sd0;
        9'd81:coefficient=-16'sd322;
        9'd82:coefficient=16'sd383;
        9'd83:coefficient=16'sd0;
        9'd84:coefficient=-16'sd539;
        9'd85:coefficient=16'sd639;
        9'd86:coefficient=16'sd0;
        9'd87:coefficient=-16'sd907;
        9'd88:coefficient=16'sd1092;
        9'd89:coefficient=16'sd0;
        9'd90:coefficient=-16'sd1660;
        9'd91:coefficient=16'sd2139;
        9'd92:coefficient=16'sd0;
        9'd93:coefficient=-16'sd4456;
        9'd94:coefficient=16'sd9002;
        9'd95:coefficient=16'sd21848;
        9'd96:coefficient=16'sd9002;
        9'd97:coefficient=-16'sd4456;
        9'd98:coefficient=16'sd0;
        9'd99:coefficient=16'sd2139;
        9'd100:coefficient=-16'sd1660;
        9'd101:coefficient=16'sd0;
        9'd102:coefficient=16'sd1092;
        9'd103:coefficient=-16'sd907;
        9'd104:coefficient=16'sd0;
        9'd105:coefficient=16'sd639;
        9'd106:coefficient=-16'sd539;
        9'd107:coefficient=16'sd0;
        9'd108:coefficient=16'sd383;
        9'd109:coefficient=-16'sd322;
        9'd110:coefficient=16'sd0;
        9'd111:coefficient=16'sd224;
        9'd112:coefficient=-16'sd185;
        9'd113:coefficient=16'sd0;
        9'd114:coefficient=16'sd124;
        9'd115:coefficient=-16'sd100;
        9'd116:coefficient=16'sd0;
        9'd117:coefficient=16'sd62;
        9'd118:coefficient=-16'sd48;
        9'd119:coefficient=16'sd0;
        9'd120:coefficient=16'sd27;
        9'd121:coefficient=-16'sd20;
        9'd122:coefficient=16'sd0;
        9'd123:coefficient=16'sd9;
        9'd124:coefficient=-16'sd6;
        9'd125:coefficient=16'sd0;
        9'd126:coefficient=16'sd2;
        9'd128:coefficient=-16'sd1;
        9'd129:coefficient=16'sd0;
        9'd130:coefficient=16'sd3;
        9'd131:coefficient=-16'sd9;
        9'd132:coefficient=16'sd16;
        9'd133:coefficient=-16'sd20;
        9'd134:coefficient=16'sd16;
        9'd135:coefficient=16'sd0;
        9'd136:coefficient=-16'sd28;
        9'd137:coefficient=16'sd62;
        9'd138:coefficient=-16'sd92;
        9'd139:coefficient=16'sd100;
        9'd140:coefficient=-16'sd71;
        9'd141:coefficient=16'sd0;
        9'd142:coefficient=16'sd107;
        9'd143:coefficient=-16'sd224;
        9'd144:coefficient=16'sd311;
        9'd145:coefficient=-16'sd322;
        9'd146:coefficient=16'sd221;
        9'd147:coefficient=16'sd0;
        9'd148:coefficient=-16'sd311;
        9'd149:coefficient=16'sd639;
        9'd150:coefficient=-16'sd877;
        9'd151:coefficient=16'sd907;
        9'd152:coefficient=-16'sd630;
        9'd153:coefficient=16'sd0;
        9'd154:coefficient=16'sd958;
        9'd155:coefficient=-16'sd2139;
        9'd156:coefficient=16'sd3373;
        9'd157:coefficient=-16'sd4456;
        9'd158:coefficient=16'sd5198;
        9'd159:coefficient=16'sd27306;
        9'd160:coefficient=16'sd5198;
        9'd161:coefficient=-16'sd4456;
        9'd162:coefficient=16'sd3373;
        9'd163:coefficient=-16'sd2139;
        9'd164:coefficient=16'sd958;
        9'd165:coefficient=16'sd0;
        9'd166:coefficient=-16'sd630;
        9'd167:coefficient=16'sd907;
        9'd168:coefficient=-16'sd877;
        9'd169:coefficient=16'sd639;
        9'd170:coefficient=-16'sd311;
        9'd171:coefficient=16'sd0;
        9'd172:coefficient=16'sd221;
        9'd173:coefficient=-16'sd322;
        9'd174:coefficient=16'sd311;
        9'd175:coefficient=-16'sd224;
        9'd176:coefficient=16'sd107;
        9'd177:coefficient=16'sd0;
        9'd178:coefficient=-16'sd71;
        9'd179:coefficient=16'sd100;
        9'd180:coefficient=-16'sd92;
        9'd181:coefficient=16'sd62;
        9'd182:coefficient=-16'sd28;
        9'd183:coefficient=16'sd0;
        9'd184:coefficient=16'sd16;
        9'd185:coefficient=-16'sd20;
        9'd186:coefficient=16'sd16;
        9'd187:coefficient=-16'sd9;
        9'd188:coefficient=16'sd3;
        9'd189:coefficient=16'sd0;
        9'd190:coefficient=-16'sd1;
        9'd192:coefficient=16'sd1;
        9'd193:coefficient=-16'sd4;
        9'd194:coefficient=16'sd2;
        9'd195:coefficient=16'sd9;
        9'd196:coefficient=-16'sd11;
        9'd197:coefficient=-16'sd11;
        9'd198:coefficient=16'sd30;
        9'd199:coefficient=16'sd0;
        9'd200:coefficient=-16'sd54;
        9'd201:coefficient=16'sd36;
        9'd202:coefficient=16'sd65;
        9'd203:coefficient=-16'sd100;
        9'd204:coefficient=-16'sd37;
        9'd205:coefficient=16'sd176;
        9'd206:coefficient=-16'sd55;
        9'd207:coefficient=-16'sd224;
        9'd208:coefficient=16'sd220;
        9'd209:coefficient=16'sd186;
        9'd210:coefficient=-16'sd428;
        9'd211:coefficient=16'sd0;
        9'd212:coefficient=16'sd602;
        9'd213:coefficient=-16'sd369;
        9'd214:coefficient=-16'sd620;
        9'd215:coefficient=16'sd907;
        9'd216:coefficient=16'sd326;
        9'd217:coefficient=-16'sd1538;
        9'd218:coefficient=16'sd496;
        9'd219:coefficient=16'sd2139;
        9'd220:coefficient=-16'sd2385;
        9'd221:coefficient=-16'sd2573;
        9'd222:coefficient=16'sd10041;
        9'd223:coefficient=16'sd19114;
        9'd224:coefficient=16'sd10041;
        9'd225:coefficient=-16'sd2573;
        9'd226:coefficient=-16'sd2385;
        9'd227:coefficient=16'sd2139;
        9'd228:coefficient=16'sd496;
        9'd229:coefficient=-16'sd1538;
        9'd230:coefficient=16'sd326;
        9'd231:coefficient=16'sd907;
        9'd232:coefficient=-16'sd620;
        9'd233:coefficient=-16'sd369;
        9'd234:coefficient=16'sd602;
        9'd235:coefficient=16'sd0;
        9'd236:coefficient=-16'sd428;
        9'd237:coefficient=16'sd186;
        9'd238:coefficient=16'sd220;
        9'd239:coefficient=-16'sd224;
        9'd240:coefficient=-16'sd55;
        9'd241:coefficient=16'sd176;
        9'd242:coefficient=-16'sd37;
        9'd243:coefficient=-16'sd100;
        9'd244:coefficient=16'sd65;
        9'd245:coefficient=16'sd36;
        9'd246:coefficient=-16'sd54;
        9'd247:coefficient=16'sd0;
        9'd248:coefficient=16'sd30;
        9'd249:coefficient=-16'sd11;
        9'd250:coefficient=-16'sd11;
        9'd251:coefficient=16'sd9;
        9'd252:coefficient=16'sd2;
        9'd253:coefficient=-16'sd4;
        9'd254:coefficient=16'sd1;
        9'd256:coefficient=-16'sd2;
        9'd257:coefficient=-16'sd2;
        9'd258:coefficient=16'sd6;
        9'd259:coefficient=16'sd8;
        9'd260:coefficient=-16'sd9;
        9'd261:coefficient=-16'sd21;
        9'd262:coefficient=16'sd6;
        9'd263:coefficient=16'sd42;
        9'd264:coefficient=16'sd11;
        9'd265:coefficient=-16'sd67;
        9'd266:coefficient=-16'sd51;
        9'd267:coefficient=16'sd81;
        9'd268:coefficient=16'sd119;
        9'd269:coefficient=-16'sd67;
        9'd270:coefficient=-16'sd210;
        9'd271:coefficient=16'sd0;
        9'd272:coefficient=16'sd305;
        9'd273:coefficient=16'sd142;
        9'd274:coefficient=-16'sd368;
        9'd275:coefficient=-16'sd372;
        9'd276:coefficient=16'sd346;
        9'd277:coefficient=16'sd682;
        9'd278:coefficient=-16'sd171;
        9'd279:coefficient=-16'sd1047;
        9'd280:coefficient=-16'sd246;
        9'd281:coefficient=16'sd1421;
        9'd282:coefficient=16'sd1065;
        9'd283:coefficient=-16'sd1747;
        9'd284:coefficient=-16'sd2804;
        9'd285:coefficient=16'sd1969;
        9'd286:coefficient=16'sd10196;
        9'd287:coefficient=16'sd14338;
        9'd288:coefficient=16'sd10196;
        9'd289:coefficient=16'sd1969;
        9'd290:coefficient=-16'sd2804;
        9'd291:coefficient=-16'sd1747;
        9'd292:coefficient=16'sd1065;
        9'd293:coefficient=16'sd1421;
        9'd294:coefficient=-16'sd246;
        9'd295:coefficient=-16'sd1047;
        9'd296:coefficient=-16'sd171;
        9'd297:coefficient=16'sd682;
        9'd298:coefficient=16'sd346;
        9'd299:coefficient=-16'sd372;
        9'd300:coefficient=-16'sd368;
        9'd301:coefficient=16'sd142;
        9'd302:coefficient=16'sd305;
        9'd303:coefficient=16'sd0;
        9'd304:coefficient=-16'sd210;
        9'd305:coefficient=-16'sd67;
        9'd306:coefficient=16'sd119;
        9'd307:coefficient=16'sd81;
        9'd308:coefficient=-16'sd51;
        9'd309:coefficient=-16'sd67;
        9'd310:coefficient=16'sd11;
        9'd311:coefficient=16'sd42;
        9'd312:coefficient=16'sd6;
        9'd313:coefficient=-16'sd21;
        9'd314:coefficient=-16'sd9;
        9'd315:coefficient=16'sd8;
        9'd316:coefficient=16'sd6;
        9'd317:coefficient=-16'sd2;
        9'd318:coefficient=-16'sd2;
        default:coefficient=0;
    endcase end
endfunction
always @(posedge clk or posedge rst) begin
    if(rst) begin
        state<=IDLE;fir_head<=0;fir_anchor<=0;tap<=0;fir_count<=0;
        accumulator_l<=0;accumulator_r<=0;write_index<=0;read_addr<=0;fill<=0;
        phase<=0;wet_gain<=0;startup_gain<=0;active_mode<=0;
        left_out<=0;right_out<=0;out_valid<=0;overrun<=0;
        offset_a<=0;offset_b<=0;best_offset<=0;corr_busy<=0;corr_head<=0;
        prev_mute_a<=0;prev_mute_b<=0;candidate<=0;corr_tap<=0;
        anchor_ref<=0;anchor_target<=0;corr_score<=0;best_score<=24'hffffff;
        ref_l<=0;ref_r<=0;interp_channel<=0;cubic_c1<=0;cubic_c2<=0;cubic_y0<=0;
        dl<=0;dr<=0;distance_reg<=0;score_total<=0;score_better<=0;

        mul_a<=0;mul_b<=0;product_l<=0;input_l<=0;input_r<=0;
        center_l<=0;center_r<=0;filtered_l<=0;filtered_r<=0;read_slot<=0;operation_flags<=0;
        dry_l<=0;dry_r<=0;head_a_l<=0;head_a_r<=0;head_b_l<=0;head_b_r<=0;
        wet_l<=0;wet_r<=0;mix_l<=0;mix_r<=0;ramped_l<=0;mac_base<=0;
    end else if(clear) begin
        state<=IDLE;fir_head<=0;fir_count<=0;write_index<=0;fill<=0;
        phase<=0;wet_gain<=0;startup_gain<=0;active_mode<=0;
        left_out<=0;right_out<=0;out_valid<=0;overrun<=0;
        offset_a<=0;offset_b<=0;best_offset<=0;corr_busy<=0;corr_head<=0;
        prev_mute_a<=0;prev_mute_b<=0;candidate<=0;corr_tap<=0;
        anchor_ref<=0;anchor_target<=0;corr_score<=0;best_score<=24'hffffff;
        ref_l<=0;ref_r<=0;interp_channel<=0;cubic_c1<=0;cubic_c2<=0;cubic_y0<=0;
        dl<=0;dr<=0;distance_reg<=0;score_total<=0;score_better<=0;

    end else begin
        out_valid<=0;
        if(sample_valid && state!=IDLE) overrun<=1;
        case(state)
            IDLE:if(sample_valid) begin
                input_l<=left_in;input_r<=right_in;state<=F_WRITE;
                prev_mute_a<=mute_a;prev_mute_b<=mute_b;
                if(!corr_busy && fill>=2700 && active_mode!=0 && active_mode==requested_mode &&
                   ((mute_a && !prev_mute_a) || (mute_b && !prev_mute_b))) begin
                    corr_busy<=1;corr_head<=mute_b && !prev_mute_b;
                    anchor_target<=mute_b && !prev_mute_b ? base_b : base_a;
                    // Downshift will wrap the muted head BEFORE its next fade.
                    // Shift the reference back one whole grain so the search
                    // compares its post-wrap separation, using only past data.
                    anchor_ref<=(mute_b && !prev_mute_b ? actual_a : actual_b)
                                -(active_mode==2 ? 12'd2048 : 12'd0);
                    candidate<=0;best_score<=24'hffffff;best_offset<=0;
                end

                if(requested_mode!=active_mode) begin
                    if(wet_gain>512) wet_gain<=wet_gain-512;
                    else if(wet_gain!=0) wet_gain<=0;
                    else begin active_mode<=requested_mode;phase<=0;offset_a<=0;offset_b<=0;corr_busy<=0;end
                end else if(wet_gain<desired_gain)
                    wet_gain<=desired_gain-wet_gain>512 ? wet_gain+512 : desired_gain;
                else if(wet_gain>desired_gain)
                    wet_gain<=wet_gain-desired_gain>512 ? wet_gain-512 : desired_gain;
                if(fill>=2304) begin if(startup_gain<256) startup_gain<=startup_gain+4;end
                else startup_gain<=0;
            end
            F_WRITE:begin
                fir_anchor<=fir_head;fir_head<=fir_head+1'b1;
                if(fir_count<63) fir_count<=fir_count+1'b1;
                tap<=0;accumulator_l<=0;accumulator_r<=0;state<=F_READ;
            end
            F_READ:state<=F_GET;
            F_GET:begin
                mul_a<=tap<fir_count ? $signed(fir_q[15:0]) : 18'sd0;
                mul_b<=coefficient_q;
                if(tap==31) begin
                    center_l<=tap<fir_count ? $signed(fir_q[15:0]) : 16'sd0;
                    // Right centre is captured in F_SET_R after the second RAM slice.
                end
                state<=F_WAIT_L;
            end
            F_WAIT_L:state<=F_SET_R;
            F_SET_R:begin
                if(tap==31)center_r<=tap<fir_count ? $signed(fir_q[31:16]):16'sd0;
                product_l<=product;
                mul_a<=tap<fir_count ? $signed(fir_q[31:16]) : 18'sd0;
                state<=F_WAIT_R;
            end
            F_WAIT_R:state<=F_ACC;
            F_ACC:begin
                accumulator_l<=fir_total_l;accumulator_r<=fir_total_r;
                if(tap==62)state<=F_ROUND;
                else begin tap<=tap+1'b1;state<=F_READ;end
            end
            // The FIR accumulators are dead until the next F_WRITE. Reuse
            // them for the exact signed rounded values, then saturate on a
            // separate clock instead of routing sum -> round -> clip at once.
            F_ROUND:begin
                accumulator_l<=($signed(accumulator_l)+40'sd16384)>>>15;
                accumulator_r<=($signed(accumulator_r)+40'sd16384)>>>15;
                state<=F_CLIP;
            end
            F_CLIP:begin
                filtered_l<=clip(accumulator_l);filtered_r<=clip(accumulator_r);state<=R_WRITE;
            end
            R_WRITE:begin
                if(fill<4095) fill<=fill+1'b1;
                read_slot<=0;read_addr<=actual_a+12'd1;state<=R_READ;
            end
            R_READ:state<=R_WAIT;
            R_WAIT:state<=R_GET;
            R_GET:begin
                if(read_slot<8) begin
                    // The distributed point RAM captures this stereo pair on the same edge.
                    case(read_slot)
                        0:read_addr<=actual_a;
                        1:read_addr<=actual_a-12'd1;
                        2:read_addr<=actual_a-12'd2;
                        3:read_addr<=actual_b+12'd1;
                        4:read_addr<=actual_b;
                        5:read_addr<=actual_b-12'd1;
                        6:read_addr<=actual_b-12'd2;
                        7:read_addr<=write_index-12'd1152;
                    endcase
                    read_slot<=read_slot+1'b1;state<=R_READ;
                end else begin
                    dry_l<=ring_q[15:0];dry_r<=ring_q[31:16];interp_channel<=0;interp_point<=0;state<=I_SELECT;
                end
            end
            // Four-point Catmull-Rom cubic, full Q16 fractional position.
            // Coefficients/intermediates stay wide; saturate only the final sample.
            I_SELECT:begin
                case(interp_point)
                    0:selected_m<=point_value;1:selected_0<=point_value;
                    2:selected_1<=point_value;3:selected_2<=point_value;
                endcase
                interp_point<=interp_point+1'b1;
                if(interp_point==3)state<=I_PART;
            end
            I_PART:begin
                partial_30<=selected_2-selected_m;
                partial_31<=selected_0-selected_1;
                partial_20<=(selected_m<<<1)-(selected_0<<<2)-selected_0;
                partial_21<=(selected_1<<<2)-selected_2;
                cubic_c1<=(selected_1-selected_m)>>>1;cubic_y0<=selected_0;state<=I_COEFF;
            end
            I_COEFF:begin
                mul_a<=(partial_30+(partial_31<<<1)+partial_31)>>>1;
                cubic_c2<=(partial_20+partial_21)>>>1;
                mul_b<=$signed({2'd0,phase[15:0]});state<=I_WAIT0;
            end
            I_WAIT0:state<=I_STEP0;
            I_STEP0:begin mul_a<=((product+39'sd32768)>>>16)+cubic_c2;state<=I_WAIT1;end
            I_WAIT1:state<=I_STEP1;
            I_STEP1:begin mul_a<=((product+39'sd32768)>>>16)+cubic_c1;state<=I_WAIT2;end
            I_WAIT2:state<=I_DONE;
            I_DONE:begin
                case(interp_channel)
                    0:head_a_l<=clip(interp_value);1:head_a_r<=clip(interp_value);
                    2:head_b_l<=clip(interp_value);3:head_b_r<=clip(interp_value);
                endcase
                if(interp_channel==3) begin operation_flags<=6'd1;state<=MAC_SELECT;end
                else begin interp_channel<=interp_channel+1'b1;state<=I_SELECT;end
            end
            // Background stereo SAD search, +/-64 samples, 16 points at stride 4.
            C_REF0:state<=C_REF1;
            C_REF1:state<=C_REF2;
            C_REF2:begin
                ref_l<=ring_q[47:32];ref_r<=ring_q[63:48];
                read_addr<=corr_target_addr;state<=C_TGT0;
            end
            C_TGT0:state<=C_TGT1;
            C_TGT1:state<=C_TGT2;
            C_TGT2:begin
                dl<=$signed({ring_q[47],ring_q[47:32]})-$signed({ref_l[15],ref_l});
                dr<=$signed({ring_q[63],ring_q[63:48]})-$signed({ref_r[15],ref_r});
                state<=C_ABS;
            end
            C_ABS:begin distance_reg<=distance;state<=C_SUM;end
            C_SUM:begin
                score_total<=corr_score+distance_reg;
                state<=corr_tap==15 ? C_COMPARE:C_SCORE;
            end
            // Only the final SAD tap selects a candidate. Register that
            // exact comparison before the offset/address destination muxes.
            // One background clock per candidate fits the 48 kHz budget.
            C_COMPARE:begin score_better<=score_total<best_score;state<=C_SCORE;end
            C_SCORE:begin
                if(corr_tap==15) begin
                    if(score_better) begin best_score<=score_total;best_offset<=candidate_offset;end
                    if(candidate==128) begin
                        if(corr_head && mute_b) offset_b<=score_better ? candidate_offset : best_offset;
                        if(!corr_head && mute_a) offset_a<=score_better ? candidate_offset : best_offset;
                        corr_busy<=0;
                    end else candidate<=candidate+1'b1;
                    state<=IDLE;
                end else begin
                    corr_score<=score_total;corr_tap<=corr_tap+1'b1;
                    read_addr<=anchor_ref-{6'd0,corr_tap,2'b0}-12'd4;state<=C_REF0;
                end
            end
            // The cubic partials are dead after the final I_DONE. Reuse
            // them for MAC operands, cutting source selection/subtraction
            // away from the shared DSP input mux without adding word registers.
            MAC_SELECT:begin
                partial_20<=mac_difference;partial_21<=mac_gain;mac_base<=mac_source_a;
                state<=MAC_SET;
            end
            MAC_SET:begin
                mul_a<=partial_20;mul_b<=partial_21[17:0];
                state<=MAC_WAIT;
            end
            MAC_WAIT:state<=MAC_DONE;
            MAC_DONE:begin mac_sum<=mac_value;state<=MAC_CLIP;end
            MAC_CLIP:begin
                (* parallel_case *) case(1'b1)
                    operation_flags[0]:wet_l<=clip(mac_sum);operation_flags[1]:wet_r<=clip(mac_sum);
                    operation_flags[2]:mix_l<=clip(mac_sum);operation_flags[3]:mix_r<=clip(mac_sum);
                    operation_flags[4]:ramped_l<=clip(mac_sum);
                    operation_flags[5]:begin
                        left_out<=fill>=2304 ? ramped_l : 16'sd0;
                        right_out<=fill>=2304 ? clip(mac_sum) : 16'sd0;
                        out_valid<=1;write_index<=write_index+1'b1;
                        phase<=active_mode==0 ? 27'd0 : phase+phase_step;
                        if(corr_busy && active_mode==requested_mode) begin
                            corr_tap<=0;corr_score<=0;read_addr<=anchor_ref;state<=C_REF0;
                        end else begin corr_busy<=0;state<=IDLE;end
                    end
                endcase
                if(!operation_flags[5]) begin operation_flags<=operation_flags<<1;state<=MAC_SELECT;end
            end
            default:state<=IDLE;
        endcase
    end
end
endmodule

// Specialized exact 1152-sample dry delay. After each write, pointer names
// the oldest retained frame. The final R_READ/R_WAIT pair follows all eight
// cubic point reads, so tail writes finish well before its two read slices.
module saixian_pitch_dry_delay(input clk,rst,write_frame,read_first,read_second,
 input[31:0] wd,output[31:0] rd);
reg[10:0] pointer;
reg tail_write_pending,read_tail;
reg[7:0] saved_tail_address;
reg[15:0] saved_tail_high,tail_low;
wire head_write=write_frame && !pointer[10] && !rst;
wire tail_write=write_frame && pointer[10] && !rst;
wire tail_write_second=tail_write_pending && !rst;
wire tail_we=tail_write || tail_write_second;
wire[7:0] tail_index=tail_write_second ? saved_tail_address:pointer[7:0];
wire tail_second=tail_write_second || (!tail_write && read_second);
wire[9:0] byte_address={tail_index,tail_second,1'b0};
wire[15:0] tail_data=tail_write_second ? saved_tail_high:wd[15:0];
wire[31:0] head_q;
wire[7:0] tail_a,tail_b;
always @(posedge clk)begin
 if(rst)begin pointer<=0;tail_write_pending<=0;read_tail<=0;saved_tail_address<=0;saved_tail_high<=0;tail_low<=0;end
 else begin
  if(write_frame)pointer<=pointer==1152 ? 11'd0:pointer+1'b1;
  tail_write_pending<=tail_write;
  if(tail_write)begin saved_tail_address<=pointer[7:0];saved_tail_high<=wd[31:16];end
  if(read_first)read_tail<=pointer[10];
  if(read_second)tail_low<={tail_b,tail_a};
 end
end
`ifdef VICTORY_SIM
reg[15:0] head_memory[0:2047];reg[31:0] head_read;
reg[7:0] tail_memory[0:1023];reg[7:0] tail_read_a,tail_read_b;
always @(posedge clk)begin
 if(head_write)begin head_memory[{pointer[9:0],1'b0}]<=wd[15:0];head_memory[{pointer[9:0],1'b1}]<=wd[31:16];end
 head_read<={head_memory[{pointer[9:0],1'b1}],head_memory[{pointer[9:0],1'b0}]};
 if(tail_we)begin tail_memory[byte_address]<=tail_data[7:0];tail_memory[byte_address+1'b1]<=tail_data[15:8];end
 tail_read_a<=tail_memory[byte_address];tail_read_b<=tail_memory[byte_address+1'b1];
 if(!rst && ((tail_write && tail_write_second) || ((read_first || read_second) && tail_we)))
  $fatal(1,"pitch dry-delay port ownership collision");
end
assign head_q=head_read;assign tail_a=tail_read_a;assign tail_b=tail_read_b;
`else
EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.ADDR_WIDTH_A(11),.DATA_DEPTH_A(2048),
 .DATA_WIDTH_B(16),.ADDR_WIDTH_B(11),.DATA_DEPTH_B(2048),.BYTE_ENABLE(0),.MODE("DP"),
 .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),
 .RESETMODE("SYNC"),.IMPLEMENT("32K")) head(
 .clka(clk),.rsta(1'b0),.cea(1'b1),.wea(head_write),.ocea(1'b1),.bea(1'b0),
 .addra({pointer[9:0],1'b0}),.dia(wd[15:0]),.doa(head_q[15:0]),
 .clkb(clk),.rstb(1'b0),.ceb(1'b1),.web(head_write),.oceb(1'b1),.beb(1'b0),
 .addrb({pointer[9:0],1'b1}),.dib(wd[31:16]),.dob(head_q[31:16]));
EG_LOGIC_BRAM #(.DATA_WIDTH_A(8),.ADDR_WIDTH_A(10),.DATA_DEPTH_A(1024),
 .DATA_WIDTH_B(8),.ADDR_WIDTH_B(10),.DATA_DEPTH_B(1024),.BYTE_ENABLE(0),.MODE("DP"),
 .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),
 .RESETMODE("SYNC"),.IMPLEMENT("9K")) tail(
 .clka(clk),.rsta(1'b0),.cea(1'b1),.wea(tail_we),.ocea(1'b1),.bea(1'b0),
 .addra(byte_address),.dia(tail_data[7:0]),.doa(tail_a),
 .clkb(clk),.rstb(1'b0),.ceb(1'b1),.web(tail_we),.oceb(1'b1),.beb(1'b0),
 .addrb(byte_address+10'd1),.dib(tail_data[15:8]),.dob(tail_b));
`endif
assign rd=read_tail ? {tail_b,tail_a,tail_low}:head_q;
endmodule

module saixian_pitch_ram #(
    parameter WIDTH=64,ADDR=12,CAP_ADDR=11,parameter RAM_KIND="32K",parameter RAM32_LANES=8
)(input clk,we,input [ADDR-1:0] wa,ra,input [WIDTH-1:0] wd,output [WIDTH-1:0] rd);
`ifdef VICTORY_SIM
reg [WIDTH-1:0] mem[0:(1<<ADDR)-1];reg [WIDTH-1:0] q;
always @(posedge clk) begin q<=mem[ra];if(we)mem[wa]<=wd;end
assign rd=q;
`else
localparam BANKS=ADDR>CAP_ADDR ? 1<<(ADDR-CAP_ADDR) : 1;
wire [WIDTH-1:0] bank_q[0:BANKS-1];reg [31:0] bank_sel;
wire [CAP_ADDR-1:0] wa_native=wa,ra_native=ra;
always @(posedge clk) bank_sel<=ra>>CAP_ADDR;
genvar bank,lane;
generate for(bank=0;bank<BANKS;bank=bank+1)begin:banks
    for(lane=0;lane<WIDTH/16;lane=lane+1)begin:lanes
        EG_LOGIC_BRAM #(
            .DATA_WIDTH_A(16),.ADDR_WIDTH_A(CAP_ADDR),.DATA_DEPTH_A(1<<CAP_ADDR),
            .DATA_WIDTH_B(16),.ADDR_WIDTH_B(CAP_ADDR),.DATA_DEPTH_B(1<<CAP_ADDR),
            .BYTE_ENABLE(0),.MODE("PDPW"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
            .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),
            .DEBUGGABLE("NO"),.PACKABLE("NO"),.FORCE_KEEP("OFF"),
            // One 2048x16 lane may use four RAM9Ks instead of one RAM32K.
            // Logical depth, read latency and all audio arithmetic stay exact.
            .INIT_FILE("NONE"),.FILL_ALL("NONE"),
            .IMPLEMENT(RAM_KIND=="32K" && bank*(WIDTH/16)+lane>=RAM32_LANES ? "9K":RAM_KIND)
        ) ram(
            .doa(),.dob(bank_q[bank][lane*16+:16]),.dia(wd[lane*16+:16]),.dib(16'd0),
            .cea(1'b1),.ocea(1'b0),.clka(clk),.wea(we && (wa>>CAP_ADDR)==bank),.rsta(1'b0),
            .ceb(1'b1),.oceb(1'b0),.clkb(clk),.web(1'b0),.rstb(1'b0),
            .bea(1'b0),.beb(1'b0),.addra(wa_native),.addrb(ra_native));
    end
end endgenerate
assign rd=bank_q[bank_sel];
`endif
endmodule

// Asynchronous read, synchronous write: native LUT RAM, no block RAM.
module saixian_pitch_points(input clk,we,input[2:0] wa,ra,input[31:0] wd,output[31:0] rd);
`ifdef VICTORY_SIM
reg[31:0] memory[0:7];
always @(posedge clk)if(we)memory[wa]<=wd;
assign rd=memory[ra];
`else
EG_LOGIC_DRAM #(.DATA_WIDTH_W(32),.DATA_WIDTH_R(32),.ADDR_WIDTH_W(4),.ADDR_WIDTH_R(4),
 .DATA_DEPTH_W(16),.DATA_DEPTH_R(16)) memory(.di(wd),.waddr({1'b0,wa}),.we(we),
 .wclk(clk),.raddr({1'b0,ra}),.\do (rd));
`endif
endmodule

// 64 stereo FIR frames in one byte-wide true-dual RAM9K.
// Capture left on IDLE's input edge and right on F_WRITE. F_READ exposes
// left; F_GET and following multiplier clocks expose right. No extra cycles.
module saixian_pitch_fir_ram(input clk,write_left,write_right,read_right,
 input[5:0] wa,ra,input[15:0] left_data,right_data,output[15:0] rd);
wire we=write_left || write_right;
wire[8:0] address={1'b0,(we ? wa:ra),(we ? write_right:read_right),1'b0};
wire[15:0] wd=write_right ? right_data:left_data;
`ifdef VICTORY_SIM
reg[7:0] memory[0:511];reg[7:0] qa,qb;
always @(posedge clk)begin
 if(we)begin memory[address]<=wd[7:0];memory[address+1'b1]<=wd[15:8];end
 else begin qa<=memory[address];qb<=memory[address+1'b1];end
end
assign rd={qb,qa};
`else
EG_LOGIC_BRAM #(.DATA_WIDTH_A(8),.ADDR_WIDTH_A(9),.DATA_DEPTH_A(512),
 .DATA_WIDTH_B(8),.ADDR_WIDTH_B(9),.DATA_DEPTH_B(512),.BYTE_ENABLE(0),.MODE("DP"),
 .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),
 .RESETMODE("SYNC"),.IMPLEMENT("9K")) memory(
 .clka(clk),.rsta(1'b0),.cea(1'b1),.wea(we),.ocea(1'b1),.bea(1'b0),.addra(address),.dia(wd[7:0]),.doa(rd[7:0]),
 .clkb(clk),.rstb(1'b0),.ceb(1'b1),.web(we),.oceb(1'b1),.beb(1'b0),.addrb(address+9'd1),.dib(wd[15:8]),.dob(rd[15:8]));
`endif
endmodule

// Same coefficients and F_GET boundary as 5.4; the registered ROM removes
// the 315-way combinational coefficient decoder from the DSP input mux.
module saixian_pitch_coeff(input clk,input[8:0] address,output signed[15:0] value);
`ifdef VICTORY_SIM
reg[15:0] memory[0:511];reg[15:0] q;
initial $readmemh("common/audio_ui/saixian_pitch_coeff.hex",memory);
always @(posedge clk)q<=memory[address];
assign value=q;
`else
EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.ADDR_WIDTH_A(9),.DATA_DEPTH_A(512),
 .DATA_WIDTH_B(16),.ADDR_WIDTH_B(9),.DATA_DEPTH_B(512),.BYTE_ENABLE(0),.MODE("SP"),
 .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),
 .RESETMODE("SYNC"),.IMPLEMENT("9K"),.INIT_FILE("saixian_pitch_coeff.mif")) memory(
 .clka(clk),.rsta(1'b0),.cea(1'b1),.wea(1'b0),.ocea(1'b1),.bea(1'b0),.addra(address),.dia(16'd0),.doa(value),
 .clkb(clk),.rstb(1'b0),.ceb(1'b0),.web(1'b0),.oceb(1'b0),.beb(1'b0),.addrb(9'd0),.dib(16'd0),.dob());
`endif
endmodule

