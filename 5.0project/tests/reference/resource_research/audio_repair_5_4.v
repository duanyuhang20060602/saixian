// 48 kHz signed-16 stereo repair. FIR uses one shared multiplier/history RAM.
// Input spacing >=360 clocks; production 48 kHz spacing is >1500 clocks.
// Sample-aligned dry/wet delay: 32 samples (666.7 us), ~335 processing clocks.
module reference_audio_repair #(parameter PACKED_HISTORY=0)(
    input wire clk, rst, clear, sample_valid, enable,
    input wire signed [15:0] left_in, right_in,
    output reg signed [15:0] left_out, right_out,
    output reg out_valid
);
reg clear_q;
always @(posedge clk or posedge rst)
 if(rst)clear_q<=0;else clear_q<=clear;
reg [3:0] front_phase;
reg [1:0] history_count;
reg have_neighbors;
reg signed [15:0] before_l,before_r,after_l,after_r;
reg signed [19:0] threshold_l,threshold_r;
reg [15:0] spike_before_abs,spike_after_abs;
reg signed [15:0] l1,l2,r1,r2,clean_l,clean_r,hp_l,hp_r,center_l,center_r;
reg signed [15:0] aligned_l,aligned_r,part_a_l,part_a_r,part_b_l,part_b_r;
reg signed [31:0] dc_l,dc_r;
wire front_right=front_phase==4 || front_phase==8;
wire signed [15:0] front_before=front_right ? before_r : before_l;
wire signed [15:0] front_after=front_right ? after_r : after_l;
wire signed [15:0] front_center=front_right ? center_r : center_l;
wire signed [19:0] front_threshold=front_right ? threshold_r : threshold_l;
wire signed [15:0] front_clean=front_right ? clean_r : clean_l;
wire signed [31:0] front_dc=front_right ? dc_r : dc_l;
wire signed [32:0] dc_error=$signed({front_clean,16'd0})-$signed(front_dc);
wire signed [32:0] dc_next=$signed(front_dc)+(dc_error>>>11);
// Register the neighbor differences, then the spike decision. This keeps
// the original decision/rounding but meets B's 100 MHz clock.
reg signed [17:0] click_d0_l,click_d1_l,click_n_l,click_avg_l;
reg signed [17:0] click_d0_r,click_d1_r,click_n_r,click_avg_r;
reg click_l,click_r;
wire signed [17:0] click_d0=front_right ? click_d0_r:click_d0_l;
wire signed [17:0] click_d1=front_right ? click_d1_r:click_d1_l;
wire signed [17:0] click_n=front_right ? click_n_r:click_n_l;
wire click_decision_l=((click_d0_l>threshold_l && click_d1_l>threshold_l) ||
 (click_d0_l < -threshold_l && click_d1_l < -threshold_l)) && click_n_l<256 && click_n_l > -256;
wire click_decision_r=((click_d0_r>threshold_r && click_d1_r>threshold_r) ||
 (click_d0_r < -threshold_r && click_d1_r < -threshold_r)) && click_n_r<256 && click_n_r > -256;
wire signed [15:0] spike_before=front_phase==2 ? before_r : before_l;
wire signed [15:0] spike_after=front_phase==2 ? after_r : after_l;
wire [15:0] spike_before_magnitude=spike_before[15] ? -spike_before : spike_before;
wire [15:0] spike_after_magnitude=spike_after[15] ? -spike_after : spike_after;
wire signed [19:0] front_spike=20'sd1024+(({4'd0,spike_before_abs}+{4'd0,spike_after_abs})<<1);
reg [8:0] wet,wet_q,aligned_wet;
reg [5:0] write_index,head_index,read_index;
reg [6:0] history_samples;
reg [4:0] tap_index;
reg [4:0] state;
localparam IDLE=0,READ_A=1,WAIT_A=2,GET_A=3,READ_B=4,WAIT_B=5,
    GET_B=6,MUL_L=7,MUL_R=8,NEXT=9,FILTER=10,PEAK=11,BLEND=12,OUTPUT_SAMPLE=13,PEAK_R=14,BLEND_R=15,PREP_MUL=16;
wire [5:0] reverse_age=6'd62-{1'b0,tap_index};
wire memory_write=front_phase==9 && !rst && !clear_q;
wire [63:0] memory_q;
reference_repair_history_ram #(.PACKED(PACKED_HISTORY)) history_ram(clk,memory_write,write_index,read_index,
    {center_r,center_l,hp_r,hp_l},memory_q);
reg product_valid,product_channel;
reg signed [28:0] product;
reg signed [16:0] pair_q;reg signed [11:0] coefficient_q;
reg signed [29:0] accumulator_l,accumulator_r;
reg signed [17:0] filtered_l,filtered_r;
reg signed [15:0] denoised_l,denoised_r;
wire blend_phase=state==PEAK_R || state==BLEND;
wire right_channel=state==MUL_L || state==BLEND;
wire signed [15:0] operand_a=blend_phase ? (right_channel ? denoised_r : denoised_l) : (right_channel ? part_a_r : part_a_l);
wire signed [15:0] operand_b=blend_phase ? (right_channel ? aligned_r : aligned_l) :
                                           (tap_index==31 ? 16'sd0 : (right_channel ? part_b_r : part_b_l));
wire signed [16:0] operand_b_adjusted={operand_b[15]^blend_phase,operand_b^{16{blend_phase}}};
wire signed [16:0] shared_pair=$signed({operand_a[15],operand_a})+operand_b_adjusted+blend_phase;
wire signed [11:0] shared_coefficient=blend_phase ? $signed({3'd0,aligned_wet}) : coefficient(tap_index);
wire signed [15:0] shared_peak=peak_protect(state==PEAK_R ? filtered_r : filtered_l);
reg signed [26:0] blend_l;

function signed [15:0] saturate;
    input signed [32:0] value;
    begin
        if(value>32767) saturate=16'sh7fff;
        else if(value < -32768) saturate=16'sh8000;
        else saturate=value[15:0];
    end
endfunction
function signed [15:0] peak_protect;
    input signed [17:0] value;
    reg signed [18:0] limited;
    begin
        if(value>31500) limited=19'sd31500+(($signed({value[17],value})-19'sd31500)>>>4);
        else if(value < -31500) limited=-19'sd31500-((-$signed({value[17],value})-19'sd31500)>>>4);
        else limited=value;
        peak_protect=saturate(limited);
    end
endfunction
function signed [15:0] declick;
    input signed [15:0] before_sample,center_sample,after_sample;
    input signed [19:0] threshold;
    reg signed [17:0] d0,d1,neighbors,average;
    begin
        d0=$signed(center_sample)-$signed(before_sample);
        d1=$signed(center_sample)-$signed(after_sample);
        neighbors=$signed(before_sample)-$signed(after_sample);
        average=($signed(before_sample)+$signed(after_sample))>>>1;
        if (((d0>threshold && d1>threshold) || (d0 < -threshold && d1 < -threshold)) &&
            neighbors<256 && neighbors > -256) declick=average[15:0];
        else declick=center_sample;
    end
endfunction
function signed [19:0] spike_threshold;
    input signed [15:0] before_sample,after_sample;
    reg signed [16:0] before_abs,after_abs;
    begin
        before_abs=before_sample<0 ? -$signed({before_sample[15],before_sample}) : $signed(before_sample);
        after_abs=after_sample<0 ? -$signed({after_sample[15],after_sample}) : $signed(after_sample);
        spike_threshold=20'sd1024+((before_abs+after_abs)<<1);
    end
endfunction
// Q12 symmetric 63-tap FIR, full sum exactly 4096.
function signed [11:0] coefficient;
    input [4:0] index;
    begin
        case(index)
            0: coefficient=12'sd3;
            1: coefficient=12'sd0;
            2: coefficient=-12'sd3;
            3: coefficient=-12'sd5;
            4: coefficient=-12'sd3;
            5: coefficient=12'sd1;
            6: coefficient=12'sd7;
            7: coefficient=12'sd10;
            8: coefficient=12'sd5;
            9: coefficient=-12'sd6;
            10: coefficient=-12'sd18;
            11: coefficient=-12'sd19;
            12: coefficient=-12'sd5;
            13: coefficient=12'sd18;
            14: coefficient=12'sd36;
            15: coefficient=12'sd31;
            16: coefficient=12'sd0;
            17: coefficient=-12'sd42;
            18: coefficient=-12'sd65;
            19: coefficient=-12'sd45;
            20: coefficient=12'sd18;
            21: coefficient=12'sd88;
            22: coefficient=12'sd113;
            23: coefficient=12'sd57;
            24: coefficient=-12'sd67;
            25: coefficient=-12'sd190;
            26: coefficient=-12'sd213;
            27: coefficient=-12'sd65;
            28: coefficient=12'sd250;
            29: coefficient=12'sd643;
            30: coefficient=12'sd967;
            default: coefficient=12'sd1094;
        endcase
    end
endfunction

always @(posedge clk or posedge rst) begin
    if(rst) begin
        click_d0_l<=0;click_d1_l<=0;click_n_l<=0;click_avg_l<=0;
        click_d0_r<=0;click_d1_r<=0;click_n_r<=0;click_avg_r<=0;click_l<=0;click_r<=0;
        front_phase<=0;history_count<=0;l1<=0;l2<=0;r1<=0;r2<=0;
        spike_before_abs<=0;spike_after_abs<=0;
        have_neighbors<=0;before_l<=0;before_r<=0;after_l<=0;after_r<=0;threshold_l<=0;threshold_r<=0;
        dc_l<=0;dc_r<=0;wet<=0;wet_q<=0;aligned_wet<=0;
        left_out<=0;right_out<=0;out_valid<=0;
        aligned_l<=0;aligned_r<=0;center_l<=0;center_r<=0;
        clean_l<=0;clean_r<=0;hp_l<=0;hp_r<=0;
        pair_q<=0;coefficient_q<=0;
        product_valid<=0;product_channel<=0;accumulator_l<=0;accumulator_r<=0;
        state<=IDLE;tap_index<=0;write_index<=0;head_index<=0;read_index<=0;history_samples<=0;
    end else if(clear_q) begin
        click_d0_l<=0;click_d1_l<=0;click_n_l<=0;click_avg_l<=0;
        click_d0_r<=0;click_d1_r<=0;click_n_r<=0;click_avg_r<=0;click_l<=0;click_r<=0;
        front_phase<=0;history_count<=0;l1<=0;l2<=0;r1<=0;r2<=0;
        spike_before_abs<=0;spike_after_abs<=0;
        have_neighbors<=0;before_l<=0;before_r<=0;after_l<=0;after_r<=0;threshold_l<=0;threshold_r<=0;
        dc_l<=0;dc_r<=0;wet<=enable ? 9'd256 : 9'd0;wet_q<=0;aligned_wet<=0;
        left_out<=0;right_out<=0;out_valid<=0;
        aligned_l<=0;aligned_r<=0;center_l<=0;center_r<=0;
        clean_l<=0;clean_r<=0;hp_l<=0;hp_r<=0;
        pair_q<=0;coefficient_q<=0;
        product_valid<=0;product_channel<=0;accumulator_l<=0;accumulator_r<=0;
        state<=IDLE;tap_index<=0;write_index<=0;head_index<=0;read_index<=0;history_samples<=0;
    end else begin
        if(front_phase!=0) front_phase<=front_phase==9 ? 0 : front_phase+1'b1;
        out_valid<=0;product_valid<=0;
        if(state==MUL_L || state==MUL_R || state==BLEND || state==BLEND_R)
            product<=pair_q*coefficient_q;
        if(state==PREP_MUL || state==MUL_L || state==PEAK_R || state==BLEND)begin
            pair_q<=shared_pair;coefficient_q<=shared_coefficient;
        end
        if(sample_valid) begin
            l2<=l1;l1<=left_in;r2<=r1;r1<=right_in;
            center_l<=l1;center_r<=r1;
            if(history_count!=2) history_count<=history_count+1'b1;
            before_l<=l2;before_r<=r2;after_l<=left_in;after_r<=right_in;
            front_phase<=1;
            have_neighbors<=history_count==2;
            if(enable && wet<256) wet<=wet+1'b1;
            else if(!enable && wet!=0) wet<=wet-1'b1;
        end
        case(front_phase)
            1: begin spike_before_abs<=spike_before_magnitude;spike_after_abs<=spike_after_magnitude;
                click_d0_l<=$signed(center_l)-$signed(before_l);click_d1_l<=$signed(center_l)-$signed(after_l);
                click_n_l<=$signed(before_l)-$signed(after_l);click_avg_l<=($signed(before_l)+$signed(after_l))>>>1;
                click_d0_r<=$signed(center_r)-$signed(before_r);click_d1_r<=$signed(center_r)-$signed(after_r);
                click_n_r<=$signed(before_r)-$signed(after_r);click_avg_r<=($signed(before_r)+$signed(after_r))>>>1;
            end
            2: begin threshold_l<=front_spike;spike_before_abs<=spike_before_magnitude;spike_after_abs<=spike_after_magnitude;end
            3: begin threshold_r<=front_spike;click_l<=click_decision_l;end
            4: click_r<=click_decision_r;
            5: clean_l<=have_neighbors && click_l ? click_avg_l[15:0]:center_l;
            6: clean_r<=have_neighbors && click_r ? click_avg_r[15:0]:center_r;
            7: begin dc_l<=dc_next;hp_l<=saturate(dc_error>>>16);end
            8: begin dc_r<=dc_next;hp_r<=saturate(dc_error>>>16);wet_q<=wet;end
            default: ;
        endcase
        if(front_phase==9) begin
            head_index<=write_index;write_index<=write_index+1'b1;
            if(history_samples<63) history_samples<=history_samples+1'b1;
            aligned_wet<=wet_q;tap_index<=0;accumulator_l<=0;accumulator_r<=0;state<=READ_A;
        end
        if(product_valid) begin
            if(product_channel) accumulator_r<=accumulator_r+$signed(product);
            else accumulator_l<=accumulator_l+$signed(product);
        end
        case(state)
            READ_A: begin read_index<=head_index-{1'b0,tap_index};state<=WAIT_A;end
            WAIT_A: state<=GET_A;
            GET_A: begin
                part_a_l<=history_samples>{2'd0,tap_index} ? memory_q[15:0] : 16'd0;
                part_a_r<=history_samples>{2'd0,tap_index} ? memory_q[31:16] : 16'd0;
                if(tap_index==31) begin
                    aligned_l<=history_samples>31 ? memory_q[47:32] : 16'd0;
                    aligned_r<=history_samples>31 ? memory_q[63:48] : 16'd0;
                end
                state<=READ_B;
            end
            READ_B: begin read_index<=head_index-reverse_age;state<=WAIT_B;end
            WAIT_B: state<=GET_B;
            GET_B: begin
                part_b_l<=history_samples>{1'b0,reverse_age} ? memory_q[15:0] : 16'd0;
                part_b_r<=history_samples>{1'b0,reverse_age} ? memory_q[31:16] : 16'd0;
                state<=PREP_MUL;
            end
            PREP_MUL:state<=MUL_L;
            MUL_L,MUL_R: begin
                product_valid<=1;product_channel<=state==MUL_R;
                state<=state==MUL_L ? MUL_R : NEXT;
            end
            NEXT: begin
                if(tap_index==31) state<=FILTER;
                else begin tap_index<=tap_index+1'b1;state<=READ_A;end
            end
            FILTER: begin
                filtered_l<=(accumulator_l+30'sd2048)>>>12;filtered_r<=(accumulator_r+30'sd2048)>>>12;state<=PEAK;
            end
            PEAK: begin denoised_l<=shared_peak;state<=PEAK_R;end
            PEAK_R: begin denoised_r<=shared_peak;state<=BLEND;end
            BLEND: begin
                state<=BLEND_R;
            end
            BLEND_R: begin blend_l<=product;state<=OUTPUT_SAMPLE;end
            OUTPUT_SAMPLE: begin
                left_out<=saturate($signed(aligned_l)+(blend_l>>>8));right_out<=saturate($signed(aligned_r)+(product>>>8));out_valid<=1;state<=IDLE;
            end
            default: ;
        endcase
    end
end
endmodule

// Same synchronous PDPW primitive pattern as production visualizer memories.
// Valid-history masking in the controller makes uninitialized/stale RAM unreadable.
module reference_repair_history_ram #(parameter PACKED=1)(
    input clk,we,input [5:0] wa,ra,input [63:0] wd,output [63:0] rd
);
`ifdef VICTORY_SIM
reg [63:0] mem[0:63];
reg [63:0] q;
always @(posedge clk) begin q<=mem[ra];if(we) mem[wa]<=wd;end
assign rd=q;
`else
// Same 64x64 history and synchronous latency; widen lanes to avoid
// reserving a separate 512x16 primitive for each 64-word field.
localparam LANE_BITS=PACKED ? 32:16;
localparam LANE_ADDR=PACKED ? 8:9;
localparam LANE_DEPTH=PACKED ? 256:512;
genvar lane;
generate for(lane=0;lane<(PACKED ? 2:4);lane=lane+1) begin: lanes
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(LANE_BITS),.ADDR_WIDTH_A(LANE_ADDR),.DATA_DEPTH_A(LANE_DEPTH),
        .DATA_WIDTH_B(LANE_BITS),.ADDR_WIDTH_B(LANE_ADDR),.DATA_DEPTH_B(LANE_DEPTH),
        .BYTE_ENABLE(0),.MODE("PDPW"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),
        .DEBUGGABLE("NO"),.PACKABLE("NO"),.FORCE_KEEP("OFF"),
        .INIT_FILE("NONE"),.FILL_ALL("NONE"),.IMPLEMENT("9K")
    ) ram9k(
        .doa(),.dob(rd[lane*LANE_BITS+:LANE_BITS]),.dia(wd[lane*LANE_BITS+:LANE_BITS]),.dib({LANE_BITS{1'b0}}),
        .cea(1'b1),.ocea(1'b0),.clka(clk),.wea(we),.rsta(1'b0),
        .ceb(1'b1),.oceb(1'b0),.clkb(clk),.web(1'b0),.rstb(1'b0),
        .bea(1'b0),.beb(1'b0),.addra({{(LANE_ADDR-6){1'b0}},wa}),.addrb({{(LANE_ADDR-6){1'b0}},ra}));
end endgenerate
`endif
endmodule

