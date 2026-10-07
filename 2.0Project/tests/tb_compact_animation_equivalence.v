`timescale 1ns/1ps
module tb_compact_animation_equivalence;
reg clk=0,rst=1,de=0,vs=0;
reg [10:0] x=0;
reg [9:0] y=0;
reg [23:0] rgb=0;
reg [3:0] scene=0;
reg [8:0] phase=0;
reg [7:0] result_phase=0;
reg [11:0] wipe=0,sheen=0;
reg [4:0] drop=0;
reg [10:0] gold=0;
reg red=0;
wire d1,v1,d2,v2;
wire [23:0] c1,c2;
integer i,j,k,checks=0;
reg [31:0] random_word=32'h9327c631;
always #5 clk=~clk;
saixian_battle_result_fx dut(.clk(clk),.rst(rst),.frame_tick(1'b0),.trigger(1'b0),
    .select_blue(1'b0),.select_red(1'b0),.select_sprint(1'b0),.stop(1'b0),
    .x_in(x),.y_in(y),.de_in(de),.vs_in(vs),.rgb_in(rgb),.sprint_background_valid(1'b1),
    .de_out(d1),.vs_out(v1),.rgb_out(c1));
saixian_battle_result_fx_ref ref_dut(.clk(clk),.rst(rst),.frame_tick(1'b0),.trigger(1'b0),
    .select_blue(1'b0),.select_red(1'b0),.select_sprint(1'b0),.stop(1'b0),
    .x_in(x),.y_in(y),.de_in(de),.vs_in(vs),.rgb_in(rgb),.sprint_background_valid(1'b1),
    .de_out(d2),.vs_out(v2),.rgb_out(c2));
always @(posedge clk) begin
    #1;
    if(!rst) begin
        checks=checks+1;
        if({d1,v1,c1}!=={d2,v2,c2}) $fatal(1,"animation differs at scene=%d phase=%d x=%d y=%d got=%h expected=%h",scene,phase,x,y,c1,c2);
    end
end
initial begin
    force dut.state=scene;force ref_dut.state=scene;
    force dut.frame_count=phase;force ref_dut.frame_count=phase;
    force dut.result_frame=result_phase;force ref_dut.result_frame=result_phase;
    force dut.wipe_edge=wipe;force ref_dut.wipe_edge=wipe;
    force dut.sheen_edge=sheen;force ref_dut.sheen_edge=sheen;
    force dut.title_drop=drop;force ref_dut.title_drop=drop;
    force dut.gold_line_edge=gold;force ref_dut.gold_line_edge=gold;
    force dut.red_selected=red;force ref_dut.red_selected=red;
    repeat(5) @(negedge clk);rst=0;
    for(j=0;j<9;j=j+1) for(k=0;k<4;k=k+1) begin
        scene=j;phase=k*97;result_phase=k*53;wipe=k*450;sheen=k*491;drop=k*7;gold=220+k*293;red=j>=7;
        for(i=0;i<16384;i=i+1) begin
            random_word={random_word[30:0],random_word[31]^random_word[21]^random_word[1]^random_word[0]};
            x=random_word[10:0];y=random_word[20:11];rgb=random_word[23:0];
            de=i%19<17;vs=i%997<3;
            @(negedge clk);
        end
    end
    de=0;repeat(12) @(negedge clk);
    $display("PASS %d complete RGB/DE/VS comparisons against accepted uncompressed RTL across 9 scenes and 4 phases",checks);$finish;
end
endmodule
