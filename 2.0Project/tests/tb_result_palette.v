`timescale 1ns/1ps
module tb_result_palette;
reg clk=0;always #5 clk=~clk;
reg rst=1,ft=0,blue=0,red=0,sprint_select=0;
reg [10:0] x=0;reg [9:0] y=0;reg [23:0] ri=24'hA87532;
wire busy,sprint,de,vs;wire [23:0] rgb;
saixian_battle_result_fx dut(.clk(clk),.rst(rst),.frame_tick(ft),.trigger(1'b0),
.select_blue(blue),.select_red(red),.select_sprint(sprint_select),.x_in(x),.y_in(y),
.de_in(1'b1),.vs_in(1'b0),.rgb_in(ri),.sprint_background_valid(1'b1),
.busy(busy),.sprint_active(sprint),.de_out(de),.vs_out(vs),.rgb_out(rgb));
reg [23:0] scene_rgb;
reg plate, shield, shield_inner, badge_y;
reg [10:0] taper;
always @* begin
    // Separated angled plates, never a full-width rectangular banner.
    plate=(dut.fq>=50 && dut.yq>=242 && dut.yq<496 && dut.diagonal_q<dut.edge_q &&
           ((dut.diagonal_q>=420 && dut.diagonal_q<588 && dut.yq>=260 && dut.yq<474) ||
            (dut.diagonal_q>=608 && dut.diagonal_q<1092) ||
            (dut.diagonal_q>=1112 && dut.diagonal_q<1280 && dut.yq>=260 && dut.yq<474)));
    taper=(dut.yq>=176) ? 11'd224-{1'b0,dut.yq} : 11'd48;
    shield=(dut.fq>=78 && dut.yq>=112 && dut.yq<224 && dut.center_distance_q<=taper);
    shield_inner=(dut.yq>=116 && dut.yq<220 && dut.center_distance_q+11'd4<taper);
    badge_y=(dut.yq>=132 && dut.yq<177 &&
             dut.center_distance_q+(dut.yq-10'd132)/2>=20 &&
             dut.center_distance_q+(dut.yq-10'd132)/2<32) ||
            (dut.yq>=168 && dut.yq<200 && dut.center_distance_q<10) ||
            (dut.yq>=200 && dut.yq<210 && dut.center_distance_q<210-dut.yq);
    scene_rgb=dut.rgb_q;
    if(dut.active_q) begin
        // Restrained dark-blue field; diagonal architecture, not a red/blue split.
        scene_rgb=24'h0B1723;
        if(dut.center_distance_q<448) scene_rgb=24'h0E202E;
        if(dut.center_distance_q<256) scene_rgb=24'h102735;
        if(dut.diagonal_q[7:0]<2) scene_rgb=24'h183341;
        if((dut.yq==46 || dut.yq==674) && dut.xq>=48 && dut.xq<1232) scene_rgb=24'h526574;
        if(dut.fq<65 && (dut.yq==300 || dut.yq==438) && dut.xq>=440 && dut.xq<840)
            scene_rgb=24'h54D5F6;
        if(plate) begin
            scene_rgb=24'h196580;
            if(dut.center_distance_q<448) scene_rgb=24'h1B708C;
            if(dut.center_distance_q<256) scene_rgb=24'h207C97;
            if(dut.diagonal_q[4:0]==0) scene_rgb=24'h2A819B;
            if(dut.yq<244 || dut.yq>=494 || dut.diagonal_q==608 || dut.diagonal_q==1091)
                scene_rgb=24'h54D5F6;
            if(dut.fq>=156 && dut.fq<216 && dut.diagonal_q>=dut.sheen_q && dut.diagonal_q<dut.sheen_q+12'd72)
                scene_rgb=24'h398FA7;
        end
        if(dut.fq>=50 && dut.fq<108 && dut.yq>=218 && dut.yq<520 &&
           dut.diagonal_q>=dut.edge_q && dut.diagonal_q<dut.edge_q+12'd8) scene_rgb=24'hDDF9FF;
        if(shield) scene_rgb=shield_inner ? 24'h0B1723 : 24'h54D5F6;
        if(shield && badge_y) scene_rgb=24'h54D5F6;
        if(dut.fq>=78 && dut.yq>=163 && dut.yq<165 &&
          ((dut.xq>=405 && dut.xq<539) || (dut.xq>=741 && dut.xq<875))) scene_rgb=24'h4098B0;
        if(dut.fq>=130 && dut.yq==590 && dut.xq>=600 && dut.xq<680) scene_rgb=24'h526574;
        // Fixed decorative dashes; final hold has no running counters/motion.
        if((dut.yq==100 && dut.xq>=84 && dut.xq<103) ||
           (dut.yq==536 && dut.xq>=1050 && dut.xq<1063) ||
           (dut.yq==646 && dut.xq>=310 && dut.xq<326)) scene_rgb=24'h276078;
        if(dut.hold_q && dut.yq>=672 && dut.yq<674 && dut.xq>=48 && dut.xq<1232) scene_rgb=24'h54D5F6;
    end
    if(dut.rank_q || dut.podium_q) begin
        // A real running track stays visible behind FPGA-native timing data.
        // When the dedicated TF background is missing, retain a clean dark
        // fallback instead of displaying an unrelated carousel photograph.
        scene_rgb=dut.sprint_background_valid ?
                  {1'b0,dut.rgb_q[23:17],1'b0,dut.rgb_q[15:9],1'b0,dut.rgb_q[7:1]} :
                  24'h0C1825;
        if(dut.result_header_q)
            scene_rgb=24'h163245;
        if(dut.result_header_rule_q)
            scene_rgb=24'h58C4E2;
        // Quiet track-guide lines keep the three result cards grounded.
        if(dut.podium_guide_q)
            scene_rgb=24'h254252;
        if(dut.rank_panel_q) begin
            case(dut.row_q)
                0: scene_rgb=24'h725622;
                1: scene_rgb=24'h506473;
                2: scene_rgb=24'h73503B;
                default: scene_rgb=24'h1D3D51;
            endcase
            if(dut.rank_edge_q)
                scene_rgb=24'h6DB9D1;
            if(dut.rank_stripe_q)
                scene_rgb=24'h28526A;
        end
        if(dut.podium_panel_q) begin
            case(dut.row_q)
                0: scene_rgb=24'h30414A;
                1: scene_rgb=24'h253F50;
                default: scene_rgb=24'h35404A;
            endcase
            if(dut.podium_time_q)
                scene_rgb=24'h182D3A;
            if(dut.podium_edge_q) begin
                case(dut.row_q)
                    0: scene_rgb=24'hE4BD65;
                    1: scene_rgb=24'hBBD4E2;
                    default: scene_rgb=24'hCB916B;
                endcase
            end
            if(dut.gold_line_q)
                scene_rgb=24'hF7D77A;
        end
        // Ceremony-style medal: blue ribbon, faceted rim and a bright centre.
        if(dut.podium_q && dut.row_q<3) begin
            if(dut.medal_ribbon_q) scene_rgb=24'h28648B;
            if(dut.medal_outer_q) begin
                case(dut.row_q)
                    0: scene_rgb=24'hF7D77A;
                    1: scene_rgb=24'hE4EDF2;
                    default: scene_rgb=24'hE3AC7B;
                endcase
            end
            if(dut.medal_inner_q) begin
                case(dut.row_q)
                    0: scene_rgb=24'hD49B20;
                    1: scene_rgb=24'h9EAFB9;
                    default: scene_rgb=24'hB56A38;
                endcase
            end
            if(dut.medal_star_q) scene_rgb=24'hFFF4D0;
        end
        if(dut.result_bottom_rule_q)
            scene_rgb=24'h58C4E2;
    end
end
reg [23:0] expected0=0,expected1=0,expected2=0;
integer n,checks=0,active_checks=0,rank_checks=0,podium_checks=0;
always @(posedge clk) begin
 if(rst) begin expected0=0;expected1=0;expected2=0;end
 else begin expected2=expected1;expected1=expected0;expected0=scene_rgb;end
 #1;
 if(!rst && dut.scene_delay!==expected2) $fatal(1,"palette changed scene: %h expected %h",dut.scene_delay,expected2);
 if(!rst) checks=checks+1;
 if(!rst && dut.active_q) active_checks=active_checks+1;
 if(!rst && dut.rank_q) rank_checks=rank_checks+1;
 if(!rst && dut.podium_q) podium_checks=podium_checks+1;
end
initial begin
 repeat(4) @(negedge clk);rst=0;
 for(n=0;n<150000;n=n+1) begin
  @(negedge clk);ft=(n%128==0);blue=n<128;red=n>=50000 && n<50128;
  sprint_select=n>=100000 && n<100128;
  x=(n*37)%1280;y=(n*11)%720;ri=n*24'h010203;
 end
 repeat(10) @(negedge clk);
 if(active_checks<1000 || rank_checks<1000 || podium_checks<1000) $fatal(1,"insufficient scene coverage %d %d %d",active_checks,rank_checks,podium_checks);
 $display("PASS palette versus original full-RGB scene reference: %d clocks, blue/red/sprint",checks);$finish;
end
endmodule
