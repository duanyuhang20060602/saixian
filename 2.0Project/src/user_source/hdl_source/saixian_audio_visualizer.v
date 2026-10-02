`ifdef VICTORY_SIM
`define AV_ROM_ROOT "src/user_source/hdl_source/"
`else
`define AV_ROM_ROOT "../user_source/hdl_source/"
`endif
// Actual post-volume PCM analysis. All memories are split into <=9K-bit
// chunks so the visualizer does not consume the scarce RAM32K blocks.
module saixian_av_ram #(parameter WIDTH=32, ADDR=10,
    parameter LOW=9, parameter INIT_FILE="")(
    input clk, input we, input [ADDR-1:0] wa,ra,
    input [WIDTH-1:0] wd, output [WIDTH-1:0] rd
);
localparam BANKS=1<<(ADDR-LOW);
wire [WIDTH-1:0] bank_q[0:BANKS-1];
reg [ADDR-LOW:0] bank_sel;
always @(posedge clk) bank_sel<=ra>>LOW;
genvar g;
generate for(g=0;g<BANKS;g=g+1) begin: banks
`ifdef VICTORY_SIM
    reg [WIDTH-1:0] mem[0:(1<<LOW)-1]; /* fehdl force_ram=1, ram_style="bram" */
    reg [WIDTH-1:0] q;
    integer j;
    reg [WIDTH-1:0] init_values[0:(1<<ADDR)-1];
    initial if(INIT_FILE!="") begin
        $readmemh(INIT_FILE,init_values);
        for(j=0;j<(1<<LOW);j=j+1) mem[j]=init_values[(g<<LOW)+j];
    end
    always @(posedge clk) begin
        q<=mem[ra[LOW-1:0]];
        if(we && (wa>>LOW)==g) mem[wa[LOW-1:0]]<=wd;
    end
    assign bank_q[g]=q;
`else
    genvar lane;
    for(lane=0;lane<WIDTH/16;lane=lane+1) begin: lanes
        localparam ROM_FILE=INIT_FILE=="" ? "NONE" :
            {"../",INIT_FILE,(g==0 ? "_0_" : "_1_"),(lane==0 ? "0.mif" : "1.mif")};
        EG_LOGIC_BRAM #(
            .DATA_WIDTH_A(16),.ADDR_WIDTH_A(9),.DATA_DEPTH_A(512),
            .DATA_WIDTH_B(16),.ADDR_WIDTH_B(9),.DATA_DEPTH_B(512),
            .BYTE_ENABLE(0),.MODE("PDPW"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
            .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),
            .DEBUGGABLE("NO"),.PACKABLE("NO"),.FORCE_KEEP("OFF"),
            .INIT_FILE(ROM_FILE),.FILL_ALL("NONE"),.IMPLEMENT("9K")
        ) ram9k(
            .doa(),.dob(bank_q[g][lane*16+:16]),.dia(wd[lane*16+:16]),.dib(16'd0),
            .cea(1'b1),.ocea(1'b0),.clka(clk),.wea(we && (wa>>LOW)==g),.rsta(1'b0),
            .ceb(1'b1),.oceb(1'b0),.clkb(clk),.web(1'b0),.rstb(1'b0),
            .bea(1'b0),.beb(1'b0),.addra(wa[8:0]),.addrb(ra[8:0]));
    end
`endif
end endgenerate
assign rd=bank_q[bank_sel];
endmodule

// Debounce both edges, latch the eligible context at the start of a gesture.
// Leaving that context consumes the gesture until release (no leaked short).
module saixian_av_key3 #(parameter CLK_HZ=75000000, DEBOUNCE_MS=20)(
    input clk,rst,key_n,eligible,input frame_tick,
    output reg short_pulse, output reg mode
);
localparam DB=(CLK_HZ/1000)*DEBOUNCE_MS;
reg meta,sync,stable,tracking,cancelled,fired,pending_mode;
reg [31:0] debounce_count,hold_count;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        meta<=1;sync<=1;stable<=1;tracking<=0;cancelled<=0;fired<=0;
        debounce_count<=0;hold_count<=0;short_pulse<=0;mode<=0;pending_mode<=0;
    end else begin
        meta<=key_n;sync<=meta;short_pulse<=0;
        if(frame_tick && pending_mode && eligible) begin mode<=~mode;pending_mode<=0;end
        if(!eligible) pending_mode<=0;
        if(sync==stable) debounce_count<=0;
        else if(debounce_count==DB-1) begin
            stable<=sync;debounce_count<=0;
            if(!sync) begin tracking<=eligible;cancelled<=!eligible;fired<=0;hold_count<=0;end
            else begin
                if(tracking && !cancelled && !fired && eligible) short_pulse<=1;
                tracking<=0;hold_count<=0;fired<=0;
            end
        end else debounce_count<=debounce_count+1'b1;
        if(tracking && !stable) begin
            if(!eligible) begin cancelled<=1;pending_mode<=0;end
            else if(!cancelled && !fired) begin
                if(hold_count==CLK_HZ-1) begin fired<=1;pending_mode<=1;end
                else hold_count<=hold_count+1'b1;
            end
        end
    end
end
endmodule

module saixian_av_wave(
    input clk,rst,frame_tick,sample_valid,
    input signed [15:0] left,right,
    input [7:0] read_index,output [31:0] read_extrema,
    output reg valid
);
reg capture_bank,display_bank,pending,active,armed;
reg [9:0] wait_samples,sample_count;
reg signed [7:0] lmin,lmax,rmin,rmax;
wire signed [7:0] l=left[15:8],r=right[15:8];
wire trigger=armed && ((left>=16'sd256) || (right>=16'sd256));
wire start_capture=!active && (trigger || wait_samples==10'd1023);
wire signed [7:0] lo_l=(l<lmin)?l:lmin,hi_l=(l>lmax)?l:lmax;
wire signed [7:0] lo_r=(r<rmin)?r:rmin,hi_r=(r>rmax)?r:rmax;
wire write_group=sample_valid && active && !pending && sample_count[1:0]==3;
saixian_av_ram #(.WIDTH(32),.ADDR(9)) wave_ram(
    .clk(clk),.we(write_group),.wa({capture_bank,sample_count[9:2]}),
    .wd({lo_l,hi_l,lo_r,hi_r}),.ra({display_bank,read_index}),.rd(read_extrema));
always @(posedge clk or posedge rst) begin
    if(rst) begin
        capture_bank<=1;display_bank<=0;pending<=0;active<=0;armed<=0;
        wait_samples<=0;sample_count<=0;lmin<=0;lmax<=0;rmin<=0;rmax<=0;valid<=0;
    end else begin
        if(frame_tick && pending) begin
            display_bank<=capture_bank;capture_bank<=~capture_bank;pending<=0;valid<=1;
        end
        if(sample_valid && !pending) begin
            // Arm from either channel; antiphase stereo still triggers.
            if(left<=-16'sd256 || right<=-16'sd256) armed<=1;
            if(start_capture) begin
                active<=1;armed<=0;wait_samples<=0;sample_count<=1;
                lmin<=l;lmax<=l;rmin<=r;rmax<=r;
            end else if(active) begin
                sample_count<=sample_count+1'b1;
                if(sample_count[1:0]==0) begin lmin<=l;lmax<=l;rmin<=r;rmax<=r;end
                else begin lmin<=lo_l;lmax<=hi_l;rmin<=lo_r;rmax<=hi_r;end
                if(sample_count==1023) begin active<=0;pending<=1;wait_samples<=0;armed<=0;end
            end else wait_samples<=wait_samples+1'b1;
        end
    end
end
endmodule

// Radix-2 DIT, bit-reversed input, natural-order output, /2 per stage.
// One registered signed multiplier is reused for window, complex rotation,
// magnitude and band normalization. FFT never backpressures the audio path.
module saixian_av_fft(
    input clk,rst,frame_tick,sample_valid,
    input signed [15:0] left,right,
    input [4:0] read_band,
    output reg [6:0] read_height,read_peak,
    output reg valid,
    output reg block_done
);
reg [9:0] capture_index;
reg pending;
reg signed [25:0] sum_l,sum_r;
reg signed [15:0] mean_l,mean_r,work_mean_l,work_mean_r;
wire signed [26:0] next_sum_l=$signed(sum_l)+$signed(left);
wire signed [26:0] next_sum_r=$signed(sum_r)+$signed(right);
wire [31:0] capture_q;
reg [9:0] load_index;
saixian_av_ram #(.WIDTH(32),.ADDR(10)) capture_ram(
    .clk(clk),.we(sample_valid && !pending),.wa(capture_index),
    .wd({right,left}),.ra(load_index),.rd(capture_q));

localparam IDLE=0,LOAD_WAIT=1,LOAD_GET=2,WIN_WAIT=3,WIN_WRITE=4,
    READ_A=5,WAIT_A=6,GET_A=7,WAIT_B=8,GET_B=9,
    MUL1=10,MUL2=11,MUL3=12,MUL4=13,ROTATE=14,
    WRITE_A=15,WRITE_B=16,NEXT_BFLY=17,
    ENERGY_WAIT=18,ENERGY_GET=19,SQUARE1=20,SQUARE2=21,SQUARE_DONE=22,
    ENERGY_STORE=23,BAND_WAIT=24,BAND_GET=25,BAND_ACC=26,
    NORM1=27,NORM2=28,NORM3=29,NORM4=30,NORM_DONE=31,LOG_ENERGY=32,
    PUBLISH=33,ROT_CALC=34,PREP_WRITE=35,LOG_PREP=36,ROT_IMAG=37,ENERGY_COMB=38;
reg [5:0] state;
reg channel;
reg [3:0] stage;
reg [8:0] butterfly;
reg [9:0] addr_a;
wire [9:0] addr_b=addr_a | (10'd1<<stage);
reg [8:0] next_twiddle;
always @* begin
    case(stage)
        0:begin addr_a={butterfly,1'b0};next_twiddle=0;end
        1:begin addr_a={butterfly[8:1],1'b0,butterfly[0]};next_twiddle={butterfly[0],8'd0};end
        2:begin addr_a={butterfly[8:2],1'b0,butterfly[1:0]};next_twiddle={butterfly[1:0],7'd0};end
        3:begin addr_a={butterfly[8:3],1'b0,butterfly[2:0]};next_twiddle={butterfly[2:0],6'd0};end
        4:begin addr_a={butterfly[8:4],1'b0,butterfly[3:0]};next_twiddle={butterfly[3:0],5'd0};end
        5:begin addr_a={butterfly[8:5],1'b0,butterfly[4:0]};next_twiddle={butterfly[4:0],4'd0};end
        6:begin addr_a={butterfly[8:6],1'b0,butterfly[5:0]};next_twiddle={butterfly[5:0],3'd0};end
        7:begin addr_a={butterfly[8:7],1'b0,butterfly[6:0]};next_twiddle={butterfly[6:0],2'd0};end
        8:begin addr_a={butterfly[8],1'b0,butterfly[7:0]};next_twiddle={butterfly[7:0],1'b0};end
        default:begin addr_a={1'b0,butterfly};next_twiddle=butterfly;end
    endcase
end
reg [8:0] twiddle_index;
wire [31:0] twiddle_q;
wire [15:0] hann_q;
saixian_av_ram #(.WIDTH(32),.ADDR(9),.INIT_FILE({`AV_ROM_ROOT,"saixian_av_twiddle.hex"})) twiddle_rom(
    .clk(clk),.we(1'b0),.wa(9'd0),.wd(32'd0),.ra(twiddle_index),.rd(twiddle_q));
saixian_av_ram #(.WIDTH(16),.ADDR(10),.INIT_FILE({`AV_ROM_ROOT,"saixian_av_hann.hex"})) hann_rom(
    .clk(clk),.we(1'b0),.wa(10'd0),.wd(16'd0),.ra(load_index),.rd(hann_q));
function [9:0] reverse10;
    input [9:0] v;integer b;
    begin for(b=0;b<10;b=b+1) reverse10[b]=v[9-b];end
endfunction
reg [9:0] fft_addr;
wire [31:0] fft_q;
wire fft_we=state==WIN_WRITE || state==WRITE_A || state==WRITE_B;
reg signed [15:0] ar,ai,br,bi;
wire signed [15:0] wr=twiddle_q[31:16],wi=twiddle_q[15:0];
reg signed [31:0] p1,p2,p3;
reg signed [16:0] tr,ti;
reg signed [15:0] out_br,out_bi;
reg signed [15:0] mul_a,mul_b;
reg signed [31:0] product;
always @(posedge clk) product<=mul_a*mul_b;
wire rotate_subtract=state==ROT_CALC;
wire signed [32:0] rotation_a=rotate_subtract ? $signed(p1) : $signed(p3);
wire signed [32:0] rotation_b=rotate_subtract ? $signed(p2) : $signed(product);
wire signed [32:0] rotation_sum=rotation_a+(rotation_b^{33{rotate_subtract}})+rotate_subtract;
wire butterfly_subtract=state==PREP_WRITE;
wire signed [17:0] butterfly_r={{2{ar[15]}},ar}+({tr[16],tr}^{18{butterfly_subtract}})+butterfly_subtract;
wire signed [17:0] butterfly_i={{2{ai[15]}},ai}+({ti[16],ti}^{18{butterfly_subtract}})+butterfly_subtract;
wire [31:0] fft_wd=state==WIN_WRITE ? {16'd0,product[30:15]} :
    state==WRITE_A ? {butterfly_i[16:1],butterfly_r[16:1]} : {out_bi,out_br};
saixian_av_ram #(.WIDTH(32),.ADDR(10)) fft_ram(
    .clk(clk),.we(fft_we),.wa(fft_addr),.wd(fft_wd),.ra(fft_addr),.rd(fft_q));
reg [8:0] energy_index;
reg [31:0] bin_energy;
reg [31:0] lenergy;
wire [31:0] energy_q;
saixian_av_ram #(.WIDTH(32),.ADDR(9)) energy_ram(
    .clk(clk),.we(state==ENERGY_STORE),.wa(energy_index),.wd(bin_energy),
    .ra(energy_index),.rd(energy_q));

reg [4:0] band;
reg [9:0] band_end;
reg [15:0] reciprocal;
reg [31:0] energy_sum;
reg [31:0] normalized;
reg [31:0] add_a,add_b;
wire [31:0] shared_sum=add_a+add_b;
always @* begin
    case(state)
        SQUARE_DONE:begin add_a=p1;add_b=product;end
        ENERGY_COMB:begin add_a=bin_energy>>1;add_b=lenergy>>1;end
        BAND_ACC:begin add_a=energy_sum;add_b=energy_q;end
        NORM4:begin add_a=normalized;add_b=product<<1;end
        default:begin add_a=normalized;add_b=product<<16;end
    endcase
end
reg result_pending;
reg [31:0] band_rom[0:31]; /* fehdl force_ram=1, ram_style="bram" */
reg [31:0] band_q;
initial $readmemh({`AV_ROM_ROOT,"saixian_av_bands.hex"},band_rom);
always @(posedge clk) band_q<=band_rom[band];
// Calibration: Hann coherent gain=.5; FFT is /1024; average stereo
// bin energy E maps to amplitude squared 16*E/(32768^2).
// height = clamp(72 + 3.0103*log2(E) - 78.2678,0,72).
// A six-bit leading mantissa and coarse 12dB steps avoid a wide barrel
// shifter. Register that prefix before the small log table and clamp.
function [12:0] energy_prefix;
    input [31:0] energy;
    begin
        if(|energy[31:28]) energy_prefix={7'd84,energy[31:26]};
        else if(|energy[27:24]) energy_prefix={7'd72,energy[27:22]};
        else if(|energy[23:20]) energy_prefix={7'd60,energy[23:18]};
        else if(|energy[19:16]) energy_prefix={7'd48,energy[19:14]};
        else if(|energy[15:12]) energy_prefix={7'd36,energy[15:10]};
        else if(|energy[11:8]) energy_prefix={7'd24,energy[11:6]};
        else if(|energy[7:4]) energy_prefix={7'd12,energy[7:2]};
        else energy_prefix={7'd0,energy[3:0],2'd0};
    end
endfunction
function [6:0] prefix_height;
    input [12:0] prefix;
    reg [3:0] fraction;
    reg [7:0] sum;
    begin
        case(prefix[5:0])
            0,1,2,3,4,5:fraction=0;
            6:fraction=1;7:fraction=2;
            8,9,10:fraction=3;11,12:fraction=4;
            13,14,15:fraction=5;16,17,18,19,20:fraction=6;
            21,22,23,24,25:fraction=7;
            26,27,28,29,30,31:fraction=8;
            32,33,34,35,36,37,38,39:fraction=9;
            40,41,42,43,44,45,46,47,48,49,50:fraction=10;
            default:fraction=11;
        endcase
        sum={1'b0,prefix[12:6]}+fraction;
        if(sum<=6) prefix_height=0;
        else if(sum>=78) prefix_height=72;
        else prefix_height=sum-6;
    end
endfunction
reg [12:0] log_prefix;
wire [6:0] target_height=prefix_height(log_prefix);
// Serial 32-band smoothing. History is private; pixel reads use a separate
// double-buffered snapshot. Exactly one arithmetic path serves all bars.
reg [1:0] publish_state;
reg [4:0] publish_index;
reg publish_clear,publish_new,write_display_bank,display_bank,snapshot_pending;
reg [31:0] history_write;
reg [15:0] display_write;
wire [31:0] history_q;
wire [15:0] snapshot_q;
wire [15:0] working_target_q;
wire [6:0] next_target=publish_new ? working_target_q[6:0] : history_q[6:0];
wire [6:0] old_height=history_q[13:7],old_peak=history_q[20:14];
wire [4:0] old_hold=history_q[25:21];
wire [6:0] smoothed_height=next_target>=old_height ? next_target : old_height>1 ? old_height-2 : 0;
wire [6:0] smoothed_peak=next_target>=old_peak ? next_target : old_hold!=0 ? old_peak : old_peak!=0 ? old_peak-1'b1 : 0;
wire [4:0] smoothed_hold=next_target>=old_peak ? 5'd18 : old_hold!=0 ? old_hold-1'b1 : 0;
saixian_av_ram #(.WIDTH(32),.ADDR(9)) history_ram(
    .clk(clk),.we(publish_state==3),.wa({4'd0,publish_index}),.wd(history_write),
    .ra({4'd0,publish_index}),.rd(history_q));
saixian_av_ram #(.WIDTH(16),.ADDR(9)) target_ram(
    .clk(clk),.we(state==LOG_ENERGY),.wa({4'd0,band}),.wd({9'd0,target_height}),
    .ra({4'd0,publish_index}),.rd(working_target_q));
saixian_av_ram #(.WIDTH(16),.ADDR(9)) display_ram(
    .clk(clk),.we(publish_state==3),.wa({3'd0,write_display_bank,publish_index}),.wd(display_write),
    .ra({3'd0,display_bank,read_band}),.rd(snapshot_q));
always @* begin
    read_height=valid ? snapshot_q[6:0] : 0;
    read_peak=valid ? snapshot_q[13:7] : 0;
end
always @(posedge clk or posedge rst) begin
    if(rst) begin
        capture_index<=0;pending<=0;
        sum_l<=0;sum_r<=0;mean_l<=0;mean_r<=0;
        state<=IDLE;channel<=0;load_index<=0;stage<=0;butterfly<=0;
        twiddle_index<=0;fft_addr<=0;
        energy_index<=0;
        band<=0;energy_sum<=0;
        result_pending<=0;valid<=0;block_done<=0;
        publish_state<=1;publish_index<=0;publish_clear<=1;publish_new<=0;
        write_display_bank<=1;display_bank<=0;snapshot_pending<=0;
    end else begin
        block_done<=0;
        if(sample_valid && !pending) begin
            sum_l<=next_sum_l;sum_r<=next_sum_r;
            capture_index<=capture_index+1'b1;
            if(capture_index==1023) begin
                mean_l<=next_sum_l>>>10;mean_r<=next_sum_r>>>10;
                pending<=1;sum_l<=0;sum_r<=0;
            end
        end
        if(frame_tick && publish_state==0) begin
            if(snapshot_pending) begin display_bank<=~display_bank;snapshot_pending<=0;valid<=1;end
            write_display_bank<=snapshot_pending ? display_bank : ~display_bank;
            publish_state<=1;publish_index<=0;publish_clear<=0;publish_new<=result_pending;
        end
        case(publish_state)
            1: publish_state<=2;
            2: begin
                history_write<=publish_clear ? 0 : {6'd0,smoothed_hold,smoothed_peak,smoothed_height,next_target};
                display_write<=publish_clear ? 0 : {2'd0,smoothed_peak,smoothed_height};
                publish_state<=3;
            end
            3: if(publish_index==31) begin
                publish_state<=0;snapshot_pending<=1;publish_clear<=0;
                if(publish_new) result_pending<=0;
            end else begin publish_index<=publish_index+1'b1;publish_state<=1;end
        endcase
        case(state)
            IDLE: if(pending && !result_pending) begin
                work_mean_l<=mean_l;work_mean_r<=mean_r;
                channel<=0;load_index<=0;state<=LOAD_WAIT;
            end
            LOAD_WAIT: state<=LOAD_GET;
            LOAD_GET: begin
                // Saturating mean subtraction prevents extreme DC + transient wrap.
                mul_a<=dc_sample(channel ? capture_q[31:16] : capture_q[15:0],channel ? work_mean_r : work_mean_l);
                mul_b<=hann_q;fft_addr<=reverse10(load_index);state<=WIN_WAIT;
            end
            WIN_WAIT: state<=WIN_WRITE;
            WIN_WRITE: if(load_index==1023) begin
                if(channel) pending<=0; // Both channels are now safely copied.
                stage<=0;butterfly<=0;twiddle_index<=0;state<=READ_A;
            end else begin load_index<=load_index+1'b1;state<=LOAD_WAIT;end
            READ_A: begin fft_addr<=addr_a;twiddle_index<=next_twiddle;state<=WAIT_A;end
            WAIT_A: state<=GET_A;
            GET_A: begin ar<=fft_q[15:0];ai<=fft_q[31:16];fft_addr<=addr_b;state<=WAIT_B;end
            WAIT_B: state<=GET_B;
            GET_B: begin br<=fft_q[15:0];bi<=fft_q[31:16];state<=MUL1;end
            MUL1: begin mul_a<=br;mul_b<=wr;state<=MUL2;end
            MUL2: begin mul_a<=bi;mul_b<=wi;state<=MUL3;end
            MUL3: begin p1<=product;mul_a<=br;mul_b<=wi;state<=MUL4;end
            MUL4: begin p2<=product;mul_a<=bi;mul_b<=wr;state<=ROTATE;end
            ROTATE: begin p3<=product;state<=ROT_CALC;end
            ROT_CALC: begin tr<=rotation_sum>>>15;state<=ROT_IMAG;end
            ROT_IMAG: begin ti<=rotation_sum>>>15;state<=PREP_WRITE;end
            PREP_WRITE: begin out_br<=butterfly_r>>>1;out_bi<=butterfly_i>>>1;fft_addr<=addr_a;state<=WRITE_A;end
            WRITE_A: begin fft_addr<=addr_b;state<=WRITE_B;end
            WRITE_B: state<=NEXT_BFLY;
            NEXT_BFLY: begin
                butterfly<=butterfly+1'b1;
                if(butterfly==511) begin
                    if(stage==9) begin energy_index<=1;fft_addr<=1;state<=ENERGY_WAIT;end
                    else begin stage<=stage+1'b1;state<=READ_A;end
                end else state<=READ_A;
            end
            ENERGY_WAIT: state<=ENERGY_GET;
            ENERGY_GET: begin mul_a<=fft_q[15:0];mul_b<=fft_q[15:0];bi<=fft_q[31:16];lenergy<=energy_q;state<=SQUARE1;end
            SQUARE1: begin mul_a<=bi;mul_b<=bi;state<=SQUARE2;end
            SQUARE2: begin p1<=product;state<=SQUARE_DONE;end
            SQUARE_DONE: begin
                bin_energy<=shared_sum;
                state<=channel ? ENERGY_COMB : ENERGY_STORE;
            end
            ENERGY_COMB:begin bin_energy<=shared_sum;state<=ENERGY_STORE;end
            ENERGY_STORE: if(energy_index==511) begin
                if(!channel) begin channel<=1;load_index<=0;state<=LOAD_WAIT;end
                else begin band<=0;energy_index<=1;energy_sum<=0;state<=BAND_WAIT;end
            end else begin energy_index<=energy_index+1'b1;fft_addr<=energy_index+1'b1;state<=ENERGY_WAIT;end
            BAND_WAIT: state<=BAND_GET;
            BAND_GET: begin band_end<=band_q[25:16];reciprocal<=band_q[15:0];state<=BAND_ACC;end
            BAND_ACC: begin
                energy_sum<=shared_sum;
                if({1'b0,energy_index}+1'b1==band_end) state<=NORM1;
                else begin energy_index<=energy_index+1'b1;state<=BAND_WAIT;end
            end
            // Reciprocal is unsigned Q15 (32768 for a one-bin band).
            // Split the 32-bit sum into 15-bit limbs for the signed DSP.
            NORM1: begin mul_a<={1'b0,energy_sum[14:0]};mul_b<=reciprocal>>1;state<=NORM2;end
            NORM2: begin mul_a<={1'b0,energy_sum[29:15]};state<=NORM3;end
            NORM3: begin normalized<=$unsigned(product)>>14;mul_a<={14'd0,energy_sum[31:30]};state<=NORM4;end
            NORM4: begin normalized<=shared_sum;state<=NORM_DONE;end
            NORM_DONE: begin normalized<=shared_sum;state<=LOG_PREP;end
            LOG_PREP: begin log_prefix<=energy_prefix(normalized);state<=LOG_ENERGY;end
            LOG_ENERGY: begin
                if(band==31) state<=PUBLISH;
                else begin band<=band+1'b1;energy_index<=energy_index+1'b1;energy_sum<=0;state<=BAND_WAIT;end
            end
            PUBLISH: begin result_pending<=1;block_done<=1;state<=IDLE;end
        endcase
    end
end
function signed [15:0] dc_sample;
    input signed [15:0] sample,mean;
    reg signed [16:0] d;
    begin d=$signed(sample)-$signed(mean);dc_sample=d>32767 ? 16'sd32767 : d< -32768 ? -16'sd32768 : d[15:0];end
endfunction
endmodule
`undef AV_ROM_ROOT
