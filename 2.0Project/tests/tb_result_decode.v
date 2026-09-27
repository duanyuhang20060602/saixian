`timescale 1ns/1ps
module tb_result_decode;
reg clk=0;always #5 clk=~clk;
reg rst=1;reg rank=0,podium=0;reg [9:0] row=0;
wire busy,sprint,de,vs;wire [23:0] rgb;
saixian_battle_result_fx dut(.clk(clk),.rst(rst),.frame_tick(1'b0),.trigger(1'b0),
 .select_blue(1'b0),.select_red(1'b0),.select_sprint(1'b0),.x_in(11'd0),.y_in(10'd0),
 .de_in(1'b0),.vs_in(1'b0),.rgb_in(24'd0),.sprint_background_valid(1'b1),
 .busy(busy),.sprint_active(sprint),.de_out(de),.vs_out(vs),.rgb_out(rgb));
integer m,v,i,id,origin,shift;
initial begin
    repeat(4) @(negedge clk);rst=0;
    force dut.rank_mode=rank;force dut.podium_mode=podium;force dut.raster_y=row;
    for(m=0;m<3;m=m+1) begin
        rank=(m==1);podium=(m==2);
        for(v=0;v<1024;v=v+1) begin
            row=v;id=8;origin=0;shift=0;
            if(rank) begin
                for(i=0;i<8;i=i+1) if(v>=143+i*55 && v<187+i*55) begin id=i;origin=151+i*55;shift=1200;end
            end else if(podium) begin
                for(i=0;i<3;i=i+1) if(v>=180+i*135 && v<276+i*135) begin id=i;origin=214+i*135;shift=1400;end
            end
            #1;
            if(dut.row_id!==4'(id) || dut.row_y!==10'(origin) || dut.row_shift!==12'(shift))
                $fatal(1,"one-hot band decode mismatch mode=%d y=%d",m,v);
        end
    end
    $display("PASS exhaustive one-hot row decode versus original priority geometry: 3072 cases");$finish;
end
endmodule
