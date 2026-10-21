// Three cascaded /2 FIR decimators. One shared 16x16 multiplier for stereo.
// All state is local to analysis: never feeds or backpressures audio playback.
// Input spacing >= 1024 clocks. 75 MHz / 48 kHz gives >1562 clocks.
module saixian_av_decimator(
    input clk,rst,sample_valid,
    input signed [15:0] left_in,right_in,
    output reg out_valid,
    output reg signed [15:0] left_out,right_out,
    output reg overrun
);
reg signed [31:0] history[0:95];
reg [4:0] head[0:2];
reg [2:0] phase;
reg [1:0] level;
reg [4:0] tap;
reg [2:0] state;
reg [4:0] anchor;
reg signed [15:0] work_left,work_right;
reg signed [31:0] history_q;
reg signed [15:0] coeff_q;
reg signed [31:0] product_l,product;
reg signed [39:0] acc_l,acc_r;
reg [6:0] clear_index;
reg clearing;
integer i;
wire [4:0] history_tap=anchor-tap;
wire [6:0] history_addr={level,history_tap};
wire signed [39:0] total_l=acc_l+product_l;
wire signed [39:0] total_r=acc_r+product;
function signed [15:0] coefficient;
    input [4:0] index;
    begin case(index)
        5'd0: coefficient=-16'sd4;
        5'd1: coefficient=16'sd0;
        5'd2: coefficient=16'sd35;
        5'd3: coefficient=16'sd0;
        5'd4: coefficient=-16'sd124;
        5'd5: coefficient=16'sd0;
        5'd6: coefficient=16'sd321;
        5'd7: coefficient=16'sd0;
        5'd8: coefficient=-16'sd708;
        5'd9: coefficient=16'sd0;
        5'd10: coefficient=16'sd1441;
        5'd11: coefficient=16'sd0;
        5'd12: coefficient=-16'sd3050;
        5'd13: coefficient=16'sd0;
        5'd14: coefficient=16'sd10281;
        5'd15: coefficient=16'sd16384;
        5'd16: coefficient=16'sd10281;
        5'd17: coefficient=16'sd0;
        5'd18: coefficient=-16'sd3050;
        5'd19: coefficient=16'sd0;
        5'd20: coefficient=16'sd1441;
        5'd21: coefficient=16'sd0;
        5'd22: coefficient=-16'sd708;
        5'd23: coefficient=16'sd0;
        5'd24: coefficient=16'sd321;
        5'd25: coefficient=16'sd0;
        5'd26: coefficient=-16'sd124;
        5'd27: coefficient=16'sd0;
        5'd28: coefficient=16'sd35;
        5'd29: coefficient=16'sd0;
        5'd30: coefficient=-16'sd4;
        default:coefficient=0;
    endcase end
endfunction
function signed [15:0] clip;
    input signed [39:0] value;
    reg signed [39:0] rounded;
    begin
        rounded=(value+40'sd16384)>>>15;
        clip=rounded>32767 ? 16'sd32767 : rounded < -32768 ? -16'sd32768 : rounded[15:0];
    end
endfunction
always @(posedge clk) begin
    history_q<=history[history_addr];
    coeff_q<=coefficient(tap);
    // Stereo multiplication is serialized over two clocks, one physical DSP.
    product<=$signed(state==3 ? history_q[15:0] : history_q[31:16])*coeff_q;
    if(state==4) product_l<=product;
    if(clearing) history[clear_index]<=0;
    else if(state==1) history[{level,head[level]}]<={work_right,work_left};
end
// History is cleared sequentially after reset; reset does not infer 96 reset FFs.
always @(posedge clk or posedge rst) begin
    if(rst) begin
        state<=0;phase<=0;level<=0;tap<=0;anchor<=0;acc_l<=0;acc_r<=0;
        out_valid<=0;left_out<=0;right_out<=0;overrun<=0;
        head[0]<=0;head[1]<=0;head[2]<=0;clearing<=1;clear_index<=0;
        work_left<=0;work_right<=0;
    end else begin
        out_valid<=0;
        if(clearing) begin
            if(clear_index==95) begin clearing<=0;clear_index<=0;end
            else clear_index<=clear_index+1'b1;
        end else begin
            if(sample_valid && state!=0) overrun<=1;
            case(state)
                0:if(sample_valid) begin work_left<=left_in;work_right<=right_in;level<=0;state<=1;end
                1:begin
                    anchor<=head[level];head[level]<=head[level]+1'b1;
                    phase[level]<=~phase[level];tap<=0;acc_l<=0;acc_r<=0;
                    state<=phase[level] ? 2 : 0;
                end
                2:state<=3; // synchronous history/coeff ROM read
                3:state<=4;
                4:state<=5;
                5:begin
                    acc_l<=total_l;acc_r<=total_r;
                    if(tap==30) begin
                        if(level==2) begin
                            left_out<=clip(total_l);right_out<=clip(total_r);out_valid<=1;state<=0;
                        end else begin
                            work_left<=clip(total_l);work_right<=clip(total_r);level<=level+1'b1;state<=1;
                        end
                    end else begin tap<=tap+1'b1;state<=2;end
                end
                default:state<=0;
            endcase
        end
    end
end
endmodule
