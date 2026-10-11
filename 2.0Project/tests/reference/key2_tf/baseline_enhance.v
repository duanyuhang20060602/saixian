module baseline_enhance #(
    parameter integer WIDTH=1280, SPLIT_X=640, PHOTO_SMOOTH=0
)(
    input wire clk,rst,de,vs,frame_tick,statistics_enable,
    input wire [10:0] x,input wire [9:0] y,
    input wire [23:0] rgb_in,input wire [1:0] mode,strength,
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
reg [19:0] stat_sum;
reg [11:0] stat_count;
wire [19:0] stat_count_ext={8'd0,stat_count};
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
always @* begin
    // Preserve low-contrast lettering/texture rather than replacing it with
    // the causal neighborhood average. Keep the existing edge sharpening.
    if(PHOTO_SMOOTH && strength==1) begin
        // Range-gated neighbours have already rejected strong edges.
        // Blend halfway toward the centre-weighted mean. Symmetric rounding
        // avoids the negative-value bias of an arithmetic right shift.
        if(detail>0) detail_term=-((detail+1)>>>1);
        else detail_term=((-detail+1)>>>1);
    end else if(detail>=-3 && detail<=3) detail_term=0;
    else case(strength)
        0:detail_term=0;1:detail_term=detail>>>1;
        2:detail_term=detail;default:detail_term=detail+(detail>>>1);
    endcase
    if(detail_term>12) detail_term=12;
    if(detail_term< -12) detail_term=-12;
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
        if(frame_tick) begin
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