`timescale 1ns/1ps
module tb_compact_atlas;
reg clk=0;
reg [11:0] blue_addr=0;
reg [12:0] sprint_addr=0;
wire [31:0] blue,sprint;
reg [31:0] blue_original[0:4095],sprint_original[0:8191];
reg [31:0] blue_expected[0:1],sprint_expected[0:1];
integer i;
always #5 clk=~clk;
saixian_victory_atlas b(clk,blue_addr,blue);
saixian_sprint_atlas s(clk,sprint_addr,sprint);
initial begin
    $readmemh("src/user_source/hdl_source/saixian_victory_atlas.hex",blue_original);
    $readmemh("src/user_source/hdl_source/saixian_sprint_atlas.hex",sprint_original);
    @(negedge clk);
    for(i=0;i<8194;i=i+1) begin
        blue_expected[1]=blue_expected[0];sprint_expected[1]=sprint_expected[0];
        blue_addr=i%4096;sprint_addr=i%8192;
        blue_expected[0]=blue_original[blue_addr];sprint_expected[0]=sprint_original[sprint_addr];
        @(negedge clk);
        if(i>=1 && {blue,sprint}!=={blue_expected[1],sprint_expected[1]})
            $fatal(1,"lossless atlas mismatch/address latency at %d",i);
    end
    $display("PASS all 12288 canonical atlas words with back-to-back addresses and exact two-clock latency");$finish;
end
endmodule
