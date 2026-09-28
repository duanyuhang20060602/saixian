`timescale 1ns/1ps
module tb_enhance_numeric;
reg clk=0;always #5 clk=~clk;
reg rst=1,de=0,ft=0;reg [10:0] x=0;reg [9:0] y=0;
reg [23:0] rgb=0;
wire [23:0] out;wire od,ov;wire [10:0] ox;wire [9:0] oy;wire [1:0] gain;
saixian_adaptive_enhance #(.WIDTH(128)) dut(clk,rst,de,1'b0,ft,1'b1,x,y,rgb,2'd1,2'd3,out,od,ov,ox,oy,gain);
integer expected=0,checks=0,i,j,p,t;
always @(posedge clk) begin
    #1;
    if(!rst && od) begin
        if(out !== {8'(expected),8'(expected),8'(expected)})
            $fatal(1,"tone mismatch x=%d y=%d got=%h expected=%d gain=%d",ox,oy,out,expected,gain);
        checks=checks+1;
    end
end
task frame;
    input integer level,next_gain;
    begin
        p=level*(255-level);
        case(gain)
            0:t=0;1:t=p>>10;2:t=p>>9;3:t=(p>>9)+(p>>10);
        endcase
        expected=level+t;if(expected>255) expected=255;
        for(j=0;j<80;j=j+1) begin
            for(i=0;i<128;i=i+1) begin
                @(negedge clk);de=1;x=i;y=j;rgb={8'(level),8'(level),8'(level)};
            end
            @(negedge clk);de=0;repeat(8) @(negedge clk);
        end
        repeat(10) @(negedge clk);ft=1;
        @(negedge clk);ft=0;
        if(gain!==2'(next_gain)) $fatal(1,"adaptive gain mismatch %d expected %d",gain,next_gain);
    end
endtask
initial begin
    repeat(4) @(negedge clk);rst=0;
    frame(32,3);frame(80,2);frame(120,1);frame(200,0);
    frame(0,3);frame(255,0);
    if(checks!=61440) $fatal(1,"numeric pixel count %d",checks);
    $display("PASS adaptive thresholds, fixed-point tone reference, constant-field borders and saturation: %d pixels",checks);
    $finish;
end
endmodule
