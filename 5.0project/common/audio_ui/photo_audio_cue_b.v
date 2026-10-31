// B-only one-hot cue control. External PCM/metadata are cycle-equivalent
// to the shared A implementation; original sample timing is preserved.
module photo_audio_cue_samples #(
    parameter integer PAGE_STYLES = 0,
    parameter integer CLK_FREQ_HZ    = 25_000_000,
    parameter integer SAMPLE_RATE_HZ = 48_000
)(
    input  wire        clk,
    input  wire        rst,
    input  wire [3:0]  cue_event,
    input wire [3:0] page_style,
    input wire sample_tick,
    output reg         audio_valid,
    output reg  [23:0] audio_left,
    output reg  [23:0] audio_right,
    output reg  [7:0]  audio_level,
    output wire        cue_busy,
    output wire        spectrum_active,
    output wire [4:0]  spectrum_tone_bin
);

localparam CUE_COUNT  = 4'd1;
localparam CUE_START  = 4'd2;
localparam CUE_PAUSE  = 4'd3;
localparam CUE_RESUME = 4'd4;
localparam CUE_FINISH = 4'd5;
localparam CUE_PAGE   = 4'd6;


reg [31:0] phase_acc;
reg [31:0] phase_inc;
reg [16:0] samples_left;
reg [16:0] segment_samples;
reg [2:0]  segment;
reg [6:0] active_flags;reg [3:0] active_style;reg [15:0] page_noise;
reg signed [23:0] pcm;
reg [7:0] envelope;
// The burst interface spaces sample ticks by hundreds of system clocks.
// Register the page waveform/old envelope before the shared multiplier;
// PCM is ready one clock later, before the next sample tick, so audio_left
// retains its original sample alignment. PAGE_STYLES needs ticks >=2 clocks.
reg signed [15:0] wave_q;reg [7:0] envelope_q;reg multiply_pending;
reg [7:0] peak_hold;
reg [10:0] peak_decay_count;

wire [16:0] attack_samples = segment_samples - samples_left;


wire signed [23:0] triangle = phase_acc[31] ?
                              -$signed({1'b0, phase_acc[30:8]}) :
                               $signed({1'b0, phase_acc[30:8]});

// Shared waveform/envelope multiplier for all page styles and legacy cues.
wire page_sound=PAGE_STYLES && active_flags[5];
wire page_rustle=active_style==0 || active_style==8 || active_style==10;
wire page_gate=(active_style==3 && attack_samples[9:8]==3) ||
               (active_style==4 && attack_samples[9]);
wire signed [23:0] rustle=$signed({page_noise,8'd0})>>>2;
wire signed [23:0] page_wave=active_style==0 ? rustle:(triangle>>>1)+(rustle>>>1);
reg [31:0] page_step;
always @*begin
 case(active_style)
  1,5:page_step=32'd50000;2:page_step=32'd25000;7:page_step=32'd60000;
  9:page_step=32'd90000;10:page_step=-32'd14000;default:page_step=0;
 endcase
end
wire signed [23:0] waveform=page_sound ? (page_gate ? 24'sd0:page_rustle ? page_wave:triangle):triangle;

// The cue generator already knows the exact tone being played. Export that
// metadata so the lightweight display can place energy in physical bins
// without implementing a resource-heavy FFT.
assign spectrum_active = (samples_left != 17'd0) && (phase_inc != 32'd0);
// Unlike spectrum_active, cue_busy remains asserted through intentional
// silent gaps between segments, so external sequencing cannot mistake the
// 50 ms gap in the finish cue for the end of the complete sound.
assign cue_busy = (|active_flags);
assign spectrum_tone_bin =
    (phase_inc == 32'd29527900)  ? 5'd3  : // 330 Hz
    (phase_inc == 32'd39370534)  ? 5'd4  : // 440 Hz
    (phase_inc == 32'd59055800)  ? 5'd5  : // 660 Hz
    (phase_inc == 32'd78741067)  ? 5'd7  : // 880 Hz
    (phase_inc == 32'd88583700)  ? 5'd8  : // 990 Hz
    (phase_inc == 32'd118111600) ? 5'd11 : // 1320 Hz
                                   5'd0;

function [31:0] frequency_increment;
    input [15:0] hz;
    begin
        case (hz)
            16'd330 : frequency_increment = 32'd29527900;
            16'd440 : frequency_increment = 32'd39370534;
            16'd660 : frequency_increment = 32'd59055800;
            16'd880 : frequency_increment = 32'd78741067;
            16'd990 : frequency_increment = 32'd88583700;
            16'd1320: frequency_increment = 32'd118111600;
            default: frequency_increment = 32'd0;
        endcase
    end
endfunction

task start_segment;
    input [15:0] hz;
    input [16:0] count;
    begin
        phase_inc       <= frequency_increment(hz);
        samples_left    <= count;
        segment_samples <= count;
        phase_acc       <= 32'd0;
    end
endtask

always @(posedge clk or posedge rst) begin
    if (rst) begin
        
        wave_q<=0;envelope_q<=0;multiply_pending<=0;active_style<=0;page_noise<=16'h1ace;
        phase_acc        <= 32'd0;
        phase_inc        <= 32'd0;
        samples_left     <= 17'd0;
        segment_samples  <= 17'd0;
        segment           <= 3'd0;
        active_flags <= 7'd0;
        pcm               <= 24'sd0;
        audio_valid       <= 1'b0;
        audio_left        <= 24'd0;
        audio_right       <= 24'd0;
        envelope          <= 8'd0;
        audio_level       <= 8'd0;
        peak_hold         <= 8'd0;
        peak_decay_count  <= 11'd0;
    end else begin
        audio_valid <= 1'b0;
        multiply_pending<=PAGE_STYLES && cue_event==0 && sample_tick && samples_left!=0 && phase_inc!=0;
        if(PAGE_STYLES && sample_tick)begin wave_q<=waveform>>>8;envelope_q<=envelope;end
        if(PAGE_STYLES && multiply_pending)pcm<=wave_q*$signed({1'b0,envelope_q});

        if (cue_event != 4'd0) begin
            active_flags <= {cue_event>6,cue_event==6,cue_event==5,cue_event==4,cue_event==3,cue_event==2,cue_event==1};
            segment    <= 3'd0;
            case (cue_event)
                CUE_COUNT : start_segment(16'd880, 17'd5760);   // 120 ms
                CUE_START : start_segment(16'd1320,17'd28800);  // 600 ms
                CUE_PAUSE : start_segment(16'd440, 17'd7200);   // first low pulse
                CUE_RESUME: start_segment(16'd660, 17'd7200);   // rising pair
                CUE_PAGE  : begin
                    active_style<=page_style<=10 ? page_style:4'd0;
                    if(!PAGE_STYLES)start_segment(16'd1320,17'd1440);
                    else case(page_style)
                     0:start_segment(660,2400);  // scroll: paper rustle, 50 ms
                     1:start_segment(330,1920);  // flip: short low sweep
                     2:start_segment(440,3840);  // ribbons: smooth rising tone
                     3:start_segment(880,3456);  // columns: repeated clicks
                     4:start_segment(660,4800);  // accordion: pulsed tone
                     5:start_segment(330,3840);  // metal: low rising sweep
                     6:start_segment(1320,960);  // water: three falling droplets
                     7:start_segment(440,4800);  // portal: rising energy
                     8:start_segment(1320,2880); // glass: high noisy grains
                     9:start_segment(330,5760);  // tunnel: long rising sweep
                     10:start_segment(990,4320); // tear: falling noisy sweep
                     default:start_segment(660,2400);
                    endcase
                end   // Legacy default remains 30 ms.
                CUE_FINISH: start_segment(16'd440, 17'd12000);  // falling pair
                default   : start_segment(16'd0,   17'd1);
            endcase
        end

        else if (sample_tick) begin
            
            audio_valid <= 1'b1;

            if (samples_left != 0 && phase_inc != 0) begin
                phase_acc <= phase_acc + phase_inc;
                if(page_sound)begin
                 page_noise<={page_noise[14:0],page_noise[15]^page_noise[13]^page_noise[12]^page_noise[10]};
                 phase_inc<=phase_inc+page_step;
                end
                samples_left <= samples_left - 17'd1;

                if (samples_left < 17'd480)
                    envelope <= samples_left[8:1];
                else if (attack_samples < 17'd480)
                    envelope <= attack_samples[8:1];
                else
                    envelope <= 8'd220;

                if(!PAGE_STYLES)pcm <= (waveform >>> 8) * $signed({1'b0,envelope});
                audio_left  <= pcm;
                audio_right <= pcm;
            end else begin
                pcm         <= 24'sd0;
                audio_left  <= 24'd0;
                audio_right <= 24'd0;
                envelope    <= 8'd0;

                if(samples_left!=0)begin samples_left<=samples_left-1'b1;end
                else case (1'b1)
                    active_flags[5]:begin
                     if(PAGE_STYLES && active_style==6 && segment<2)begin
                      segment<=segment+1'b1;
                      if(segment==0)start_segment(990,960);else start_segment(660,1440);
                     end else active_flags<=0;
                    end
                    active_flags[2]: begin
                        if (segment == 3'd0) begin
                            segment <= 3'd1;
                            start_segment(16'd0, 17'd4800);
                        end else if (segment == 3'd1) begin
                            segment <= 3'd2;
                            start_segment(16'd440, 17'd7200);
                        end else active_flags <= 7'd0;
                    end
                    active_flags[3]: begin
                        if (segment == 3'd0) begin
                            segment <= 3'd1;
                            start_segment(16'd0, 17'd2400);
                        end else if (segment == 3'd1) begin
                            segment <= 3'd2;
                            start_segment(16'd990, 17'd9600);
                        end else active_flags <= 7'd0;
                    end
                    active_flags[4]: begin
                        if (segment == 3'd0) begin
                            segment <= 3'd1;
                            start_segment(16'd0, 17'd2400);
                        end else if (segment == 3'd1) begin
                            segment <= 3'd2;
                            start_segment(16'd330, 17'd31200);
                        end else active_flags <= 7'd0;
                    end
                    default: active_flags <= 7'd0;
                endcase
            end

            if (pcm[23] ? ((~pcm[22:15]) + 8'd1) > peak_hold : pcm[22:15] > peak_hold)
                peak_hold <= pcm[23] ? ((~pcm[22:15]) + 8'd1) : pcm[22:15];
        end

        if (peak_decay_count == 11'd1999) begin
            peak_decay_count <= 11'd0;
            if (peak_hold != 0)
                peak_hold <= peak_hold - 8'd1;
            audio_level <= peak_hold;
        end else begin
            peak_decay_count <= peak_decay_count + 11'd1;
        end
    end
end

endmodule
