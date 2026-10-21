`timescale 1ns/1ps
module tb_volume_curve;
reg clk=0,rst=1;
reg [3:0] volume_setting=0;
reg [23:0] audio_left_in=0,audio_right_in=0;
reg [7:0] level_in=255;
wire [23:0] pl,pr,cl,cr;wire [7:0] pm,cm;
integer gain[0:8];integer i,j;
always #5 clk=~clk;
saixian_audio_volume #(.PIPELINE(1)) piped(.clk(clk),.rst(rst),.volume_setting(volume_setting),
    .audio_left_in(audio_left_in),.audio_right_in(audio_right_in),.level_in(level_in),
    .audio_left_out(pl),.audio_right_out(pr),.level_out(pm));
saixian_audio_volume #(.PIPELINE(0)) comb(.clk(clk),.rst(rst),.volume_setting(volume_setting),
    .audio_left_in(audio_left_in),.audio_right_in(audio_right_in),.level_in(level_in),
    .audio_left_out(cl),.audio_right_out(cr),.level_out(cm));
function [23:0] expected;
input signed [23:0] x;input integer g;
reg signed [63:0] v;
begin
    v=x;v=(v*g)>>>3;
    expected=v>8388607 ? 24'h7fffff : v< -8388608 ? 24'h800000 : v[23:0];
end endfunction
task check;
input [23:0] l,r;
begin
    @(negedge clk);audio_left_in=l;audio_right_in=r;volume_setting=i;
    #1;if(cl!==expected($signed(l),gain[i]) || cr!==expected($signed(r),gain[i]))$fatal(1,"combinational gain/saturation level %d",i);
    @(posedge clk);#1;
    if(pl!==expected($signed(l),gain[i]) || pr!==expected($signed(r),gain[i]))$fatal(1,"pipeline gain/saturation level %d",i);
    if(i==0 && (pm!==0 || cm!==0))$fatal(1,"mute meter");
end endtask
initial begin
    gain[0]=0;gain[1]=6;gain[2]=7;gain[3]=8;gain[4]=9;
    gain[5]=10;gain[6]=11;gain[7]=12;gain[8]=13;
    repeat(3)@(negedge clk);rst=0;
    for(i=0;i<=8;i=i+1)begin
        check(24'h7fffff,24'h800000);check(24'h000001,24'hffffff);
        check(24'h100000,24'he00000);check(0,0);
        for(j=0;j<32;j=j+1)check($random,$random);
    end
    $display("PASS all 9 boosted gain levels, level 0 mute, old level 8 at new level 5, signed peaks saturate without wrapping; pipeline and combinational");$finish;
end
endmodule
