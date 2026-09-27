// Blue victory -> red victory -> eight-runner ranking -> compact top three.
// Each K2 press advances from a held page; no automatic exit.
module saixian_battle_result_fx(
    input wire clk, rst, frame_tick, trigger,
    input wire select_blue, select_red, select_sprint,
    input wire [10:0] x_in,
    input wire [9:0] y_in,
    input wire de_in, vs_in,
    input wire [23:0] rgb_in,
    input wire sprint_background_valid,
    output wire busy,
    output wire sprint_active,
    output reg de_out, vs_out,
    output reg [23:0] rgb_out
);
// Uniform entry pipeline precomputes diagonal cuts before title slice mux.
// RGB, coordinates and sidebands always traverse the same stage.
reg [10:0] raster_x;
reg [9:0] raster_y;
reg raster_de, raster_vs;
reg [23:0] raster_rgb;
reg signed [12:0] cut_axis;
wire signed [12:0] input_title_u = $signed({2'b00,x_in})-13'sd448;
wire signed [12:0] input_title_v = $signed({3'b000,y_in})-13'sd322;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        raster_x<=0; raster_y<=0; raster_de<=0; raster_vs<=0;
        raster_rgb<=0; cut_axis<=0;
    end else begin
        raster_x<=x_in; raster_y<=y_in; raster_de<=de_in; raster_vs<=vs_in;
        raster_rgb<=rgb_in; cut_axis<=input_title_v+(input_title_u>>>3);
    end
end
localparam IDLE=3'd0, PLAY=3'd1, HOLD=3'd2,
           RANK_IN=3'd3, RANK_HOLD=3'd4,
           PODIUM_IN=3'd5, PODIUM_HOLD=3'd6,
           RED_PLAY=4'd7, RED_HOLD=4'd8;
reg [3:0] state;
reg pending;
reg [1:0] direct_pending;
reg auto_podium;
reg red_selected;
reg [8:0] frame_count;
reg [7:0] result_frame;
reg [11:0] wipe_edge, sheen_edge;
reg [4:0] title_drop;
reg [10:0] gold_line_edge;
assign busy = (state != IDLE) || pending || (direct_pending != 0);
wire [1:0] direct_choice = select_blue ? 2'd1 :
                           select_red ? 2'd2 :
                           select_sprint ? 2'd3 : direct_pending;
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
        state<=IDLE; pending<=0; direct_pending<=0; auto_podium<=0; red_selected<=0;
        frame_count<=0; result_frame<=0;
        wipe_edge<=0; sheen_edge<=0; title_drop<=24; gold_line_edge<=11'd220;
    end else begin
        // Latch UART pulses until the next video frame; the latest choice wins.
        if(select_blue) direct_pending<=2'd1;
        else if(select_red) direct_pending<=2'd2;
        else if(select_sprint) direct_pending<=2'd3;
        // Presses during animated transitions never queue a later skip.
        if(trigger && (state==IDLE || state==HOLD || state==RED_HOLD ||
                       state==RANK_HOLD || state==PODIUM_HOLD)) pending<=1;
        if(frame_tick) begin
            // Frame-rate accent follows the champion's entrance, then freezes.
            if(state==RANK_IN || state==IDLE) gold_line_edge<=11'd220;
            else if(state==PODIUM_IN && result_frame>=8'd56 &&
                    gold_line_edge<11'd1060) gold_line_edge<=gold_line_edge+11'd30;
            if(direct_choice!=0) begin
                direct_pending<=0; pending<=0;
                frame_count<=0; result_frame<=0;
                wipe_edge<=0; sheen_edge<=0; title_drop<=24;
                red_selected<=(direct_choice==2'd2);
                auto_podium<=(direct_choice==2'd3);
                case(direct_choice)
                    2'd1: state<=PLAY;
                    2'd2: state<=RED_PLAY;
                    default: state<=RANK_IN;
                endcase
            end else if(state==IDLE) begin
                if(pending || trigger) begin
                    state<=PLAY; pending<=0; frame_count<=0; result_frame<=0;
                    red_selected<=0;
                    wipe_edge<=0; sheen_edge<=0; title_drop<=24;
                end
            end else if(state==PLAY || state==RED_PLAY) begin
                pending<=0;
                if(frame_count==9'd359)
                    state<=(state==PLAY) ? HOLD : RED_HOLD;
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
            end else if(state==HOLD) begin
                if(pending || trigger) begin
                    state<=RED_PLAY; pending<=0; frame_count<=0;
                    wipe_edge<=0; sheen_edge<=0; title_drop<=24;
                    red_selected<=1;
                end
            end else if(state==RED_HOLD) begin
                if(pending || trigger) begin
                    state<=RANK_IN; pending<=0; result_frame<=0;
                end
            end else if(state==RANK_IN) begin
                pending<=0;
                if(result_frame==8'd143) begin
                    state<=RANK_HOLD;
                    if(auto_podium) result_frame<=0;
                end
                else result_frame<=result_frame+8'd1;
            end else if(state==RANK_HOLD) begin
                if(pending || trigger) begin
                    state<=PODIUM_IN; pending<=0; result_frame<=0; auto_podium<=0;
                end else if(auto_podium) begin
                    if(result_frame==8'd119) begin
                        state<=PODIUM_IN; result_frame<=0; auto_podium<=0;
                    end else result_frame<=result_frame+8'd1;
                end
            end else if(state==PODIUM_IN) begin
                pending<=0;
                if(result_frame==8'd95) state<=PODIUM_HOLD;
                else result_frame<=result_frame+8'd1;
            end else if(pending || trigger) begin
                state<=IDLE; pending<=0; frame_count<=0; result_frame<=0; auto_podium<=0;
                red_selected<=0;
            end
        end
    end
end

// Atlas rectangles: large Chinese title, VICTORY, intro, footer, subtitle,
// and the final K2 return prompt. Native-size, 2-bit antialiased typography.
reg [8:0] atlas_x;
reg [6:0] atlas_y;
reg ink_enable, red_ink_enable;
// Fixed vertical baseline: only the three slices move, avoiding a serial
// frame-offset/subtract/cut-selector chain on the synchronous ROM address.
wire [9:0] title_y = 10'd322;
// Three staggered diagonal title slices, settling into the original atlas.
// Displacements are frame-rate registers, outside the pixel arithmetic path.
reg signed [10:0] slice_origin_a, slice_origin_b, slice_origin_c;
// Signed origins are multiples of four/sixteen. Compute the high part
// directly, avoiding shift/subtract plus a second full-width offset adder.
function signed [10:0] slice_origin;
    input [8:0] f,onset;
    input reverse;
    reg [8:0] age;
    reg [6:0] coarse;
    reg [8:0] fine;
    begin
        age=f-onset;
        coarse=reverse ? 7'd90+{4'd0,age[2:0]} : 7'd110-{4'd0,age[2:0]};
        fine=reverse ? 9'd384+{5'd0,age[3:0]} : 9'd416-{5'd0,age[3:0]};
        if(f<onset) slice_origin=reverse ? -11'sd608 : -11'sd288;
        else if(age<8) slice_origin={coarse,4'b0};
        else if(age<16) slice_origin={fine,2'b0};
        else slice_origin=-11'sd448;
    end
endfunction
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
    if(rst) begin slice_origin_a<=-11'sd288; slice_origin_b<=-11'sd608; slice_origin_c<=-11'sd288; end
    else if(frame_tick) begin
        slice_origin_a<=slice_origin(next_frame,9'd90,1'b0);
        slice_origin_b<=slice_origin(next_frame,9'd98,1'b1);
        slice_origin_c<=slice_origin(next_frame,9'd106,1'b0);
        if(state==IDLE) begin slice_origin_a<=-11'sd288; slice_origin_b<=-11'sd608; slice_origin_c<=-11'sd288; end
    end
end
wire signed [12:0] title_u=$signed({2'b00,raster_x})-13'sd448;
wire signed [12:0] title_v=$signed({3'b000,raster_y})-$signed({3'b000,title_y});
// cut_axis is registered alongside the input raster.
wire signed [12:0] source_u_a=$signed({2'b00,raster_x})+slice_origin_a;
wire signed [12:0] source_u_b=$signed({2'b00,raster_x})+slice_origin_b;
wire signed [12:0] source_u_c=$signed({2'b00,raster_x})+slice_origin_c;
reg signed [12:0] source_u;
reg title_ready;
always @* begin
    source_u=title_u;
    title_ready=0;
    if(cut_axis<48) begin
        source_u=source_u_a;
        title_ready=(frame_count>=90);
    end else if(cut_axis<96) begin
        source_u=source_u_b;
        title_ready=(frame_count>=98);
    end else begin
        source_u=source_u_c;
        title_ready=(frame_count>=106);
    end
end
always @* begin
    atlas_x=0; ink_enable=0; red_ink_enable=0;
    if((state==PLAY || state==HOLD ||
        state==RED_PLAY || state==RED_HOLD) && raster_de) begin
        if(frame_count<65 && raster_x>=576 && raster_x<704 && raster_y>=332 && raster_y<364) begin
            atlas_x=raster_x-11'd192; ink_enable=1;
        end
        if(frame_count>=90) begin
            // Power-of-two-aligned bounds: exact signed interval tests without
            // serial arithmetic comparators after the title slice mux.
            if(title_ready && source_u[12:9]==0 && !(source_u[8] && source_u[7]) &&
               title_v[12:7]==0 && !(title_v[6] && title_v[5])) begin
                atlas_x=source_u[8:0]; ink_enable=1;
                red_ink_enable=red_selected && source_u[12:7]==0;
            end else if(raster_x>=576 && raster_x<704 && raster_y>=280 && raster_y<304) begin
                atlas_x=raster_x-11'd192; ink_enable=1;
            end else if(red_selected && raster_x>=576 && raster_x<704 &&
                        raster_y>=435 && raster_y<467) begin
                atlas_x=raster_x-11'd576;
                ink_enable=1; red_ink_enable=1;
            end else if(!red_selected && raster_x>=448 && raster_x<832 &&
                        raster_y>=435 && raster_y<467) begin
                atlas_x=raster_x-11'd448; ink_enable=1;
            end
        end
        if(frame_count>=130 && raster_x>=576 && raster_x<704 && raster_y>=546 && raster_y<570) begin
            atlas_x=raster_x-11'd192; ink_enable=1;
        end
        if((state==HOLD || state==RED_HOLD) &&
           raster_x>=576 && raster_x<704 && raster_y>=602 && raster_y<634) begin
            atlas_x=raster_x-11'd192; ink_enable=1;
        end
    end
end
// Vertical atlas address depends on the raster row, not the diagonal title
// slice's horizontal displacement. This cuts the previous 14-level setup path
// without changing which pixels receive ink.
always @* begin
    atlas_y=0;
    if(frame_count<65 && raster_y>=332 && raster_y<364)
        atlas_y=raster_y-10'd300;
    else if(frame_count>=90 && raster_y>=322 && raster_y<418)
        atlas_y=raster_y-10'd322;
    else if(frame_count>=90 && raster_y>=280 && raster_y<304)
        atlas_y=raster_y-10'd280;
    else if(frame_count>=90 && raster_y>=435 && raster_y<467)
        atlas_y=raster_y-10'd339;
    else if(frame_count>=130 && raster_y>=546 && raster_y<570)
        atlas_y=raster_y-10'd482;
    else if(raster_y>=602 && raster_y<634)
        atlas_y=raster_y-10'd506;
end
wire [31:0] atlas_word;

// Eight independently staggered, frame-rate-only slide positions. The pixel
// path only selects a registered displacement; it never computes easing.
reg [10:0] rank_shift [0:7];
reg [10:0] podium_shift [0:2];
integer si;
function [10:0] slide_shift;
    input [7:0] f;
    input [7:0] onset;
    reg [7:0] age;
    begin
        age=f-onset;
        if(f<onset) slide_shift=11'd1200;
        else if(age<8'd24) slide_shift=(8'd24-age)*11'd50;
        else slide_shift=0;
    end
endfunction
always @(posedge clk or posedge rst) begin
    if(rst) begin
        for(si=0;si<8;si=si+1) rank_shift[si]<=11'd1200;
        for(si=0;si<3;si=si+1) podium_shift[si]<=11'd1200;
    end else if(frame_tick) begin
        if(direct_choice==2'd3) begin
            for(si=0;si<8;si=si+1) rank_shift[si]<=11'd1200;
            for(si=0;si<3;si=si+1) podium_shift[si]<=11'd1200;
        end else begin
            if(state==RANK_IN)
                for(si=0;si<8;si=si+1)
                    rank_shift[si]<=slide_shift(result_frame,si*12);
            if(state==PODIUM_IN)
                for(si=0;si<3;si=si+1)
                    podium_shift[si]<=slide_shift(result_frame,(2-si)*16);
            if(state==IDLE) begin
                for(si=0;si<8;si=si+1) rank_shift[si]<=11'd1200;
                for(si=0;si<3;si=si+1) podium_shift[si]<=11'd1200;
            end
        end
    end
end

wire rank_mode = (state==RANK_IN || state==RANK_HOLD);
wire podium_mode = (state==PODIUM_IN || state==PODIUM_HOLD);
assign sprint_active = rank_mode || podium_mode;
reg [3:0] row_id;
reg [9:0] row_y;
reg [11:0] row_shift;
wire [10:0] row_hit;
assign row_hit[0]=rank_mode && raster_y>=143 && raster_y<187;
assign row_hit[1]=rank_mode && raster_y>=198 && raster_y<242;
assign row_hit[2]=rank_mode && raster_y>=253 && raster_y<297;
assign row_hit[3]=rank_mode && raster_y>=308 && raster_y<352;
assign row_hit[4]=rank_mode && raster_y>=363 && raster_y<407;
assign row_hit[5]=rank_mode && raster_y>=418 && raster_y<462;
assign row_hit[6]=rank_mode && raster_y>=473 && raster_y<517;
assign row_hit[7]=rank_mode && raster_y>=528 && raster_y<572;
assign row_hit[8]=podium_mode && raster_y>=180 && raster_y<276;
assign row_hit[9]=podium_mode && raster_y>=315 && raster_y<411;
assign row_hit[10]=podium_mode && raster_y>=450 && raster_y<546;
always @* begin
    // Disjoint vertical bands: one-hot OR rather than an eight-level
    // priority mux. Geometry and slide positions are unchanged.
    row_id={!(|row_hit),(|row_hit[7:4]),
            (row_hit[2]|row_hit[3]|row_hit[6]|row_hit[7]|row_hit[10]),
            (row_hit[1]|row_hit[3]|row_hit[5]|row_hit[7]|row_hit[9])};
    row_y=({10{row_hit[0]}}&10'd151)|({10{row_hit[1]}}&10'd206)|
          ({10{row_hit[2]}}&10'd261)|({10{row_hit[3]}}&10'd316)|
          ({10{row_hit[4]}}&10'd371)|({10{row_hit[5]}}&10'd426)|
          ({10{row_hit[6]}}&10'd481)|({10{row_hit[7]}}&10'd536)|
          ({10{row_hit[8]}}&10'd214)|({10{row_hit[9]}}&10'd349)|
          ({10{row_hit[10]}}&10'd484);
    row_shift=({12{row_hit[0]}}&{1'b0,rank_shift[0]})|({12{row_hit[1]}}&{1'b0,rank_shift[1]})|
              ({12{row_hit[2]}}&{1'b0,rank_shift[2]})|({12{row_hit[3]}}&{1'b0,rank_shift[3]})|
              ({12{row_hit[4]}}&{1'b0,rank_shift[4]})|({12{row_hit[5]}}&{1'b0,rank_shift[5]})|
              ({12{row_hit[6]}}&{1'b0,rank_shift[6]})|({12{row_hit[7]}}&{1'b0,rank_shift[7]})|
              ({12{row_hit[8]}}&({1'b0,podium_shift[0]}+12'd200))|
              ({12{row_hit[9]}}&({1'b0,podium_shift[1]}+12'd200))|
              ({12{row_hit[10]}}&({1'b0,podium_shift[2]}+12'd200));
end
// Stage 0 separates the displacement mux/add from the ROM address decode.
// Victory and passthrough pixels take the same extra clock.
reg [10:0] pre_x;
reg [9:0] pre_y, pre_row_y;
reg [11:0] pre_row_shift;
reg [11:0] pre_x_atlas;
reg [8:0] pre_header_x;
reg [7:0] pre_header_y;
reg [7:0] row_atlas_bias;
reg [3:0] pre_row_id;
reg pre_active, pre_hold, pre_rank, pre_podium;
always @* begin
    if(pre_rank) begin
        case(pre_row_id)
            0:row_atlas_bias=105;1:row_atlas_bias=78;
            2:row_atlas_bias=51;3:row_atlas_bias=24;
            4:row_atlas_bias=253;5:row_atlas_bias=226;
            6:row_atlas_bias=199;7:row_atlas_bias=172;
            default:row_atlas_bias=0;
        endcase
    end else begin
        case(pre_row_id)
            0:row_atlas_bias=42;1:row_atlas_bias=191;
            2:row_atlas_bias=84;default:row_atlas_bias=0;
        endcase
    end
end
wire [11:0] pre_row_x_virtual = {1'b0,pre_x} + pre_row_shift;
reg [8:0] pre_atlas_x, pre_frame_count;
reg [6:0] pre_atlas_y;
reg pre_de, pre_vs, pre_ink, pre_red_ink, pre_red;
reg [23:0] pre_rgb;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        pre_x<=0; pre_y<=0; pre_row_y<=0; pre_row_shift<=0;
        pre_x_atlas<=0;
        pre_header_x<=0;pre_header_y<=0;
        pre_atlas_x<=0; pre_atlas_y<=0; pre_frame_count<=0;
        pre_row_id<=8; pre_de<=0; pre_vs<=0; pre_ink<=0;
        pre_red_ink<=0; pre_red<=0;
        pre_active<=0; pre_hold<=0; pre_rank<=0; pre_podium<=0;
        pre_rgb<=0;
    end else begin
        pre_x<=raster_x; pre_y<=raster_y; pre_row_y<=row_y;
        pre_row_shift<=row_shift;
        // Subtract from x in parallel with row displacement selection,
        // rather than serializing y decode -> shift mux -> subtraction.
        pre_x_atlas<={1'b0,raster_x}-(rank_mode ? 12'd124 : 12'd384);
        pre_header_x<=raster_x-(rank_mode ? 11'd124 : 11'd184);
        pre_header_y<=raster_y+(rank_mode ? 8'd166 : 8'd154);
        pre_atlas_x<=atlas_x; pre_atlas_y<=atlas_y;
        pre_frame_count<=frame_count; pre_row_id<=row_id;
        pre_de<=raster_de; pre_vs<=raster_vs; pre_ink<=ink_enable;
        pre_red_ink<=red_ink_enable;
        pre_red<=red_selected && (state==RED_PLAY || state==RED_HOLD);
        pre_active<=(state==PLAY || state==HOLD ||
                     state==RED_PLAY || state==RED_HOLD);
        pre_hold<=(state==HOLD || state==RED_HOLD); pre_rank<=rank_mode;
        pre_podium<=podium_mode; pre_rgb<=raster_rgb;
    end
end
saixian_victory_atlas u_atlas(
    .clk(clk),.addr({pre_atlas_y,pre_atlas_x[8:4]}),.bits(atlas_word));
wire [15:0] red_word;
saixian_red_victory_atlas u_red_atlas(
    .clk(clk),.addr({pre_atlas_y,pre_atlas_x[6:3]}),.bits(red_word));
reg [8:0] result_atlas_x;
reg [7:0] result_atlas_y;
reg result_ink;
wire result_header_address=pre_rank ? (pre_y<10'd119) : (pre_y<10'd132);
always @* begin
    // Addresses in non-ink regions are don't-care. Do not gate the BRAM
    // address with the full clipping predicate; gate only the final alpha.
    result_atlas_x=result_header_address ? pre_header_x : pre_x_atlas+pre_row_shift;
    result_atlas_y=result_header_address ? pre_header_y : pre_y[7:0]+row_atlas_bias;
    result_ink=0;
    if(pre_de && (pre_rank || pre_podium)) begin
        if(pre_rank && pre_y>=10'd58 && pre_y<10'd90 &&
           pre_x>=11'd124 && pre_x<11'd636) begin
            result_ink=1;
        end else if(pre_podium && pre_y>=10'd70 && pre_y<10'd102 &&
                    pre_x>=11'd184 && pre_x<11'd696) begin
            result_ink=1;
        end else if(pre_row_id<8 && pre_rank &&
                    pre_y>=pre_row_y && pre_y<pre_row_y+10'd28 &&
                    pre_row_x_virtual>=12'd124 && pre_row_x_virtual<12'd636) begin
            result_ink=1;
        end else if(pre_row_id<3 && pre_podium &&
                    pre_y>=pre_row_y && pre_y<pre_row_y+10'd28 &&
                    pre_row_x_virtual>=12'd384 && pre_row_x_virtual<12'd896) begin
            result_ink=1;
        end
    end
end
wire [31:0] result_word;
saixian_sprint_atlas u_sprint_atlas(
    .clk(clk),.addr({result_atlas_y,result_atlas_x[8:4]}),.bits(result_word));

// Three ribboned medals are drawn from registered geometry, not bitmap ROM.
// Their octagonal rims and central star read clearly at 720p without spending
// another BRAM; the three cards keep their existing staggered entrance.
reg [9:0] medal_center_y, medal_top_y;
always @* begin
    case(pre_row_id)
        0: begin medal_center_y=10'd228; medal_top_y=10'd185; end
        1: begin medal_center_y=10'd363; medal_top_y=10'd320; end
        2: begin medal_center_y=10'd498; medal_top_y=10'd455; end
        default: begin medal_center_y=0; medal_top_y=0; end
    endcase
end
wire [11:0] medal_dx = (pre_row_x_virtual>=12'd270) ?
                        pre_row_x_virtual-12'd270 : 12'd270-pre_row_x_virtual;
wire [9:0] medal_dy = (pre_y>=medal_center_y) ?
                       pre_y-medal_center_y : medal_center_y-pre_y;
wire [9:0] ribbon_age = pre_y-medal_top_y;
wire medal_area = pre_podium && pre_row_id<3;
wire ribbon_left = pre_row_x_virtual>=12'd246+{4'd0,ribbon_age[9:2]} &&
                   pre_row_x_virtual<12'd257+{4'd0,ribbon_age[9:2]};
wire ribbon_right = pre_row_x_virtual>=12'd282-{4'd0,ribbon_age[9:2]} &&
                    pre_row_x_virtual<12'd293-{4'd0,ribbon_age[9:2]};
wire medal_ribbon = medal_area && pre_y>=medal_top_y &&
                    ribbon_age<10'd45 && (ribbon_left || ribbon_right);
// The radius predicates bound both operands to 0..31. A six-bit sum
// is exact in that region; outside it the shape is masked off.
wire [5:0] medal_radius_sum={1'b0,medal_dx[4:0]}+{1'b0,medal_dy[4:0]};
wire medal_outer = medal_area && medal_dx<=11'd31 &&
                   medal_dy<=10'd31 && medal_radius_sum<=6'd44;
wire medal_inner = medal_area && medal_dx<=11'd24 &&
                   medal_dy<=10'd24 && medal_radius_sum<=6'd34;
wire medal_star = medal_inner &&
                  medal_radius_sum<=6'd13;

// Stage 1: geometry coordinates and synchronous ROM read in parallel.
reg [10:0] xq;
reg [9:0] yq;
reg [11:0] row_x_virtual_q;
reg [11:0] diagonal_q, edge_q, sheen_q;
reg [10:0] center_distance_q;
reg [8:0] fq;
reg active_q, hold_q, de_q, vs_q, ink_q, red_ink_q, red_q, result_ink_q;
reg [3:0] subpixel_q, result_subpixel_q;
reg rank_q, podium_q;
reg medal_ribbon_q, medal_outer_q, medal_inner_q, medal_star_q;
reg result_header_q, result_header_rule_q, podium_guide_q;
reg rank_panel_q, rank_edge_q, rank_stripe_q;
reg podium_panel_q, podium_time_q, podium_edge_q, gold_line_q;
reg result_bottom_rule_q;
reg [3:0] row_q;
reg [23:0] rgb_q;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        xq<=0; yq<=0; row_x_virtual_q<=0;
        diagonal_q<=0; edge_q<=0; sheen_q<=0;
        center_distance_q<=0; fq<=0; active_q<=0; hold_q<=0;
        de_q<=0; vs_q<=0; ink_q<=0; red_ink_q<=0;
        red_q<=0; result_ink_q<=0;
        subpixel_q<=0; result_subpixel_q<=0; rgb_q<=0;
        rank_q<=0; podium_q<=0; row_q<=0;
        medal_ribbon_q<=0; medal_outer_q<=0;
        medal_inner_q<=0; medal_star_q<=0;
        result_header_q<=0; result_header_rule_q<=0; podium_guide_q<=0;
        rank_panel_q<=0; rank_edge_q<=0; rank_stripe_q<=0;
        podium_panel_q<=0; podium_time_q<=0; podium_edge_q<=0;
        gold_line_q<=0; result_bottom_rule_q<=0;
    end else begin
        xq<=pre_x; yq<=pre_y; row_x_virtual_q<=pre_row_x_virtual;
        diagonal_q<={1'b0,pre_x}+{3'b0,pre_y[9:1]};
        center_distance_q <= (pre_x>=640) ? pre_x-11'd640 : 11'd640-pre_x;
        edge_q<=wipe_edge+12'd121; sheen_q<=sheen_edge;
        fq<=pre_frame_count; active_q<=pre_active;
        hold_q<=pre_hold;
        de_q<=pre_de; vs_q<=pre_vs; ink_q<=pre_ink;
        red_ink_q<=pre_red_ink; red_q<=pre_red;
        subpixel_q<=pre_atlas_x[3:0]; rgb_q<=pre_rgb;
        result_ink_q<=result_ink;
        result_subpixel_q<=result_atlas_x[3:0];
        rank_q<=pre_rank; podium_q<=pre_podium; row_q<=pre_row_id;
        medal_ribbon_q<=medal_ribbon; medal_outer_q<=medal_outer;
        medal_inner_q<=medal_inner; medal_star_q<=medal_star;
        // Register all result-card geometry before the color-priority mux.
        // This keeps the 75 MHz pixel path clear of a long compare chain.
        result_header_q <= (pre_rank && pre_x>=11'd72 && pre_x<11'd688 &&
                            pre_y>=10'd37 && pre_y<10'd119) ||
                           (pre_podium && pre_x>=11'd20 && pre_x<11'd860 &&
                            pre_y>=10'd48 && pre_y<10'd132);
        result_header_rule_q <= (pre_rank && pre_y==10'd121 &&
                                 pre_x>=11'd72 && pre_x<11'd688) ||
                                (pre_podium && pre_y==10'd135 &&
                                 pre_x>=11'd20 && pre_x<11'd860);
        podium_guide_q <= pre_podium && pre_x<11'd884 &&
                          (pre_y==10'd164 || pre_y==10'd299 ||
                           pre_y==10'd434 || pre_y==10'd569);
        rank_panel_q <= pre_rank && pre_row_id<8 &&
                        pre_row_x_virtual>=12'd72 && pre_row_x_virtual<12'd688;
        rank_edge_q <= pre_row_x_virtual<12'd78 ||
                       pre_row_x_virtual>=12'd682;
        rank_stripe_q <= (pre_y[2:0]==0) && pre_row_id>=3;
        podium_panel_q <= pre_podium && pre_row_id<3 &&
                          pre_row_x_virtual>=12'd220 &&
                          pre_row_x_virtual<12'd1060;
        podium_time_q <= pre_row_x_virtual>=12'd736 &&
                         pre_row_x_virtual<12'd944;
        podium_edge_q <= pre_row_x_virtual<12'd226 ||
                         pre_row_x_virtual>=12'd1054;
        gold_line_q <= pre_row_id==0 && pre_y>=10'd180 &&
                       pre_y<10'd183 && pre_row_x_virtual>=12'd220 &&
                       pre_row_x_virtual<gold_line_edge;
        result_bottom_rule_q <= pre_y==10'd660 &&
                                pre_x>=11'd72 && pre_x<11'd688;
    end
end

reg [30:0] scene_token;
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
    scene_token=rgb_q;
    if(active_q) begin
        // Restrained dark-blue field; diagonal architecture, not a red/blue split.
        scene_token=31'h41000000;
        if(center_distance_q<448) scene_token=31'h42000000;
        if(center_distance_q<256) scene_token=31'h43000000;
        if(diagonal_q[7:0]<2) scene_token=31'h44000000;
        if((yq==46 || yq==674) && xq>=48 && xq<1232) scene_token=31'h45000000;
        if(fq<65 && (yq==300 || yq==438) && xq>=440 && xq<840)
            scene_token=31'h46000000;
        if(plate) begin
            scene_token=31'h47000000;
            if(center_distance_q<448) scene_token=31'h48000000;
            if(center_distance_q<256) scene_token=31'h49000000;
            if(diagonal_q[4:0]==0) scene_token=31'h4a000000;
            if(yq<244 || yq>=494 || diagonal_q==608 || diagonal_q==1091)
                scene_token=31'h46000000;
            if(fq>=156 && fq<216 && diagonal_q>=sheen_q && diagonal_q<sheen_q+12'd72)
                scene_token=31'h4b000000;
        end
        if(fq>=50 && fq<108 && yq>=218 && yq<520 &&
           diagonal_q>=edge_q && diagonal_q<edge_q+12'd8) scene_token=31'h4c000000;
        if(shield) scene_token=shield_inner ? 31'h41000000 : 31'h46000000;
        if(shield && badge_y) scene_token=31'h46000000;
        if(fq>=78 && yq>=163 && yq<165 &&
          ((xq>=405 && xq<539) || (xq>=741 && xq<875))) scene_token=31'h4d000000;
        if(fq>=130 && yq==590 && xq>=600 && xq<680) scene_token=31'h45000000;
        // Fixed decorative dashes; final hold has no running counters/motion.
        if((yq==100 && xq>=84 && xq<103) ||
           (yq==536 && xq>=1050 && xq<1063) ||
           (yq==646 && xq>=310 && xq<326)) scene_token=31'h4e000000;
        if(hold_q && yq>=672 && yq<674 && xq>=48 && xq<1232) scene_token=31'h46000000;
    end
    if(rank_q || podium_q) begin
        // A real running track stays visible behind FPGA-native timing data.
        // When the dedicated TF background is missing, retain a clean dark
        // fallback instead of displaying an unrelated carousel photograph.
        scene_token=sprint_background_valid ?
                  {1'b0,rgb_q[23:17],1'b0,rgb_q[15:9],1'b0,rgb_q[7:1]} :
                  31'h4f000000;
        if(result_header_q)
            scene_token=31'h50000000;
        if(result_header_rule_q)
            scene_token=31'h51000000;
        // Quiet track-guide lines keep the three result cards grounded.
        if(podium_guide_q)
            scene_token=31'h52000000;
        if(rank_panel_q) begin
            case(row_q)
                0: scene_token=31'h53000000;
                1: scene_token=31'h54000000;
                2: scene_token=31'h55000000;
                default: scene_token=31'h56000000;
            endcase
            if(rank_edge_q)
                scene_token=31'h57000000;
            if(rank_stripe_q)
                scene_token=31'h58000000;
        end
        if(podium_panel_q) begin
            case(row_q)
                0: scene_token=31'h59000000;
                1: scene_token=31'h5a000000;
                default: scene_token=31'h5b000000;
            endcase
            if(podium_time_q)
                scene_token=31'h5c000000;
            if(podium_edge_q) begin
                case(row_q)
                    0: scene_token=31'h5d000000;
                    1: scene_token=31'h5e000000;
                    default: scene_token=31'h5f000000;
                endcase
            end
            if(gold_line_q)
                scene_token=31'h60000000;
        end
        // Ceremony-style medal: blue ribbon, faceted rim and a bright centre.
        if(podium_q && row_q<3) begin
            if(medal_ribbon_q) scene_token=31'h61000000;
            if(medal_outer_q) begin
                case(row_q)
                    0: scene_token=31'h60000000;
                    1: scene_token=31'h62000000;
                    default: scene_token=31'h63000000;
                endcase
            end
            if(medal_inner_q) begin
                case(row_q)
                    0: scene_token=31'h64000000;
                    1: scene_token=31'h65000000;
                    default: scene_token=31'h66000000;
                endcase
            end
            if(medal_star_q) scene_token=31'h67000000;
        end
        if(result_bottom_rule_q)
            scene_token=31'h51000000;
    end
end

reg [23:0] scene_palette [0:63]; /* fehdl force_ram=1, ram_style="bram" */
reg [23:0] scene_palette_rgb;
reg [30:0] scene_token_q;
integer palette_i;
initial begin
    for(palette_i=0;palette_i<64;palette_i=palette_i+1) scene_palette[palette_i]=0;
    scene_palette[1]=24'h0B1723;
    scene_palette[2]=24'h0E202E;
    scene_palette[3]=24'h102735;
    scene_palette[4]=24'h183341;
    scene_palette[5]=24'h526574;
    scene_palette[6]=24'h54D5F6;
    scene_palette[7]=24'h196580;
    scene_palette[8]=24'h1B708C;
    scene_palette[9]=24'h207C97;
    scene_palette[10]=24'h2A819B;
    scene_palette[11]=24'h398FA7;
    scene_palette[12]=24'hDDF9FF;
    scene_palette[13]=24'h4098B0;
    scene_palette[14]=24'h276078;
    scene_palette[15]=24'h0C1825;
    scene_palette[16]=24'h163245;
    scene_palette[17]=24'h58C4E2;
    scene_palette[18]=24'h254252;
    scene_palette[19]=24'h725622;
    scene_palette[20]=24'h506473;
    scene_palette[21]=24'h73503B;
    scene_palette[22]=24'h1D3D51;
    scene_palette[23]=24'h6DB9D1;
    scene_palette[24]=24'h28526A;
    scene_palette[25]=24'h30414A;
    scene_palette[26]=24'h253F50;
    scene_palette[27]=24'h35404A;
    scene_palette[28]=24'h182D3A;
    scene_palette[29]=24'hE4BD65;
    scene_palette[30]=24'hBBD4E2;
    scene_palette[31]=24'hCB916B;
    scene_palette[32]=24'hF7D77A;
    scene_palette[33]=24'h28648B;
    scene_palette[34]=24'hE4EDF2;
    scene_palette[35]=24'hE3AC7B;
    scene_palette[36]=24'hD49B20;
    scene_palette[37]=24'h9EAFB9;
    scene_palette[38]=24'hB56A38;
    scene_palette[39]=24'hFFF4D0;
end
always @(posedge clk) scene_palette_rgb<=scene_palette[scene_token_q[29:24]];

// Stage 2: resolve ROM bit-pair and register geometry before alpha blending.
wire [4:0] bit_offset = {~subpixel_q,1'b0};
wire [3:0] red_bit_offset = {~subpixel_q[2:0],1'b0};
wire [4:0] result_bit_offset = {~result_subpixel_q,1'b0};
reg [1:0] alpha_q2;
reg [23:0] base_q2;
reg de_q2, vs_q2, red_q2;
reg [1:0] victory_alpha,red_alpha,result_alpha;
reg victory_mask,red_mask,result_mask;
reg [23:0] scene_delay;
reg de_delay,vs_delay,red_delay;
reg [31:0] atlas_word_q,result_word_q;
reg [15:0] red_word_q;
reg [4:0] bit_offset_q,result_bit_offset_q;
reg [3:0] red_bit_offset_q;
reg ink_raw,red_ink_raw,result_ink_raw,de_raw,vs_raw,red_raw;
reg [23:0] scene_raw;
reg scene_palette_valid;
reg [79:0] words_stage0;
reg [13:0] offsets_stage0;
reg [5:0] flags_stage0;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        alpha_q2<=0; base_q2<=0; de_q2<=0; vs_q2<=0; red_q2<=0;
        victory_alpha<=0;red_alpha<=0;result_alpha<=0;
        victory_mask<=0;red_mask<=0;result_mask<=0;
        scene_delay<=0;de_delay<=0;vs_delay<=0;red_delay<=0;
        atlas_word_q<=0;result_word_q<=0;red_word_q<=0;
        bit_offset_q<=0;result_bit_offset_q<=0;red_bit_offset_q<=0;
        ink_raw<=0;red_ink_raw<=0;result_ink_raw<=0;de_raw<=0;vs_raw<=0;red_raw<=0;scene_raw<=0;scene_palette_valid<=0;
        scene_token_q<=0;words_stage0<=0;offsets_stage0<=0;flags_stage0<=0;
    end else begin
        // Register the palette index before BRAM addressing; delay glyph
        // words and all metadata equally. This cuts colour priority decoding
        // away from the physical RAM setup path without another line buffer.
        scene_token_q<=scene_token;
        words_stage0<={atlas_word,red_word,result_word};
        offsets_stage0<={bit_offset,red_bit_offset,result_bit_offset};
        flags_stage0<={ink_q,red_ink_q,result_ink_q,de_q,vs_q,red_q};
        // Isolate physical ROM-bank selection from the variable bit-pair mux.
        atlas_word_q<=words_stage0[79:48];red_word_q<=words_stage0[47:32];result_word_q<=words_stage0[31:0];
        bit_offset_q<=offsets_stage0[13:9];red_bit_offset_q<=offsets_stage0[8:5];result_bit_offset_q<=offsets_stage0[4:0];
        {ink_raw,red_ink_raw,result_ink_raw,de_raw,vs_raw,red_raw}<=flags_stage0;
        scene_raw<=scene_token_q[23:0];scene_palette_valid<=scene_token_q[30];
        victory_alpha<=atlas_word_q >> bit_offset_q;
        red_alpha<=red_word_q >> red_bit_offset_q;
        result_alpha<=result_word_q >> result_bit_offset_q;
        victory_mask<=ink_raw;red_mask<=red_ink_raw;result_mask<=result_ink_raw;
        scene_delay<=scene_palette_valid ? scene_palette_rgb : scene_raw;de_delay<=de_raw;vs_delay<=vs_raw;red_delay<=red_raw;
        alpha_q2<=result_mask ? result_alpha : red_mask ? red_alpha : victory_mask ? victory_alpha : 2'd0;
        base_q2<=scene_delay; de_q2<=de_delay; vs_q2<=vs_delay; red_q2<=red_delay;
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
// A wire-only palette rotation reuses the existing geometry and white alpha.
// Blue cyan becomes red/coral while the dark field stays dark red.
wire [23:0] winner_base = red_q2 ?
    {base_q2[7:0],base_q2[23:16],{1'b0,base_q2[23:17]}} : base_q2;
// Final RGB/DE/VS share eight clock stages (including entry and stage 0).
always @(posedge clk or posedge rst) begin
    if(rst) begin de_out<=0; vs_out<=0; rgb_out<=0; end
    else begin
        de_out<=de_q2; vs_out<=vs_q2;
        rgb_out<=de_q2 ? {blend_white(winner_base[23:16],alpha_q2),
                         blend_white(winner_base[15:8],alpha_q2),
                         blend_white(winner_base[7:0],alpha_q2)} : 24'd0;
    end
end
endmodule

module saixian_red_victory_atlas(input wire clk, input wire [10:0] addr,
                                 output wire [15:0] bits);
`ifdef VICTORY_SIM
reg [15:0] memory [0:2047];
reg [15:0] read_bits;
initial $readmemh("src/user_source/hdl_source/saixian_red_victory_atlas.hex",memory);
always @(posedge clk) read_bits<=memory[addr];
assign bits=read_bits;
`else
EG_LOGIC_BRAM #(
 .DATA_WIDTH_A(16),.ADDR_WIDTH_A(11),.DATA_DEPTH_A(2048),
 .DATA_WIDTH_B(16),.ADDR_WIDTH_B(11),.DATA_DEPTH_B(2048),
 .BYTE_ENABLE(0),.MODE("SP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
 .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),
 .DEBUGGABLE("NO"),.PACKABLE("NO"),.FORCE_KEEP("OFF"),
 .INIT_FILE("../../user_source/hdl_source/saixian_red_victory_atlas.mif"),
 .FILL_ALL("NONE"),.IMPLEMENT("32K")
) u_rom(
 .doa(bits),.dob(),.dia(16'd0),.dib(16'd0),
 .cea(1'b1),.ocea(1'b0),.clka(clk),.wea(1'b0),.rsta(1'b0),
 .ceb(1'b0),.oceb(1'b0),.clkb(1'b0),.web(1'b0),.rstb(1'b0),
 .bea(1'b0),.beb(1'b0),.addra(addr),.addrb(11'd0)
);
`endif
endmodule

module saixian_sprint_atlas(input wire clk, input wire [12:0] addr,
                            output wire [31:0] bits);
`ifdef VICTORY_SIM
reg [31:0] memory [0:8191];
reg [31:0] read_bits;
initial $readmemh("src/user_source/hdl_source/saixian_sprint_atlas.hex",memory);
always @(posedge clk) read_bits<=memory[addr];
assign bits=read_bits;
`else
EG_LOGIC_BRAM #(
 .DATA_WIDTH_A(32),.ADDR_WIDTH_A(13),.DATA_DEPTH_A(8192),
 .DATA_WIDTH_B(32),.ADDR_WIDTH_B(13),.DATA_DEPTH_B(8192),
 .BYTE_ENABLE(0),.MODE("SP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
 .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),
 .DEBUGGABLE("NO"),.PACKABLE("NO"),.FORCE_KEEP("OFF"),
 .INIT_FILE("../../user_source/hdl_source/saixian_sprint_atlas.mif"),
 .FILL_ALL("NONE"),.IMPLEMENT("32K")
) u_rom(
 .doa(bits),.dob(),.dia(32'd0),.dib(32'd0),
 .cea(1'b1),.ocea(1'b0),.clka(clk),.wea(1'b0),.rsta(1'b0),
 .ceb(1'b0),.oceb(1'b0),.clkb(1'b0),.web(1'b0),.rstb(1'b0),
 .bea(1'b0),.beb(1'b0),.addra(addr),.addrb(13'd0)
);
`endif
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
