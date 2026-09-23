// Blue-only victory scene, 1280x720. K2: IDLE -> PLAY -> HOLD -> IDLE.
// Three aligned pixel stages. No red/opponent scene and no automatic exit.
module saixian_battle_result_fx(
    input wire clk, rst, frame_tick, trigger,
    input wire [10:0] x_in,
    input wire [9:0] y_in,
    input wire de_in, vs_in,
    input wire [23:0] rgb_in,
    output wire busy,
    output reg de_out, vs_out,
    output reg [23:0] rgb_out
);
localparam IDLE=2'd0, PLAY=2'd1, HOLD=2'd2;
reg [1:0] state;
reg pending;
reg [8:0] frame_count;
reg [11:0] wipe_edge, sheen_edge;
reg [4:0] title_drop;
assign busy = (state != IDLE) || pending;
wire [8:0] next_frame = frame_count + 9'd1;

function [11:0] ease_wipe;
    input [5:0] phase;
    begin
        case(phase)
            6'd0: ease_wipe = 12'd0;
            6'd1: ease_wipe = 12'd107;
            6'd2: ease_wipe = 12'd207;
            6'd3: ease_wipe = 12'd301;
            6'd4: ease_wipe = 12'd390;
            6'd5: ease_wipe = 12'd473;
            6'd6: ease_wipe = 12'd551;
            6'd7: ease_wipe = 12'd624;
            6'd8: ease_wipe = 12'd693;
            6'd9: ease_wipe = 12'd756;
            6'd10: ease_wipe = 12'd815;
            6'd11: ease_wipe = 12'd870;
            6'd12: ease_wipe = 12'd921;
            6'd13: ease_wipe = 12'd968;
            6'd14: ease_wipe = 12'd1012;
            6'd15: ease_wipe = 12'd1052;
            6'd16: ease_wipe = 12'd1089;
            6'd17: ease_wipe = 12'd1123;
            6'd18: ease_wipe = 12'd1155;
            6'd19: ease_wipe = 12'd1183;
            6'd20: ease_wipe = 12'd1209;
            6'd21: ease_wipe = 12'd1232;
            6'd22: ease_wipe = 12'd1254;
            6'd23: ease_wipe = 12'd1273;
            6'd24: ease_wipe = 12'd1290;
            6'd25: ease_wipe = 12'd1305;
            6'd26: ease_wipe = 12'd1319;
            6'd27: ease_wipe = 12'd1331;
            6'd28: ease_wipe = 12'd1342;
            6'd29: ease_wipe = 12'd1352;
            6'd30: ease_wipe = 12'd1360;
            6'd31: ease_wipe = 12'd1367;
            6'd32: ease_wipe = 12'd1373;
            6'd33: ease_wipe = 12'd1378;
            6'd34: ease_wipe = 12'd1383;
            6'd35: ease_wipe = 12'd1386;
            6'd36: ease_wipe = 12'd1390;
            6'd37: ease_wipe = 12'd1392;
            6'd38: ease_wipe = 12'd1394;
            6'd39: ease_wipe = 12'd1396;
            6'd40: ease_wipe = 12'd1397;
            6'd41: ease_wipe = 12'd1398;
            6'd42: ease_wipe = 12'd1399;
            6'd43: ease_wipe = 12'd1399;
            6'd44: ease_wipe = 12'd1400;
            6'd45: ease_wipe = 12'd1400;
            6'd46: ease_wipe = 12'd1400;
            6'd47: ease_wipe = 12'd1400;
            6'd48: ease_wipe = 12'd1400;
            6'd49: ease_wipe = 12'd1400;
            6'd50: ease_wipe = 12'd1400;
            6'd51: ease_wipe = 12'd1400;
            default: ease_wipe=12'd1400;
        endcase
    end
endfunction

always @(posedge clk or posedge rst) begin
    if(rst) begin
        state<=IDLE; pending<=0; frame_count<=0;
        wipe_edge<=0; sheen_edge<=0; title_drop<=24;
    end else begin
        // Only queue presses in idle or final hold. Play-time presses cannot
        // become a delayed exit when the animation subsequently finishes.
        if(trigger && state != PLAY) pending<=1;
        if(frame_tick) begin
            if(state==IDLE) begin
                if(pending || trigger) begin
                    state<=PLAY; pending<=0; frame_count<=0;
                    wipe_edge<=0; sheen_edge<=0; title_drop<=24;
                end
            end else if(state==PLAY) begin
                pending<=0;
                if(frame_count==9'd359) state<=HOLD;
                else begin
                    frame_count<=next_frame;
                    if(next_frame>=50 && next_frame<=101)
                        wipe_edge<=ease_wipe(next_frame-9'd50);
                    if(next_frame>=90 && next_frame<114)
                        title_drop<=9'd114-next_frame;
                    else if(next_frame>=114) title_drop<=0;
                    if(next_frame>=156 && next_frame<=216)
                        sheen_edge<=sheen_edge+12'd28;
                end
            end else if(pending || trigger) begin
                state<=IDLE; pending<=0; frame_count<=0;
            end
        end
    end
end

// Atlas rectangles: large Chinese title, VICTORY, intro, footer, subtitle,
// and the final K2 return prompt. Native-size, 2-bit antialiased typography.
reg [8:0] atlas_x;
reg [6:0] atlas_y;
reg ink_enable;
// Fixed vertical baseline: only the three slices move, avoiding a serial
// frame-offset/subtract/cut-selector chain on the synchronous ROM address.
wire [9:0] title_y = 10'd322;
// Three staggered diagonal title slices, settling into the original atlas.
// Displacements are frame-rate registers, outside the pixel arithmetic path.
reg [7:0] slice_a, slice_b, slice_c;
function [7:0] slice_shift;
    input [8:0] f;
    input [8:0] onset;
    reg [8:0] age;
    begin
        age=f-onset;
        if(f<onset) slice_shift=8'd160;
        else if(age<8) slice_shift=8'd160-(age<<4);
        else if(age<16) slice_shift=8'd32-((age-8)<<2);
        else slice_shift=0;
    end
endfunction
always @(posedge clk or posedge rst) begin
    if(rst) begin slice_a<=160; slice_b<=160; slice_c<=160; end
    else if(frame_tick) begin
        slice_a<=slice_shift(next_frame,9'd90);
        slice_b<=slice_shift(next_frame,9'd98);
        slice_c<=slice_shift(next_frame,9'd106);
        if(state==IDLE) begin slice_a<=160; slice_b<=160; slice_c<=160; end
    end
end
wire signed [12:0] title_u=$signed({2'b00,x_in})-13'sd448;
wire signed [12:0] title_v=$signed({3'b000,y_in})-$signed({3'b000,title_y});
wire signed [12:0] cut_axis=title_v+(title_u>>>3);
reg signed [12:0] source_u;
reg title_ready;
always @* begin
    source_u=title_u;
    title_ready=0;
    if(cut_axis<48) begin
        source_u=title_u+$signed({5'b0,slice_a});
        title_ready=(frame_count>=90);
    end else if(cut_axis<96) begin
        source_u=title_u-$signed({5'b0,slice_b});
        title_ready=(frame_count>=98);
    end else begin
        source_u=title_u+$signed({5'b0,slice_c});
        title_ready=(frame_count>=106);
    end
end
always @* begin
    atlas_x=0; atlas_y=0; ink_enable=0;
    if(state!=IDLE && de_in) begin
        if(frame_count<65 && x_in>=576 && x_in<704 && y_in>=332 && y_in<364) begin
            atlas_x=x_in-11'd192; atlas_y=y_in-10'd300; ink_enable=1;
        end
        if(frame_count>=90) begin
            if(title_ready && source_u>=0 && source_u<384 && title_v>=0 && title_v<96) begin
                atlas_x=source_u[8:0]; atlas_y=title_v[6:0]; ink_enable=1;
            end else if(x_in>=576 && x_in<704 && y_in>=280 && y_in<304) begin
                atlas_x=x_in-11'd192; atlas_y=y_in-10'd280; ink_enable=1;
            end else if(x_in>=448 && x_in<832 && y_in>=435 && y_in<467) begin
                atlas_x=x_in-11'd448; atlas_y=y_in-10'd339; ink_enable=1;
            end
        end
        if(frame_count>=130 && x_in>=576 && x_in<704 && y_in>=546 && y_in<570) begin
            atlas_x=x_in-11'd192; atlas_y=y_in-10'd482; ink_enable=1;
        end
        if(state==HOLD && x_in>=576 && x_in<704 && y_in>=602 && y_in<634) begin
            atlas_x=x_in-11'd192; atlas_y=y_in-10'd506; ink_enable=1;
        end
    end
end
wire [31:0] atlas_word;
saixian_victory_atlas u_atlas(.clk(clk),.addr({atlas_y,atlas_x[8:4]}),.bits(atlas_word));

// Stage 1: geometry coordinates and synchronous ROM read in parallel.
reg [10:0] xq;
reg [9:0] yq;
reg [11:0] diagonal_q, edge_q, sheen_q;
reg [10:0] center_distance_q;
reg [8:0] fq;
reg active_q, hold_q, de_q, vs_q, ink_q;
reg [3:0] subpixel_q;
reg [23:0] rgb_q;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        xq<=0; yq<=0; diagonal_q<=0; edge_q<=0; sheen_q<=0;
        center_distance_q<=0; fq<=0; active_q<=0; hold_q<=0;
        de_q<=0; vs_q<=0; ink_q<=0; subpixel_q<=0; rgb_q<=0;
    end else begin
        xq<=x_in; yq<=y_in;
        diagonal_q<={1'b0,x_in}+{3'b0,y_in[9:1]};
        center_distance_q <= (x_in>=640) ? x_in-11'd640 : 11'd640-x_in;
        edge_q<=wipe_edge+12'd121; sheen_q<=sheen_edge;
        fq<=frame_count; active_q<=(state!=IDLE); hold_q<=(state==HOLD);
        de_q<=de_in; vs_q<=vs_in; ink_q<=ink_enable;
        subpixel_q<=atlas_x[3:0]; rgb_q<=rgb_in;
    end
end

reg [23:0] scene_rgb;
reg plate, shield, shield_inner, badge_y;
reg [10:0] taper;
always @* begin
    // Separated angled plates, never a full-width rectangular banner.
    plate=(fq>=50 && yq>=242 && yq<496 && diagonal_q<edge_q &&
           ((diagonal_q>=420 && diagonal_q<588 && yq>=260 && yq<474) ||
            (diagonal_q>=608 && diagonal_q<1092) ||
            (diagonal_q>=1112 && diagonal_q<1280 && yq>=260 && yq<474)));
    taper=(yq>=176) ? 11'd224-{1'b0,yq} : 11'd48;
    shield=(fq>=78 && yq>=112 && yq<224 && center_distance_q<=taper);
    shield_inner=(yq>=116 && yq<220 && center_distance_q+11'd4<taper);
    badge_y=(yq>=132 && yq<177 &&
             center_distance_q+(yq-10'd132)/2>=20 &&
             center_distance_q+(yq-10'd132)/2<32) ||
            (yq>=168 && yq<200 && center_distance_q<10) ||
            (yq>=200 && yq<210 && center_distance_q<210-yq);
    scene_rgb=rgb_q;
    if(active_q) begin
        // Restrained dark-blue field; diagonal architecture, not a red/blue split.
        scene_rgb=24'h0B1723;
        if(center_distance_q<448) scene_rgb=24'h0E202E;
        if(center_distance_q<256) scene_rgb=24'h102735;
        if(diagonal_q[7:0]<2) scene_rgb=24'h183341;
        if((yq==46 || yq==674) && xq>=48 && xq<1232) scene_rgb=24'h526574;
        if(fq<65 && (yq==300 || yq==438) && xq>=440 && xq<840)
            scene_rgb=24'h54D5F6;
        if(plate) begin
            scene_rgb=24'h196580;
            if(center_distance_q<448) scene_rgb=24'h1B708C;
            if(center_distance_q<256) scene_rgb=24'h207C97;
            if(diagonal_q[4:0]==0) scene_rgb=24'h2A819B;
            if(yq<244 || yq>=494 || diagonal_q==608 || diagonal_q==1091)
                scene_rgb=24'h54D5F6;
            if(fq>=156 && fq<216 && diagonal_q>=sheen_q && diagonal_q<sheen_q+12'd72)
                scene_rgb=24'h398FA7;
        end
        if(fq>=50 && fq<108 && yq>=218 && yq<520 &&
           diagonal_q>=edge_q && diagonal_q<edge_q+12'd8) scene_rgb=24'hDDF9FF;
        if(shield) scene_rgb=shield_inner ? 24'h0B1723 : 24'h54D5F6;
        if(shield && badge_y) scene_rgb=24'h54D5F6;
        if(fq>=78 && yq>=163 && yq<165 &&
          ((xq>=405 && xq<539) || (xq>=741 && xq<875))) scene_rgb=24'h4098B0;
        if(fq>=130 && yq==590 && xq>=600 && xq<680) scene_rgb=24'h526574;
        // Fixed decorative dashes; final hold has no running counters/motion.
        if((yq==100 && xq>=84 && xq<103) ||
           (yq==536 && xq>=1050 && xq<1063) ||
           (yq==646 && xq>=310 && xq<326)) scene_rgb=24'h276078;
        if(hold_q && yq>=672 && yq<674 && xq>=48 && xq<1232) scene_rgb=24'h54D5F6;
    end
end

// Stage 2: resolve ROM bit-pair and register geometry before alpha blending.
wire [4:0] bit_offset = {~subpixel_q,1'b0};
reg [1:0] alpha_q2;
reg [23:0] base_q2;
reg de_q2, vs_q2;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        alpha_q2<=0; base_q2<=0; de_q2<=0; vs_q2<=0;
    end else begin
        alpha_q2<=ink_q ? ((atlas_word >> bit_offset) & 32'h3) : 2'd0;
        base_q2<=scene_rgb; de_q2<=de_q; vs_q2<=vs_q;
    end
end

function [7:0] blend_white;
    input [7:0] base;
    input [1:0] alpha;
    begin
        case(alpha)
            0: blend_white=base;
            1: blend_white=(base>>1)+(base>>2)+8'd63;
            2: blend_white=(base>>2)+8'd191;
            default: blend_white=8'd255;
        endcase
    end
endfunction
// Stage 3: final RGB/DE/VS are always delayed by the same three clocks.
always @(posedge clk or posedge rst) begin
    if(rst) begin de_out<=0; vs_out<=0; rgb_out<=0; end
    else begin
        de_out<=de_q2; vs_out<=vs_q2;
        rgb_out<=de_q2 ? {blend_white(base_q2[23:16],alpha_q2),
                         blend_white(base_q2[15:8],alpha_q2),
                         blend_white(base_q2[7:0],alpha_q2)} : 24'd0;
    end
end
endmodule

module saixian_victory_atlas(input wire clk, input wire [11:0] addr,
                            output wire [31:0] bits);
`ifdef VICTORY_SIM
reg [31:0] memory [0:4095];
reg [31:0] read_bits;
initial $readmemh("src/user_source/hdl_source/saixian_victory_atlas.hex",memory);
always @(posedge clk) read_bits<=memory[addr];
assign bits=read_bits;
`else
EG_LOGIC_BRAM #(
 .DATA_WIDTH_A(32),.ADDR_WIDTH_A(12),.DATA_DEPTH_A(4096),
 .DATA_WIDTH_B(32),.ADDR_WIDTH_B(12),.DATA_DEPTH_B(4096),
 .BYTE_ENABLE(0),.MODE("SP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
 .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),
 .DEBUGGABLE("NO"),.PACKABLE("NO"),.FORCE_KEEP("OFF"),
 .INIT_FILE("../../user_source/hdl_source/saixian_victory_atlas.mif"),
 .FILL_ALL("NONE"),.IMPLEMENT("32K")
) u_rom(
 .doa(bits),.dob(),.dia(32'd0),.dib(32'd0),
 .cea(1'b1),.ocea(1'b0),.clka(clk),.wea(1'b0),.rsta(1'b0),
 .ceb(1'b0),.oceb(1'b0),.clkb(1'b0),.web(1'b0),.rstb(1'b0),
 .bea(1'b0),.beb(1'b0),.addra(addr),.addrb(12'd0)
);
`endif
endmodule
